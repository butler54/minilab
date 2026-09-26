#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Downscoped post-refactor (007): upstream SPIRE CRs now come from the VP
# `ztwim` chart (its own CI covers them). This suite asserts what's OURS:
# the ClusterSPIFFEID workload registration shape, the ztwim.enabled gate on
# pattern-owned content, and the values intent carried in overrides/values-ztwim.yaml.
python3 - "$root" <<'EOF'
import subprocess, sys, yaml

root = sys.argv[1]
fail = []

def render(chart_dir, kwsets=None):
    cmd = ["helm", "template", chart_dir, f"{root}/charts/{chart_dir}",
           "-f", f"{root}/values-global.yaml",
           "-f", f"{root}/overrides/values-openshell.yaml",
           "--set", "global.openshell.enabled=true",
           "--set", "global.openshell.ztwim.enabled=true"]
    cmd += kwsets or []
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        fail.append(f"helm template {chart_dir} failed: {out.stderr.strip()[:300]}")
        return []
    return [d for d in yaml.safe_load_all(out.stdout) if d]

docs = render("openshell-platform")
cs = next((d for d in docs if d.get("kind") == "ClusterSPIFFEID"), None)
if not cs:
    fail.append("ClusterSPIFFEID not rendered by openshell-platform when ztwim.enabled=true")
else:
    ws = cs.get("spec", {}).get("workloadSelector", {})
    if "namespace" in ws:
        fail.append("ClusterSPIFFEID workloadSelector.namespace not in Red Hat operator sample schema")
    sa = ws.get("k8sServiceAccount", {})
    if sa.get("namespace") != "openshell" or sa.get("name") != "openshell-sandbox":
        fail.append(f"ClusterSPIFFEID selector wrong: {sa}")
    ttl = cs.get("spec", {}).get("ttl")
    if not (isinstance(ttl, str) and ttl.endswith("s")):
        fail.append(f"ClusterSPIFFEID ttl must be a duration string (e.g. '3600s'), got {ttl!r}")

# Toggle off -> no ztwim-dependent content from pattern-owned charts
off = render("openshell-platform", kwsets=["--set", "global.openshell.ztwim.enabled=false"])
if any(d.get("kind") == "ClusterSPIFFEID" for d in off):
    fail.append("ClusterSPIFFEID rendered while ztwim.enabled=false")

v = yaml.safe_load(open(f"{root}/overrides/values-ztwim.yaml"))
spire = v.get("spire", {})
if spire.get("federation", {}).get("enabled") not in (False, "false", None):
    fail.append("ztwim federation must stay disabled for the lab")
if (v.get("defaultDenyNetworkPolicy") or {}).get("enabled") is not False:
    fail.append("default-deny network policies must be off (lab posture)")
if spire.get("server", {}).get("persistence", {}).get("size") != "2Gi":
    fail.append("spire persistence must be pinned at 2Gi")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell ztwim validation passed")
EOF
