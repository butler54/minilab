#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$root" <<'EOF'
import os, subprocess, sys, yaml

root = sys.argv[1]
fail = []

def render(chart, extra=None):
    cmd = ["helm", "template", os.path.basename(chart), os.path.join(root, "charts", chart),
           "-f", os.path.join(root, "values-global.yaml"),
           "-f", os.path.join(root, "overrides", "values-openshell.yaml"),
           "--set", "global.openshell.enabled=true"]
    if extra:
        cmd += extra
    out = subprocess.run(cmd, capture_output=True, text=True, cwd=root)
    if out.returncode != 0:
        fail.append(f"helm template {chart} failed: {out.stderr.strip()[:400]}")
        return []
    return [d for d in yaml.safe_load_all(out.stdout) if d]

# 1. agent-sandbox renders its CRDs and controller, namespace-agnostic
docs = render("agent-sandbox", extra=["--include-crds"])
kinds = [d["kind"] for d in docs if "kind" in d]
crds = [d["metadata"]["name"] for d in docs if d.get("kind") == "CustomResourceDefinition"]
if "sandboxes.agents.x-k8s.io" not in crds:
    fail.append(f"agent-sandbox missing sandboxes CRD (got {crds})")
if "Deployment" not in kinds:
    fail.append("agent-sandbox missing controller Deployment")

# 2. openshell wrapper renders the upstream chart with required values
chart = os.path.join(root, "charts", "openshell")
vals_path = os.path.join(chart, "values.yaml")
if not os.path.isdir(chart):
    fail.append("charts/openshell missing")
else:
    vals = yaml.safe_load(open(vals_path)) or {}
    vals = vals.get("openshell", {})  # subchart alias in wrapper values
    server = vals.get("server", {})
    sup = vals.get("supervisor", {})
    agent_sb = vals.get("agentSandbox", {})
    checks = {
        "agentSandbox.preflight.enabled": (agent_sb.get("preflight") or {}).get("enabled") is False,
        "server.telemetryEnabled": server.get("telemetryEnabled") is False,
        "supervisor.sideloadMethod": sup.get("sideloadMethod") == "init-container",
        "server.credentialStorage.existingSecret": (server.get("credentialStorage") or {}).get("existingSecret") == "openshell-kek",
    }
    for k, ok in checks.items():
        if not ok:
            fail.append(f"charts/openshell/values.yaml: {k} not set as required")

    # SCC overrides: fsGroup/runAsUser must be explicitly null
    psc = vals.get("podSecurityContext", "MISSING")
    sc = vals.get("securityContext", "MISSING")
    if not (isinstance(psc, dict) and "fsGroup" in psc and psc["fsGroup"] is None):
        fail.append("podSecurityContext.fsGroup must be explicitly null")
    if not (isinstance(sc, dict) and "runAsUser" in sc and sc["runAsUser"] is None):
        fail.append("securityContext.runAsUser must be explicitly null")

    docs = render("openshell")
    if not docs and not fail:
        fail.append("charts/openshell renders no resources")
    kinds = [d.get("kind") for d in docs]
    if "StatefulSet" not in kinds:
        fail.append(f"openshell gateway StatefulSet not rendered (got {sorted(set(kinds))})")

# 3. Route/cert-manager surfaces only appear when issuer wiring is on (US3)
if os.path.isdir(chart):
    docs = render("openshell")
    routes = [d for d in docs if d.get("kind") == "Route"]
    if routes:
        host = routes[0].get("spec", {}).get("host", "")
        vals = yaml.safe_load(open(os.path.join(root, "overrides", "values-openshell.yaml")))["global"]["openshell"]
        if host != vals["gatewayHostname"]:
            fail.append(f"Route host {host!r} != openshell.gatewayHostname {vals['gatewayHostname']!r}")
        term = (routes[0].get("spec", {}).get("tls") or {}).get("termination")
        if term != "passthrough":
            fail.append(f"Route tls.termination must be passthrough, got {term!r}")

    # Subchart passthrough dials must stay in sync with the global feature values
    ov = yaml.safe_load(open(os.path.join(root, "overrides", "values-openshell.yaml")))
    g = ov["global"]["openshell"]
    sub = ov.get("openshell", {})
    if sub.get("openshiftRoute", {}).get("enabled"):
        if sub["openshiftRoute"].get("host") != g["gatewayHostname"]:
            fail.append("openshell.openshiftRoute.host != global.openshell.gatewayHostname")
        pb = sub.get("certManager", {})
        if pb.get("serverIssuerRef", {}).get("name") != f"letsencrypt-{g['issuer']}":
            fail.append("certManager.serverIssuerRef.name != letsencrypt-{{ openshell.issuer }}")
        if (pb.get("serverDnsNames") or [None])[0] != g["gatewayHostname"]:
            fail.append("certManager.serverDnsNames[0] != global.openshell.gatewayHostname")

# 4. openshell-policy baseline renders deny-all + operator drop-in keys
if os.path.isdir(os.path.join(root, "charts", "openshell-policy")):
    docs = render("openshell-policy")
    cm = next((d for d in docs if d.get("kind") == "ConfigMap" and d["metadata"]["name"] == "openshell-policy"), None)
    if not cm:
        fail.append("openshell-policy ConfigMap not rendered")
    else:
        data = cm.get("data", {})
        if not any("baseline" in k for k in data):
            fail.append(f"policy ConfigMap missing a baseline document (keys: {list(data)})")
        base_doc = next((yaml.safe_load(v) for k, v in data.items() if "baseline" in k), None)
        if not base_doc or base_doc.get("endpoints") is None:
            fail.append("baseline policy document must declare endpoints (empty list = deny-all)")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell render validation passed")
EOF
