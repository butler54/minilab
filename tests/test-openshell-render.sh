#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Facile prova: after the 007 refactor, upstream charts render at values root
# from external sources, so render-based asserts become merged-values asserts
# over the dial file + per-app override files (contracts/values-layout-contract.md).
python3 - "$root" <<'EOF'
import os, sys, yaml

root = sys.argv[1]
fail = []
load = lambda rel: yaml.safe_load(open(os.path.join(root, rel)))

wg  = load("values-global.yaml")["global"]
dials = load("overrides/values-openshell.yaml")["global"]["openshell"]
gw  = load("overrides/values-openshell-gateway.yaml")
zt  = load("overrides/values-ztwim.yaml")
cm  = load("overrides/values-certmanager.yaml")
asb = load("overrides/values-agent-sandbox.yaml")

zone = wg.get("dnsZone")
host = dials.get("gatewayHostname")
issuer = dials.get("issuer")
trust = dials.get("trustDomain") or zone
ztwim_on = bool(dials.get("ztwim", {}).get("enabled", False))

chk = lambda cond, msg: fail.append(msg) if not cond else None

# dial ⇄ override consistency (contract map)
chk(gw["openshiftRoute"]["host"] == host, "gateway override openshiftRoute.host != gatewayHostname")
chk(gw["certManager"]["serverDnsNames"][0] == host, "serverDnsNames[0] != gatewayHostname")
chk(gw["certManager"]["serverIssuerRef"]["name"] == "acme", "serverIssuerRef.name must be constant 'acme' (007 D5)")

acme = cm["certmgrOperator"]["issuers"][0]["acme"]
expected_server = "https://acme-staging-v02.api.letsencrypt.org/directory" if issuer == "staging" else "https://acme-v02.api.letsencrypt.org/directory"
chk(acme["server"] == expected_server, f"acme.server must track issuer={issuer}: expected {expected_server}")
chk(acme["privateKeySecretRef"]["name"] == f"letsencrypt-{issuer}-account-key", "acme account-key secret must track issuer dial")
chk(acme["email"] == wg.get("acmeEmail"), "acme.email != global.acmeEmail")
chk(acme["solvers"][0]["selector"]["dnsZones"][0] == zone, "acme dnsZones[0] != global.dnsZone")
api_ref = acme["solvers"][0]["dns01"]["cloudflare"]["apiTokenSecretRef"]
chk(api_ref.get("name") == "cloudflare-api-token" and api_ref.get("key") == "api-token", "cloudflare apiTokenSecretRef wrong")

spiffe = gw["server"]["providerTokenGrants"]["spiffe"]["enabled"]
chk(spiffe == ztwim_on, f"spiffe.enabled ({spiffe}) must track ztwim.enabled ({ztwim_on})")

chk(zt["spire"]["trustDomain"] == trust, "spire.trustDomain != openshell.trustDomain-or-dnsZone")

# NVIDIA static pins (carried from 006 D4/D10, migrated to 0.1.x schema)
server = gw["server"]
OSC_VER = "0.1.1"
chk(server.get("telemetryEnabled") is False, "telemetry must be off")
chk(server.get("disableTls") is False, "disableTls required false for passthrough Route")
chk((server.get("credentialStorage") or {}).get("existingSecret") == "openshell-kek", "KEK existingSecret name drifted")
theirs = gw.get("sandbox", {}).get("image", {})
chk(str(theirs.get("digest", "")).startswith("sha256:"), "sandbox.image.digest must be digest-pinned")
for comp in ("gateway", "supervisor", "sandboxRuntime"):
    chk((gw.get(comp) or {}).get("image", {}).get("tag") == OSC_VER, f"{comp}.image.tag must equal {OSC_VER}")
chk((server.get("tls") or {}).get("enableMtls") is False, "tls.enableMtls must be false for OIDC-bearer-only listeners")
oidc = server.get("oidc", {})
chk(oidc.get("issuer", "").startswith("https://keycloak."), "oidc.issuer must point at keycloak IdP")
chk(oidc.get("audience") == "openshell-cli", "oidc.audience drifted")
chk(oidc.get("rolesClaim") == "realm_access.roles", "oidc.rolesClaim must match Keycloak realm role claim")
# rh-keycloak realm consistency with gateway issuer
kc = load("overrides/values-keycloak.yaml")
kc_client = next((c for c in kc["keycloak"]["realms"][0]["clients"] if c["clientId"] == "openshell-cli"), None)
chk(kc_client is not None, "keycloak realm must define openshell-cli client")
chk(kc["keycloak"]["realms"][0]["realm"] == oidc.get("issuer", "").rsplit("/", 1)[-1], "keycloak realm name must match gateway issuer path")
chk(gw.get("agentSandbox", {}).get("preflight", {}).get("enabled") is False, "agentSandbox preflight must be disabled for GitOps rendering")
chk(isinstance(gw.get("podSecurityContext"), dict) and gw["podSecurityContext"].get("fsGroup") is None, "fsGroup must be explicitly null")
chk(isinstance(gw.get("securityContext"), dict) and gw["securityContext"].get("runAsUser") is None, "runAsUser must be explicitly null")
chk(gw.get("openshiftRoute", {}).get("enabled") is True, "openshiftRoute.enabled required")
chk(gw.get("certManager", {}).get("enabled") is True, "certManager.enabled required")

# agent-sandbox values (pinned envelope)
chk(asb["image"]["tag"] == "v1.0.3", "agent-sandbox image.tag != chartVersion")
chk(asb.get("namespace", {}).get("create") is False, "agent-sandbox namespace.create must be false")
chk((asb.get("containerSecurityContext") or {}).get("seccompProfile", {}).get("type") == "RuntimeDefault", "seccomp RuntimeDefault required")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell render (merged-values) validation passed")
EOF
