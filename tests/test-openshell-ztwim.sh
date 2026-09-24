#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Asserts ZTWIM CRs in charts/ztwim-config match the operator schemas verified
# in convergence (T047) and that the ztwim.enabled toggle works (T048).
python3 - "$root" <<'EOF'
import subprocess, sys, yaml, re

root = sys.argv[1]
fail = []

def render(kwsets):
    cmd = ["helm", "template", "ztwim-config", f"{root}/charts/ztwim-config",
           "-f", f"{root}/values-global.yaml",
           "-f", f"{root}/overrides/values-openshell.yaml",
           "--set", "global.openshell.enabled=true"]
    cmd += kwsets
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        fail.append(f"helm template ztwim-config failed: {out.stderr.strip()[:300]}")
        return []
    return [d for d in yaml.safe_load_all(out.stdout) if d]

docs = render([])
if len(docs) != 5:
    fail.append(f"expected 5 manifests (ZTWIM, SpireServer, SpireAgent, SpiffeCSIDriver, ClusterSPIFFEID), got {len(docs)}")

specs = {d["kind"]: d.get("spec", {}) for d in docs if "kind" in d}

ss = specs.get("SpireServer", {})
if not ss:
    fail.append("SpireServer missing")
else:
    for stray in ("trustDomain", "clusterName"):
        if stray in ss:
            fail.append(f"SpireServer.spec.{stray} must not be set (lives only on ZeroTrustWorkloadIdentityManager)")
    ji = ss.get("jwtIssuer", "")
    if not re.fullmatch(r"(?i)https?://[^\s?#]+", ji):
        fail.append(f"SpireServer.spec.jwtIssuer must be an http(s) URL, got {ji!r}")
    for req in ("caSubject", "persistence", "datastore"):
        if req not in ss:
            fail.append(f"SpireServer.spec.{req} required by schema")

sa = specs.get("SpireAgent", {})
for stray in ("trustDomain", "clusterName"):
    if stray in sa:
        fail.append(f"SpireAgent.spec.{stray} must not be set")

cs = specs.get("ClusterSPIFFEID", {})
ws = cs.get("workloadSelector", {})
if "namespace" in ws:
    fail.append("ClusterSPIFFEID workloadSelector.namespace not in Red Hat operator sample schema")
sa_ref = ws.get("k8sServiceAccount", {})
if sa_ref.get("namespace") != "openshell" or sa_ref.get("name") != "openshell-sandbox":
    fail.append(f"ClusterSPIFFEID k8sServiceAccount selector wrong: {sa_ref}")
if not isinstance(cs.get("ttl"), int):
    fail.append("ClusterSPIFFEID ttl must be integer seconds")

ztwim = specs.get("ZeroTrustWorkloadIdentityManager", {})
if "trustDomain" not in ztwim or "clusterName" not in ztwim:
    fail.append("ZeroTrustWorkloadIdentityManager requires trustDomain + clusterName")

# Toggle off -> nothing renders (FR-011 fallback)
off = render(["--set", "global.openshell.ztwim.enabled=false"])
if len(off) != 0:
    fail.append(f"ztwim.enabled=false must render no manifests, got {len(off)}")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell ztwim validation passed")
EOF
