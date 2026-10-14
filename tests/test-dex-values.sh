#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Feature 013 (Path B) static gate: dex org-gated issuer values contract.
#   a) dial: global.openshell.dex.hostname valid + zone-suffixed
#   b) overrides/values-dex.yaml: issuer/redirectURI derive from the dial;
#      orgs+teams gate shape; env/volume wiring matches the dex-config chart
#   c) charts/dex-config renders: Certificate (acme, dial hostname),
#      passthrough Route (Service dex, named https port), ExternalSecret
#      (both github keys from secret/data/hub/openshell-dex)
python3 - "$root" <<'EOF'
import os, subprocess, sys, yaml

root = sys.argv[1]
fail = []

gv = yaml.safe_load(open(f"{root}/values-global.yaml"))["global"]
ov = yaml.safe_load(open(f"{root}/overrides/values-openshell.yaml"))["global"]["openshell"]
dx = (ov.get("dex") or {}).get("hostname", "")
zone = gv.get("dnsZone", "")

def chk(cond, msg):
    if not cond:
        fail.append(msg)

chk(bool(dx) and dx.endswith("." + zone), f"openshell.dex.hostname {dx!r} must be set and end with .{zone}")

dv = yaml.safe_load(open(f"{root}/overrides/values-dex.yaml"))
cfg = dv.get("config", {})

chk(cfg.get("issuer") == f"https://{dx}", "values-dex issuer != https://<openshell.dex.hostname>")
conn = ((cfg.get("connectors") or [{}])[0] or {}).get("config", {})
chk(conn.get("redirectURI") == f"https://{dx}/callback", "github connector redirectURI != https://<openshell.dex.hostname>/callback")
chk(conn.get("clientID") == "$GITHUB_CLIENT_ID" and conn.get("clientSecret") == "$GITHUB_CLIENT_SECRET",
    "github credentials must be env-substituted ($GITHUB_CLIENT_ID/$GITHUB_CLIENT_SECRET), never literals")
orgs = conn.get("orgs") or []
chk(len(orgs) == 1 and orgs[0].get("name") == "tempest-concorde",
    "github connector orgs must be exactly [tempest-concorde] (FR-001 org gate)")
teams = orgs[0].get("teams") if orgs else []
chk(teams == ["openshell-users", "openshell-admins"],
    f"github connector teams must be [openshell-users, openshell-admins], got {teams!r}")
chk(conn.get("teamNameField") == "slug", "teamNameField must be slug (groups claim = org:team-slug)")
chk(cfg.get("storage", {}).get("type") == "kubernetes", "dex storage must be kubernetes (CRS-backed)")
chk((cfg.get("storage", {}).get("config") or {}).get("inCluster") is True,
    "dex storage.config.inCluster must be true (pod crashloops without it: 'must specify either inCluster or kubeConfigFile')")
chk(cfg.get("enablePasswordDB") is False, "enablePasswordDB must be false (org-gated GitHub is the sole login path, FR-002)")
chk(dv.get("https", {}).get("enabled") is True, "https.enabled must be true (pod serves the ACME cert, passthrough Route)")

sc = {c.get("id"): c for c in cfg.get("staticClients", [])}
chk(sc.get("openshell-cli", {}).get("public") is True, "staticClient openshell-cli must exist and be public")
chk(sc.get("dex-substrate-test", {}).get("redirectURIs") == ["http://127.0.0.1:5555/callback"],
    "staticClient dex-substrate-test must redirect to http://127.0.0.1:5555/callback (C1 smoke client)")

env = {e.get("name"): e for e in dv.get("envVars", [])}
for var, key in (("GITHUB_CLIENT_ID", "github-client-id"), ("GITHUB_CLIENT_SECRET", "github-client-secret")):
    ref = ((env.get(var) or {}).get("valueFrom") or {}).get("secretKeyRef") or {}
    chk(ref.get("name") == "dex-github-oauth" and ref.get("key") == key,
        f"envVars {var} must come from secret dex-github-oauth key {key}")

vols = {v.get("name"): v for v in dv.get("volumes", [])}
mounts = {m.get("name"): m for m in dv.get("volumeMounts", [])}
chk((vols.get("external-tls") or {}).get("secret", {}).get("secretName") == "dex-external-tls",
    "volumes must mount secret dex-external-tls (Certificate in charts/dex-config)")
chk((mounts.get("external-tls") or {}).get("mountPath") == "/etc/dex/tls",
    "external-tls must mount at /etc/dex/tls")
web = cfg.get("web", {})
chk(web.get("tlsCert") == "/etc/dex/tls/tls.crt" and web.get("tlsKey") == "/etc/dex/tls/tls.key",
    "web.tlsCert/tlsKey must match the /etc/dex/tls mount")

# (c) house chart render
cmd = ["helm", "template", "dex-config", os.path.join(root, "charts", "dex-config"),
       "-f", os.path.join(root, "values-global.yaml"),
       "-f", os.path.join(root, "overrides/values-openshell.yaml"),
       "--set", "global.openshell.enabled=true"]
out = subprocess.run(cmd, capture_output=True, text=True)
if out.returncode != 0:
    fail.append(f"helm template dex-config failed: {out.stderr.strip()[:400]}")
    docs = []
else:
    docs = [d for d in yaml.safe_load_all(out.stdout) if d]

cert = next((d for d in docs if d.get("kind") == "Certificate"), None)
chk(cert is not None, "dex-config must render a Certificate")
if cert:
    chk(cert["metadata"].get("namespace") == "openshell", "Certificate must be in ns openshell")
    chk(cert["spec"].get("dnsNames") == [dx], f"Certificate dnsNames must be [{dx!r}]")
    chk(cert["spec"].get("issuerRef", {}).get("name") == "acme", "Certificate must use the acme ClusterIssuer")

route = next((d for d in docs if d.get("kind") == "Route"), None)
chk(route is not None, "dex-config must render a Route")
if route:
    chk(route["spec"].get("host") == dx, "Route host must be the dex hostname")
    chk(route["spec"].get("tls", {}).get("termination") == "passthrough", "Route must be passthrough (pod serves the ACME cert)")
    chk(route["spec"].get("to", {}).get("name") == "dex", "Route must target Service dex (dex/dex chart fullname)")
    chk(route["spec"].get("port", {}).get("targetPort") == "https", "Route must target the named https port")

es = next((d for d in docs if d.get("kind") == "ExternalSecret"), None)
chk(es is not None, "dex-config must render an ExternalSecret")
if es:
    chk(es["metadata"].get("namespace") == "openshell", "ExternalSecret must be in ns openshell")
    chk(es["spec"].get("target", {}).get("name") == "dex-github-oauth", "ExternalSecret target must be dex-github-oauth")
    data = {d.get("secretKey"): d.get("remoteRef", {}) for d in es["spec"].get("data", [])}
    for key in ("github-client-id", "github-client-secret"):
        rr = data.get(key, {})
        chk(rr.get("key") == "secret/data/hub/openshell-dex" and rr.get("property") == key,
            f"ExternalSecret {key} must come from secret/data/hub/openshell-dex property {key}")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("dex values contract validation passed")
EOF
