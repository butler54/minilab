#!/usr/bin/env bash
# Feature 010 US2 / argocd-cadence-contract: values-global.yaml pins the ArgoCD
# reconciliation cadence to 600s through the patterns-operator customArgoYaml
# seam, without regressing the gitops operatorSource/channel baseline.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$root/values-global.yaml" <<'PY'
import sys, yaml

vg = yaml.safe_load(open(sys.argv[1]))
gitops = (vg.get("main") or {}).get("gitops") or {}

if gitops.get("channel") != "gitops-1.21":
    sys.exit("gitops.channel regressed or missing (expect gitops-1.21): %r" % gitops.get("channel"))
if gitops.get("operatorSource") != "redhat-operators":
    sys.exit("gitops.operatorSource regressed or missing (expect redhat-operators): %r" % gitops.get("operatorSource"))

custom = gitops.get("customArgoYaml")
if not custom:
    sys.exit("main.gitops.customArgoYaml absent — 600s cadence pin missing")
inner = yaml.safe_load(custom)
recon = ((inner or {}).get("extraConfig") or {}).get("timeout.reconciliation")
if str(recon) != "600s":
    sys.exit("customArgoYaml timeout.reconciliation=%r (expect '600s')" % recon)
PY

echo "argocd cadence validation passed"
