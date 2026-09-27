#!/usr/bin/env bash
# Inject the matilda opencode config into a live sandbox (idempotent).
# Source of truth: Git (deploy/openshell/demo/opencode-matilda.json).
# Usage: inject-config.sh <sandbox-name> [CONFIG_TEMPLATE]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SANDBOX="${1:?usage: inject-config.sh <sandbox-name> [CONFIG_TEMPLATE]}"
TEMPLATE="${2:-$root/demo/opencode-matilda.json}"

[ -f "$TEMPLATE" ] || { echo "config template missing: $TEMPLATE" >&2; exit 1; }
openshell sandbox exec -n "$SANDBOX" -- mkdir -p /sandbox/.config/opencode
openshell sandbox exec -n "$SANDBOX" -- tee /sandbox/.config/opencode/opencode.json < "$TEMPLATE" >/dev/null
openshell sandbox exec -n "$SANDBOX" -- grep -q "matilda.maincode.com" /sandbox/.config/opencode/opencode.json \
  || { echo "injected config missing matilda.maincode.com in $SANDBOX" >&2; exit 2; }
echo "PASS inject ($SANDBOX)"
