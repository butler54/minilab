#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/openshell-platform"

rendered=$(helm template openshell-platform "$chart" -f "$root/values-global.yaml" -f "$root/overrides/values-openshell.yaml" \
  --set 'global.openshell.enabled=true' --set 'global.openshell.sandbox.maxConcurrent=3')

echo "$rendered" | python3 -c '
import sys, yaml

docs = [d for d in yaml.safe_load_all(sys.stdin) if d]
quota = next((d for d in docs if d.get("kind") == "ResourceQuota"), None)
limit = next((d for d in docs if d.get("kind") == "LimitRange"), None)
assert quota, "ResourceQuota missing"
assert limit, "LimitRange missing"

# Envelope for maxConcurrent=3: pods=20, cpu=8, mem=16Gi (see capacity.yaml formula).
hard = quota["spec"]["hard"]
assert hard["pods"] == "20", f"pods quota {hard.get('pods')}"
assert hard["requests.cpu"] == "8", f"cpu quota {hard.get('requests.cpu')}"
assert hard["requests.memory"] == "16Gi", f"mem quota {hard.get('requests.memory')}"

entry = next((e for e in limit["spec"]["limits"] if e.get("type") == "Container"), None)
assert entry, "LimitRange has no Container entry"
for key in ("defaultRequest", "default", "max"):
    assert key in entry and "cpu" in entry[key] and "memory" in entry[key], f"LimitRange.{key} incomplete"

# maxConcurrent=5 must scale the quota accordingly (pods=24, cpu=12, mem=24Gi).
' || exit 1

scaled=$(helm template openshell-platform "$chart" -f "$root/values-global.yaml" -f "$root/overrides/values-openshell.yaml" \
  --set 'global.openshell.enabled=true' --set 'global.openshell.sandbox.maxConcurrent=5')
pods=$(echo "$scaled" | python3 -c '
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get("kind") == "ResourceQuota":
        print(d["spec"]["hard"]["pods"])
')
[ "$pods" = "24" ] || { echo "quota did not scale with maxConcurrent=5 (pods=$pods)"; exit 1; }

# Disabled feature renders nothing (force off regardless of committed dials).
off=$(helm template openshell-platform "$chart" -f "$root/values-global.yaml" -f "$root/overrides/values-openshell.yaml" --set 'global.openshell.enabled=false')
count=$(echo "$off" | python3 -c '
import sys, yaml
print(sum(1 for d in yaml.safe_load_all(sys.stdin) if d))
')
[ "$count" -eq 0 ] || { echo "openshell-platform rendered while openshell.enabled=false"; exit 1; }

printf 'openshell quota validation passed\n'
