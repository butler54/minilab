#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Asserts the sync-wave ordering from specs/006-openshell-gitops-install/plan.md
# plus the rh-keycloak chain added for OIDC:
#   cert-manager-config -7 < cert-manager -6 < ztwim -4 < openshell-platform -3 < openshell-keycloak-config -3 < rh-keycloak -2 < openshell 0 < openshell-policy +1 < openshell-demo +2
# agent-sandbox was removed from the wave chain when it switched from the
# upstream helm application to the downstream OLM subscription (OLM owns the
# CRD lifecycle; Subscriptions are applied by the clustergroup before app
# sync waves begin).
python3 - "$root" <<'EOF'
import sys, yaml

root = sys.argv[1]
prod = yaml.safe_load(open(f"{root}/values-prod.yaml"))["clusterGroup"]
apps = prod.get("applications", {})
fail = []

waves = {}
for name, app in apps.items():
    ann = (app.get("annotations") or {}).get("argocd.argoproj.io/sync-wave")
    if ann is not None:
        waves[name] = int(ann)

expected_order = [
    "cert-manager-config",
    "cert-manager",
    "ztwim",
    "openshell-platform",
    "openshell-keycloak-config",
    "rh-keycloak",
    "openshell",
    "openshell-policy",
    "openshell-demo",
]
present = [n for n in expected_order if n in waves]
if present:
    seq = [waves[n] for n in present]
    if seq != sorted(seq):
        fail.append(f"sync waves not monotonic with required order: {[(n, waves[n]) for n in present]}")

required_pairs = [
    ("openshell-platform", "openshell"),  # SCC+quota+KEK before gateway
    ("cert-manager-config", "cert-manager"),  # cloudflare Secret before issuers
    ("openshell-keycloak-config", "rh-keycloak"),  # IdP TLS cert before Keycloak
    ("rh-keycloak", "openshell"),         # IdP must exist before OIDC gateway
    ("cert-manager", "openshell"),        # external cert issuer before gateway
]
for a, b in required_pairs:
    if a in waves and b in waves and not waves[a] < waves[b]:
        fail.append(f"{a} (wave {waves[a]}) must precede {b} (wave {waves[b]})")

# Subscriptions for the operator-backed components must exist.
sub_map = prod.get("subscriptions", {})
if isinstance(sub_map, dict) and "rhbk" not in sub_map:
    fail.append("subscriptions.rhbk (rhbk-operator) missing — rh-keycloak needs RHBK operator")
if isinstance(sub_map, dict) and "agent-sandbox" not in sub_map:
    fail.append("subscriptions.agent-sandbox (Red Hat build, agent-sandbox-operator) missing — openshell needs the agents.x-k8s.io CRDs")
nsmap = prod.get("namespaces", {})
if "keycloak-system" not in nsmap:
    fail.append("namespaces.keycloak-system missing")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print(f"openshell ordering validation passed ({len(present)} apps waved: {sorted(waves.items(), key=lambda kv: kv[1])})")
EOF
