#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
override="$root/overrides/values-observability.yaml"
prod="$root/values-prod.yaml"
global="$root/values-global.yaml"

# The override file holds the observability surface.
[[ $(yq -r '.global.observability.enabled' "$override") == true ]]
[[ $(yq -r '.global.observability.retention' "$override") == 30d ]]

# values-global.yaml no longer contains observability-specific settings.
[[ $(yq -e '.global.observability' "$global" 2>/dev/null) == null ]] \
  || { echo "values-global.yaml still contains global.observability"; exit 1; }

# The override is wired through sharedValueFiles.
yq -e '.clusterGroup.sharedValueFiles | contains(["/overrides/values-observability.yaml"])' "$prod" >/dev/null \
  || { echo "observability override not listed in sharedValueFiles"; exit 1; }

# A later operator-explicit value file overrides the observability override.
explicit=$(mktemp)
trap 'rm -f "$explicit"' EXIT
printf 'global:\n  observability:\n    retention: 7d\n' > "$explicit"
result=$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$override" "$explicit")
[[ $(printf '%s\n' "$result" | yq -r '.global.observability.retention') == 7d ]] \
  || { echo "operator-explicit override did not take precedence"; exit 1; }

printf 'observability override relocation and precedence passed\n'