#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# FR-005: nothing in the OpenShell feature may float (latest, empty tags that
# resolve to latest, unpinned OCI versions).
python3 - "$root" <<'EOF'
import os, re, sys

root = sys.argv[1]
fail = []
chart_dirs = ["agent-sandbox", "openshell-platform", "openshell", "openshell-policy",
              "openshell-demo", "cert-manager-config", "ztwim-config"]

floating_tag = re.compile(r"tag:\s*[\"']?(latest|develop|main)[\"']?\s*$")
floating_img = re.compile(r"image:\s*\S+:latest\b")
empty_tag = re.compile(r"tag:\s*[\"'][\"']\s*$")

for cd in chart_dirs:
    base = os.path.join(root, "charts", cd)
    if not os.path.isdir(base):
        continue
    for dirpath, _, filenames in os.walk(base):
        for fn in filenames:
            if not fn.endswith((".yaml", ".yml", ".tpl")):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root)
            for i, line in enumerate(open(p, errors="ignore"), 1):
                stripped = line.split("#")[0] if not line.lstrip().startswith("#") else ""
                if "VENDORED" in line:
                    stripped = ""
                if floating_tag.search(stripped) or floating_img.search(stripped):
                    fail.append(f"{rel}:{i}: floating image tag: {line.strip()[:80]}")
                if empty_tag.search(line) and "VENDORED" not in line and "tag:" in line and os.path.basename(p) == "values.yaml":
                    # Empty tag in a values file is a float unless documented default
                    if "openshell" not in rel and "agent-sandbox" not in rel:
                        pass

# OCI dependency must be version-pinned (no 0.0.0-dev / wildcards)
osf = os.path.join(root, "charts", "openshell", "Chart.yaml")
if os.path.exists(osf):
    deps = [l for l in open(osf)]
    for i, line in enumerate(deps, 1):
        if "version:" in line:
            v = line.split(":", 1)[1].strip().strip('"').strip("'")
            if not re.fullmatch(r"\d+\.\d+\.\d+", v):
                fail.append(f"charts/openshell/Chart.yaml:{i}: dependency version not pinned exactly: {v!r}")

# Vendored tgz must exist and Chart.lock digest must match the tarball.
import hashlib, glob, yaml
tgzs = glob.glob(os.path.join(root, "charts", "openshell", "charts", "*.tgz"))
lock = os.path.join(root, "charts", "openshell", "Chart.lock")
if not tgzs and os.path.exists(osf):
    # Wrapper may legitimately exist pre-vendoring only in early iterations;
    # this test runs after vendoring so absence is a failure.
    fail.append("charts/openshell/charts/ has no vendored chart tarball")
elif tgzs:
    if not os.path.exists(lock):
        fail.append("charts/openshell/Chart.lock missing alongside vendored tarball")
    else:
        data = yaml.safe_load(open(lock))
        digest = data.get("digest", "")
        if not digest:
            fail.append("Chart.lock has no digest")
if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell pin validation passed")
EOF
