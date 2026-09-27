#!/usr/bin/env bash
# Live-auth smoke test for the OpenShell OIDC chain (Keycloak + GitHub IdP).
# Hostnames/issuer are derived from the repo values files, so drift between
# Git state and this test fails loudly.
#
#   make validate-openshell-live        (requires oc access + DNS to cluster)
#
# Contains one XFAIL probe: Keycloak's authorize endpoint currently rejects
# all redirect URIs (RHBK 26.6, observed 2026-09-27). When upstream is fixed
# this probe XPASSes and the script FAILS with instructions to flip it — that
# is intentional: it is the tripwire that says browser login works again.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GATEWAY_NAME="${OPENSHELL_GATEWAY_NAME:-k8s}"

read -r KC_HOST KC_REALM GW_HOST ISSUER AUDIENCE USER_ROLE < <(python3 - "$root" <<'EOF'
import sys, yaml
root = sys.argv[1]
kc = yaml.safe_load(open(f"{root}/overrides/values-keycloak.yaml"))
gw = yaml.safe_load(open(f"{root}/overrides/values-openshell-gateway.yaml"))
realm = kc["keycloak"]["realms"][0]["realm"]
host = kc["keycloak"]["ingress"]["hostname"]
oidc = gw["server"]["oidc"]
print(host, realm, gw["openshiftRoute"]["host"], oidc["issuer"], oidc["audience"], oidc["userRole"])
EOF
) || { echo "failed to derive config from values files"; exit 1; }

fail=()
chk() { # chk <condition-result-0/1> <message>
  if [ "$1" -ne 0 ]; then fail+=("$2"); fi
}

expect_issuer="https://${KC_HOST}/realms/${KC_REALM}"
[ "$ISSUER" = "$expect_issuer" ] || fail+=("gateway oidc.issuer ($ISSUER) != derived $expect_issuer")

# --- 1. discovery
DISC=$(curl -fsS --max-time 10 "https://${KC_HOST}/realms/${KC_REALM}/.well-known/openid-configuration") \
  || fail+=("discovery endpoint unreachable")
if [ -n "${DISC:-}" ]; then
  python3 - "$DISC" "$expect_issuer" <<'EOF' || fail+=("discovery doc issuer/device-endpoint assertion failed")
import sys, json
d = json.loads(sys.argv[1])
assert d["issuer"] == sys.argv[2], f"issuer {d['issuer']} != {sys.argv[2]}"
assert "device_authorization_endpoint" in d, "device_authorization_endpoint not advertised"
assert "urn:ietf:params:oauth:grant-type:device_code" in d["grant_types_supported"], "device_code grant missing"
EOF
fi

# --- 2. JWKS
JWKS_N=$(curl -fsS --max-time 10 "https://${KC_HOST}/realms/${KC_REALM}/protocol/openid-connect/certs" | python3 -c "import sys,json;print(len(json.load(sys.stdin)['keys']))" 2>/dev/null || echo 0)
[ "$JWKS_N" -ge 1 ] || fail+=("JWKS endpoint returned no keys")

# --- 3. device-flow HTTP liveness (anonymous; proves the only working login path stays alive)
CC=$(python3 -c "import hashlib,base64;print(base64.urlsafe_b64encode(hashlib.sha256(b'regression-probe').digest()).decode().rstrip('='))")
DEV=$(curl -fsS --max-time 10 -X POST "https://${KC_HOST}/realms/${KC_REALM}/protocol/openid-connect/auth/device" \
      -d "client_id=openshell-cli" -d "scope=openid" -d "code_challenge=$CC" -d "code_challenge_method=S256" 2>/dev/null) \
  || fail+=("device authorization POST failed")
if [ -n "${DEV:-}" ]; then
  python3 - "$DEV" <<'EOF' || fail+=("device authorization response missing device_code/user_code/verification_uri")
import sys, json
d = json.loads(sys.argv[1])
for k in ("device_code", "user_code", "verification_uri"):
    assert k in d, f"missing {k}"
EOF
fi

