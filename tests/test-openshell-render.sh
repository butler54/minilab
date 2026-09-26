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

# NVIDIA static pins (carried from 006 D4/D10)
server, sup = gw["server"], gw["supervisor"]
chk(server.get("telemetryEnabled") is False, "telemetry must be off")
chk(sup.get("sideloadMethod") == "init-container", "supervisor.sideloadMethod must be init-container")
chk(server.get("disableTls") is False, "disableTls required false for passthrough Route")
chk((server.get("credentialStorage") or {}).get("existingSecret") == "openshell-kek", "KEK existingSecret name drifted")
chk("@sha256:" in (server.get("sandboxImage") or ""), "sandboxImage must be digest-pinned")
chk(gw["image"].get("tag") == "0.0.116" and sup["image"].get("tag") == "0.0.116", "gateway/supervisor image tags must equal 0.0.116")
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
