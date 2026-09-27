#!/usr/bin/env bash
# Ensures the locally-installed openshell CLI (brew) matches the openshell
# chartVersion pinned in values-prod.yaml. Client/server protocol in 0.1.x is
# not mixable across minor versions; if this fails, install the required
# version via Makefile:  make install-openshell-cli
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

want=$(python3 - "$root" <<'EOF'
import sys, yaml
prod = yaml.safe_load(open(f"{sys.argv[1]}/values-prod.yaml"))["clusterGroup"]
print(str(prod["applications"]["openshell"]["chartVersion"]))
EOF
)

have=""
if command -v openshell >/dev/null 2>&1; then
  have=$(openshell -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
fi

if [ "$have" != "$want" ]; then
  echo "openshell CLI version mismatch: have '${have:-none}', chart pins '$want'" >&2
  echo "Install the pinned version: make install-openshell-cli" >&2
  exit 1
fi
echo "openshell CLI version check passed ($have)"
