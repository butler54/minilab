#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$root" <<'EOF'
import sys, yaml, os, re

root = sys.argv[1]
gv = yaml.safe_load(open(os.path.join(root, "values-global.yaml")))["global"]
ov = yaml.safe_load(open(os.path.join(root, "overrides/values-openshell.yaml")))["global"]["openshell"]

zone = gv.get("dnsZone", "")
email = gv.get("acmeEmail", "")
host = ov.get("gatewayHostname", "")
issuer = ov.get("issuer", "")
maxc = ov.get("sandbox", {}).get("maxConcurrent")
trust = ov.get("trustDomain", "")

fail = []
if not re.fullmatch(r"[a-z0-9]([a-z0-9.-]*[a-z0-9])?", zone or " "):
    fail.append(f"global.dnsZone invalid: {zone!r}")
if not host.endswith("." + zone):
    fail.append(f"openshell.gatewayHostname {host!r} must end with .{zone}")
if "@" not in email:
    fail.append(f"global.acmeEmail invalid: {email!r}")
if issuer not in ("staging", "prod"):
    fail.append(f"openshell.issuer must be staging|prod, got {issuer!r}")
if not (isinstance(maxc, int) and 1 <= maxc <= 5):
    fail.append(f"openshell.sandbox.maxConcurrent must be an int 1..5, got {maxc!r}")
if trust and not re.fullmatch(r"[a-z0-9]([a-z0-9.-]*[a-z0-9])?", trust):
    fail.append(f"openshell.trustDomain invalid: {trust!r}")

# spiffe enablement MUST track ztwim availability (FR-011 fallback): a CSI
# mount for a driver that may not exist must never be enabled.
ov_raw = yaml.safe_load(open(os.path.join(root, "overrides/values-openshell.yaml")))
sub = ov_raw.get("openshell", {})  # top-level subchart passthrough
spiffe = ((sub.get("server") or {}).get("providerTokenGrants") or {}).get("spiffe", {})
ztwim_on = bool(ov.get("ztwim", {}).get("enabled", False))
if spiffe.get("enabled") and not ztwim_on:
    fail.append("spiffe providerTokenGrants enabled while openshell.ztwim.enabled=false")
if ztwim_on and not spiffe.get("enabled"):
    fail.append("openshell.ztwim.enabled=true but passthrough spiffe.enabled is not true")

# The pattern's shared values file must be wired so the overrides actually apply.
prod = yaml.safe_load(open(os.path.join(root, "values-prod.yaml")))["clusterGroup"]
shared = prod.get("sharedValueFiles", [])
if "/overrides/values-openshell.yaml" not in shared:
    fail.append("values-prod.yaml sharedValueFiles missing /overrides/values-openshell.yaml")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell values contract validation passed")
EOF
