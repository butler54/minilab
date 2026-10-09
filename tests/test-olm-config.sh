#!/usr/bin/env bash
# Feature 010 US4: olm-config chart renders OLMConfig/cluster with
# disableCopiedCSVs enabled (the change is GitOps-reconciled, not live-only).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

rendered=$(helm template olm-config "$root/charts/olm-config")
name=$(echo "$rendered" | yq e 'select(.kind == "OLMConfig") | .metadata.name' -)
[ "$name" = "cluster" ] || { echo "expected OLMConfig/cluster, got '$name'"; exit 1; }
flag=$(echo "$rendered" | yq e 'select(.kind == "OLMConfig") | .spec.features.disableCopiedCSVs' -)
[ "$flag" = "true" ] || { echo "disableCopiedCSVs=$flag (expect true)"; exit 1; }

python3 - "$root/values-prod.yaml" <<'PY'
import sys, yaml

apps = (yaml.safe_load(open(sys.argv[1])).get("clusterGroup") or {}).get("applications") or {}
app = apps.get("olm-config")
if not app:
    sys.exit("clusterGroup.applications['olm-config'] missing from values-prod.yaml")
PY

echo "olm config validation passed"
