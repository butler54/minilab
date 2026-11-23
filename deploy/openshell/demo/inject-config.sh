#!/usr/bin/env bash
# Inject an opencode config into a live sandbox (idempotent).
# Source of truth: Git (deploy/openshell/demo[/zen]/opencode-*.json).
# Usage: inject-config.sh <sandbox-name> [CONFIG_TEMPLATE] [VERIFY_STRING]
# VERIFY_STRING defaults to the matilda host (008); zen passes "opencode.ai".
#
# Env: GATEWAY (default minilab). Usually inherited from the parent demo
# driver; set here too so standalone invocations hit the cluster gateway and
# never the CLI's active (local podman) default — the topology-correction
# root cause (docs/hermes-agent.md).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GATEWAY="${GATEWAY:-minilab}"
export OPENSHELL_GATEWAY="$GATEWAY"
SANDBOX="${1:?usage: inject-config.sh <sandbox-name> [CONFIG_TEMPLATE] [VERIFY_STRING]}"
TEMPLATE="${2:-$root/demo/opencode-matilda.json}"
VERIFY="${3:-matilda.maincode.com}"

[ -f "$TEMPLATE" ] || { echo "config template missing: $TEMPLATE" >&2; exit 1; }
openshell sandbox exec -n "$SANDBOX" -- mkdir -p /sandbox/.config/opencode
openshell sandbox exec -n "$SANDBOX" -- tee /sandbox/.config/opencode/opencode.json < "$TEMPLATE" >/dev/null
openshell sandbox exec -n "$SANDBOX" -- grep -q "$VERIFY" /sandbox/.config/opencode/opencode.json \
  || { echo "injected config missing $VERIFY in $SANDBOX" >&2; exit 2; }
echo "PASS inject ($SANDBOX)"
