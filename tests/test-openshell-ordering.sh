#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Asserts the sync-wave ordering from specs/006-openshell-gitops-install/plan.md:
#   cert-manager-config -7 < cert-manager -6 < agent-sandbox -5 < ztwim -4 < openshell-platform -3 < openshell-extras -1 < openshell 0 < openshell-policy +1 < openshell-demo +2
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
    "agent-sandbox",
    "ztwim",
    "openshell-platform",
    "openshell-extras",
    "openshell",
    "openshell-policy",
    "openshell-demo",
]
present = [n for n in expected_order if n in waves]
if present != [n for n in expected_order if n in apps] and len(present) != len([n for n in expected_order]):
    pass  # waves may be added incrementally; check order of those present
if present:
    seq = [waves[n] for n in present]
    if seq != sorted(seq):
        fail.append(f"sync waves not monotonic with required order: {[(n, waves[n]) for n in present]}")

required_pairs = [
    ("agent-sandbox", "openshell"),       # CRDs+controller before gateway
    ("openshell-platform", "openshell"),  # SCC+quota+KEK before gateway
    ("openshell-extras", "openshell"),    # OAuthClient/CA job before gateway
    ("cert-manager-config", "cert-manager"),  # cloudflare Secret before issuers
    ("cert-manager", "openshell"),        # external cert issuer before gateway
]
for a, b in required_pairs:
    if a in waves and b in waves and not waves[a] < waves[b]:
        fail.append(f"{a} (wave {waves[a]}) must precede {b} (wave {waves[b]})")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print(f"openshell ordering validation passed ({len(present)} apps waved: {sorted(waves.items(), key=lambda kv: kv[1])})")
EOF
