#!/usr/bin/env bash
# Inject an opencode config into a live sandbox (idempotent).
# Source of truth: Git (deploy/openshell/demo[/zen]/opencode-*.json).
# Usage: inject-config.sh <sandbox-name> [CONFIG_TEMPLATE] [VERIFY_STRING]
# VERIFY_STRING defaults to the matilda host (008); zen passes "opencode.ai".
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SANDBOX="${1:?usage: inject-config.sh <sandbox-name> [CONFIG_TEMPLATE] [VERIFY_STRING]}"
TEMPLATE="${2:-$root/demo/opencode-matilda.json}"
VERIFY="${3:-matilda.maincode.com}"

[ -f "$TEMPLATE" ] || { echo "config template missing: $TEMPLATE" >&2; exit 1; }
openshell sandbox exec -n "$SANDBOX" -- mkdir -p /sandbox/.config/opencode
openshell sandbox exec -n "$SANDBOX" -- tee /sandbox/.config/opencode/opencode.json < "$TEMPLATE" >/dev/null
openshell sandbox exec -n "$SANDBOX" -- grep -q "$VERIFY" /sandbox/.config/opencode/opencode.json \
  || { echo "injected config missing $VERIFY in $SANDBOX" >&2; exit 2; }
echo "PASS inject ($SANDBOX)"
