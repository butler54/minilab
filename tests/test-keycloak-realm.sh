#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Keycloak realm values guards (V-AUTH learnings, 2026-09-27):
#   - device-flow grant is the ONLY working login path (redirect_uri 400 bug,
#     see tests/test-openshell-auth-smoke.sh) — both realm-level and
#     client-level flags must stay on.
#   - Keycloak's hardcoded-role IdP mapper requires config key `role`;
#     `role.value` is silently ignored (observed on RHBK 26.6).
#   - openshell-admin must NEVER be granted via IdP mappers (any GitHub
#     account could log in) — operator assigns it manually post-first-login.
python3 - "$root" <<'EOF'
import os, sys, yaml, json

root = sys.argv[1]
fail = []
chk = lambda cond, msg: fail.append(msg) if not cond else None

# Realm JSON is nested YAML on the keycloak:* keys in overrides/values-keycloak.yaml.
kc = yaml.safe_load(open(os.path.join(root, "overrides/values-keycloak.yaml")))
realm = kc["keycloak"]["realms"][0]

chk(realm["realm"] == "openshell", "realm name must be 'openshell'")
chk(realm.get("enabled") is True, "realm must be enabled")
chk(realm.get("registrationAllowed") is False, "realm registrationAllowed must be false")
attrs = realm.get("attributes", {})
chk(attrs.get("oauth2DeviceAuthorizationGrantEnabled") == "true",
    "realm attributes.oauth2DeviceAuthorizationGrantEnabled must be 'true'")

# --- roles
role_names = [r["name"] for r in realm.get("roles", {}).get("realm", [])]
chk("openshell-admin" in role_names, "realm role openshell-admin missing")
chk("openshell-user" in role_names, "realm role openshell-user missing")

# --- client
client = next((c for c in realm.get("clients", []) if c.get("clientId") == "openshell-cli"), None)
chk(client is not None, "client openshell-cli missing")
if client:
    chk(client.get("publicClient") is True, "openshell-cli must be a public client")
    chk(client.get("standardFlowEnabled") is True, "openshell-cli standardFlowEnabled must be true")
    chk(client.get("implicitFlowEnabled") is False, "openshell-cli implicitFlowEnabled must be false")
    chk(client.get("directAccessGrantsEnabled") is False,
        "openshell-cli directAccessGrantsEnabled must be false")
    cattrs = client.get("attributes", {})
    chk(cattrs.get("pkce.code.challenge.method") == "S256",
        "openshell-cli pkce.code.challenge.method must be S256")
    chk(cattrs.get("oauth2.device.authorization.grant.enabled") == "true",
        "openshell-cli oauth2.device.authorization.grant.enabled must be 'true' (device flow is the only working login path)")
    mappers = client.get("protocolMappers", [])
    aud = next((m for m in mappers if m.get("protocolMapper") == "oidc-audience-mapper"), None)
    chk(aud is not None, "openshell-cli audience protocol mapper missing")
    if aud:
        cfg = aud.get("config", {})
        chk(cfg.get("included.client.audience") == "openshell-cli",
            "audience mapper included.client.audience must be openshell-cli")
        chk(cfg.get("access.token.claim") == "true", "audience mapper must set access.token.claim")
        chk(cfg.get("id.token.claim") == "false", "audience mapper id.token.claim must be false")

# --- IdP federation
idps = realm.get("identityProviders", [])
gh = next((i for i in idps if i.get("alias") == "github"), None)
chk(gh is not None, "github identityProvider missing")
if gh:
    chk(gh.get("providerId") == "github", "github IdP providerId drifted")
    chk(gh.get("enabled") is True, "github IdP must be enabled")
    cfg = gh.get("config", {})
    cid, csec = cfg.get("clientId", ""), cfg.get("clientSecret", "")
    chk(cid == "${GITHUB_CLIENT_ID}", "github clientId must remain the ${GITHUB_CLIENT_ID} placeholder")
    chk(csec == "${GITHUB_CLIENT_SECRET}", "github clientSecret must remain the ${GITHUB_CLIENT_SECRET} placeholder")

# --- IdP role mappers (the silent-ignore trap: key must be `role`)
all_text = json.dumps(realm)
mappers = realm.get("identityProviderMappers", [])
chk(len(mappers) >= 1, "expected at least one identityProviderMapper")
for m in mappers:
    mcfg = m.get("config", {})
    if "role.value" in mcfg:
        fail.append("identityProviderMapper uses config key 'role.value' — Keycloak ignores it; use 'role'")
    if "role" in mcfg:
        chk(mcfg["role"] == "openshell-user",
            f"hardcoded IdP mapper '{m.get('name')}' must grant openshell-user, got {mcfg['role']!r}")
chk('"openshell-admin"' not in json.dumps(mappers),
    "openshell-admin must never appear in IdP mapper config (manual grant only)")

# --- gateway-side OIDC consistency (cross-file)
gw = yaml.safe_load(open(os.path.join(root, "overrides/values-openshell-gateway.yaml")))
oidc = gw["server"]["oidc"]
krname = realm["realm"]
kchost = kc["keycloak"]["ingress"]["hostname"]
chk(oidc["issuer"] == f"https://{kchost}/realms/{krname}",
    f"gateway oidc.issuer must equal https://{kchost}/realms/{krname}")
chk(oidc.get("audience") == "openshell-cli",
    "gateway oidc.audience must equal openshell-cli (mapper included.client.audience)")
chk(oidc.get("adminRole") in role_names, f"gateway oidc.adminRole {oidc.get('adminRole')!r} not a realm role")
chk(oidc.get("userRole") in role_names, f"gateway oidc.userRole {oidc.get('userRole')!r} not a realm role")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("keycloak realm guard validation passed")
EOF
