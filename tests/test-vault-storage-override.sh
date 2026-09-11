#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
override="$root/overrides/values-storage-lvm.yaml"
[[ $(yq -r '.vault.server.dataStorage.storageClass' "$override") == lvms-loopback ]]
explicit=$(mktemp)
trap 'rm -f "$explicit"' EXIT
printf 'vault:\n  server:\n    dataStorage:\n      storageClass: approved-external\n' > "$explicit"
result=$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$override" "$explicit")
[[ $(printf '%s\n' "$result" | yq -r '.vault.server.dataStorage.storageClass') == approved-external ]]
printf 'Vault provider default and later explicit override precedence passed\n'