# --- 4. XFAIL: redirect_uri acceptance (known RHBK 26.6 bug — flips loud when fixed)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --get "https://${KC_HOST}/realms/${KC_REALM}/protocol/openid-connect/auth" \
  --data-urlencode response_type=code --data-urlencode client_id=openshell-cli \
  --data-urlencode "redirect_uri=http://localhost:54321/callback" \
  --data-urlencode scope=openid -d "code_challenge=$CC" -d "code_challenge_method=S256")
if [ "$CODE" = "400" ]; then
  echo "XFAIL: authorize endpoint still rejects redirect_uri (400) — known RHBK 26.6 bug"
else
  echo "XPASS: authorize endpoint no longer rejects redirect_uri (HTTP $CODE)."
  echo "       The bug is fixed — flip this probe to expect success in $0"
  fail+=("redirect_uri probe XPASS (test needs updating)")
fi

# --- 5. TLS: publicly-trusted chain on both hosts, h2 on the gateway
for h in "$KC_HOST" "$GW_HOST"; do
  ISS=$(echo | openssl s_client -connect "$h:443" -servername "$h" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null)
  echo "$ISS" | grep -q "Let's Encrypt" || fail+=("$h cert issuer not Let's Encrypt: ${ISS:-none}")
done
ALPN=$(echo | openssl s_client -alpn h2 -connect "$GW_HOST:443" -servername "$GW_HOST" 2>/dev/null | grep -i "alpn protocol" )
echo "$ALPN" | grep -qi "h2" || fail+=("gateway endpoint did not negotiate ALPN h2 (gRPC): $ALPN")

# --- 6. negative: protected RPC without token must be denied (Health is anonymous by design)
GC=$(curl -s --http2-prior-knowledge -X POST "https://${GW_HOST}/openshell.v1.OpenShell/GetGatewayInfo" \
     -H "content-type: application/grpc" -o /dev/null -w "%{http_code}|%{header_json}" 2>/dev/null || echo "000|")
case "$GC" in
  401*|*grpc-status\":\[\"7\"]*|*grpc-status\":\[\"16\"]*|*grpc-status\":\ \"7*|*grpc-status\":\ \"16*) : ;;
  000*) fail+=("GetGatewayInfo negative probe failed to connect") ;;
  *) fail+=("GetGatewayInfo without token was NOT denied: $GC") ;;
esac

# --- 7. stored-token shape (skip gracefully when not logged in)
TOK_FILE="$HOME/.config/openshell/gateways/${GATEWAY_NAME}/oidc_token.json"
if [ -f "$TOK_FILE" ]; then
  python3 - "$TOK_FILE" "$expect_issuer" "$AUDIENCE" "$USER_ROLE" <<'EOF' || fail+=("stored token shape assertion failed (see above)")
import sys, json, base64, time
d = json.load(open(sys.argv[1]))
p = d["access_token"].split('.')[1]; p += '=' * (-len(p) % 4)
pl = json.loads(base64.urlsafe_b64decode(p))
assert pl["iss"] == sys.argv[2], f"iss {pl['iss']} != {sys.argv[2]}"
aud = pl.get("aud", []); aud = [aud] if isinstance(aud, str) else aud
assert sys.argv[3] in aud, f"aud {aud} missing {sys.argv[3]}"
roles = pl.get("realm_access", {}).get("roles", [])
assert sys.argv[4] in roles, f"realm_access.roles {roles} missing {sys.argv[4]} — hardcoded IdP mapper regression?"
# openshell-admin IS allowed here (operator-granted post-first-login by design);
# the *IdP mapper* never granting it is enforced offline in test-keycloak-realm.sh.
if "openshell-admin" in roles:
    print("note: token carries operator-granted openshell-admin", file=sys.stderr)
if pl.get("exp", 0) < time.time():
    print("warning: stored token is expired (refresh with: openshell gateway login)", file=sys.stderr)
EOF
else
  echo "skip: no stored token at $TOK_FILE (login with: OPENSHELL_NO_BROWSER=1 openshell gateway login ${GATEWAY_NAME})"
fi

if [ "${#fail[@]}" -gt 0 ]; then
  printf 'FAIL: %s\n' "${fail[@]}" >&2
  exit 1
fi
echo "openshell live-auth smoke validation passed"
