#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# SC-001/SC-002 proofs (specs/007-openshell-external-charts quickstart V-SRC):
#   a) no upstream chart content under charts/
#   b) the four ExternalChartRefs carry EXACT pins matching the registry contract
#   c) agent-sandbox pin matches immutable tag form
#   d) every override file referenced by the four apps exists
python3 - "$root" <<'EOF'
import os, re, sys, yaml

root = sys.argv[1]
fail = []

# --- (a) charts/ census: nothing upstream-shaped allowed
for dirpath, dirnames, filenames in os.walk(os.path.join(root, "charts")):
    rel = os.path.relpath(dirpath, root)
    for fn in filenames:
        p = os.path.join(dirpath, fn)
        if fn.endswith(".tgz"):
            fail.append(f"{os.path.relpath(p, root)}: packaged chart archive present")
        if fn == "Chart.yaml":
            meta = yaml.safe_load(open(p))
            deps = (meta or {}).get("dependencies") or []
            if deps:
                fail.append(f"{rel}/Chart.yaml: wrapper-style OCI/git dependencies not allowed (use ExternalChartRef instead): {[d.get('name') for d in deps]}")
    base = os.path.basename(dirpath)
    if base == "crds" and "agent-sandbox-rc" in dirpath or base == "crds":
        fail.append(f"{rel}: vendored CRD directory present")

# Known upstream-content signatures that must never be committed
sig_patterns = [
    (re.compile(r"agents\.x-k8s\.io/v1beta1"), "agent-sandbox CRD content"),
    (re.compile(r"NVIDIA CORPORATION.*SPDX", re.I), "upstream NVIDIA chart template"),
]
for dirpath, dirnames, filenames in os.walk(os.path.join(root, "charts")):
    for fn in filenames:
        if not fn.endswith((".yaml", ".yml", ".tpl")):
            continue
        p = os.path.join(dirpath, fn)
        text = open(p, errors="ignore").read()
        for rx, label in sig_patterns:
            if rx.search(text):
                fail.append(f"{os.path.relpath(p, root)}: {label} detected")

# --- (b)+(c) ExternalChartRef pins
prod = yaml.safe_load(open(os.path.join(root, "values-prod.yaml")))["clusterGroup"]
apps = prod.get("applications", {})
expected = {
    "openshell": {"chart": "helm-chart", "repoURL": "ghcr.io/nvidia/openshell", "chartVersion": "0.0.116"},
    "agent-sandbox": {"path": "helm", "repoURL": "https://github.com/kubernetes-sigs/agent-sandbox", "chartVersion": "v1.0.3"},
    "cert-manager": {"chart": "ocp-certmanager", "chartVersion": "0.2.0"},
    "ztwim": {"chart": "ztwim", "chartVersion": "0.1.1"},
}
for key, want in expected.items():
    app = apps.get(key)
    if not app:
        fail.append(f"values-prod.yaml applications.{key} missing")
        continue
    for field, val in want.items():
        got = app.get(field)
        if field == "chartVersion":
            got = str(app.get(field))
            if got != val:
                fail.append(f"applications.{key}.chartVersion must be exactly {val}, got {got!r}")
        elif got != val:
            fail.append(f"applications.{key}.{field} must be {val!r}, got {got!r}")
    extra = app.get("extraValueFiles", [])
    for f in extra:
        if not os.path.exists(os.path.join(root, f.lstrip("/"))):
            fail.append(f"applications.{key}.extraValueFiles references missing file: {f}")

asb = apps.get("agent-sandbox", {})
v = str(asb.get("chartVersion", ""))
if v and not re.fullmatch(r"v\d+\.\d+\.\d+", v):
    fail.append(f"agent-sandbox chartVersion {v!r} must be an immutable release tag (vMAJOR.MINOR.PATCH)")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("external chart reference validation passed")
EOF
