#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# FR-005/FR-006: nothing in the OpenShell feature may float — images pinned in
# override files, ExternalChartRef versions exact in values-prod.yaml.
python3 - "$root" <<'EOF'
import os, re, sys, yaml

root = sys.argv[1]
fail = []

floating_tag = re.compile(r"tag:\s*[\"']?(latest|develop|main)[\"']?\s*$")
floating_img = re.compile(r"image:\s*\S+:(latest|develop|main)\b")

# 1. No floating image refs in any override file or pattern-owned chart values.
scan_roots = ["overrides", "charts"]
for sr in scan_roots:
    for dirpath, _, filenames in os.walk(os.path.join(root, sr)):
        for fn in filenames:
            if not fn.endswith((".yaml", ".yml", ".tpl")) or fn == "values-secret.yaml.template":
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root)
            for i, line in enumerate(open(p, errors="ignore"), 1):
                if line.lstrip().startswith("#"):
                    continue
                code = line.split("#")[0]
                if floating_tag.search(code) or floating_img.search(code):
                    fail.append(f"{rel}:{i}: floating image tag: {line.strip()[:80]}")

# 2. Feature charts' ExternalChartRefs: exact versions (no ranges/floats).
prod = yaml.safe_load(open(os.path.join(root, "values-prod.yaml")))["clusterGroup"]
for key in ("openshell", "agent-sandbox", "cert-manager", "ztwim", "rh-keycloak"):
    app = prod.get("applications", {}).get(key, {})
    v = str(app.get("chartVersion", ""))
    if not (re.fullmatch(r"\d+\.\d+\.\d+", v) or re.fullmatch(r"v\d+\.\d+\.\d+", v)):
        fail.append(f"applications.{key}.chartVersion must be an exact version, got {v!r}")

# 3. Feature images use concrete tags or digests (checks known pinned entries).
gw = yaml.safe_load(open(os.path.join(root, "overrides/values-openshell-gateway.yaml")))
OSC_VER = "0.1.1"
img = gw.get("gateway", {}).get("image", {}).get("tag", "")
sup = (gw.get("supervisor", {}) or {}).get("image", {}).get("tag", "")
rt = (gw.get("sandboxRuntime", {}) or {}).get("image", {}).get("tag", "")
if img != OSC_VER or sup != OSC_VER or rt != OSC_VER:
    fail.append(f"gateway/supervisor/sandboxRuntime tags must be {OSC_VER} (got {img!r}/{sup!r}/{rt!r})")
sandbox_img = (gw.get("sandbox", {}) or {}).get("image", {}).get("digest", "")
if not sandbox_img.startswith("sha256:"):
    fail.append("sandbox.image must be digest-pinned")
asb = yaml.safe_load(open(os.path.join(root, "overrides/values-agent-sandbox.yaml")))
if asb.get("image", {}).get("tag") != "v1.0.3":
    fail.append("agent-sandbox image.tag must equal its pinned chart version")
demo = yaml.safe_load(open(os.path.join(root, "charts", "openshell-demo", "values.yaml")))
hi = demo.get("demo", {}).get("harnessImage", "")
if "@sha256:" not in hi:
    fail.append("demo harnessImage must be digest-pinned")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell pin validation passed")
EOF
