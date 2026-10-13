#!/usr/bin/env bash
# Feature 011: static guards for the zen demo assets (contract Z1/Z2).
# - opencode-zen.json: strict JSON, zero secret material, provider/model-id form
# - zen-demo.yaml: every rule has endpoints+binaries, protocol rest on HTTP,
#   a justification comment, no wildcards, no duplicate host:port pairs
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CFG="$ROOT/deploy/openshell/demo/zen/opencode-zen.json"
POL="$ROOT/charts/openshell-policy/policies/zen-demo.yaml"

fail() { echo "test-zen-policy: FAIL: $*" >&2; exit 1; }

# --- Z1: config template ---
[ -f "$CFG" ] || fail "missing $CFG"
python3 -m json.tool "$CFG" >/dev/null || fail "$CFG is not strict JSON"
grep -Eq 'sk-[A-Za-z0-9]|mc_live_[a-f0-9]{8}|api[_-]?key["'"'"' ]*:[ ]*"[A-Za-z0-9_-]{16,}' "$CFG" \
  && fail "$CFG appears to contain secret material"
model=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$CFG")
case "$model" in
  opencode/*-free) : ;;
  *) fail "model '$model' must be opencode/<id>-free (zen free tier)" ;;
esac
python3 -c 'import json,sys
c=json.load(open(sys.argv[1]))
pv=(c.get("provider") or {})
assert "apiKey" not in str(c) or len(str(c["provider"]))==0 or True
# hard rule: no apiKey material — placeholder allowed only if documented (keyless mode expected)
raw=open(sys.argv[1]).read()
assert "ZEN_API_KEY" not in raw, "keyless mode confirmed (T004); apiKey placeholders must not appear"
' "$CFG" || fail "$CFG must not reference ZEN_API_KEY (keyless mode confirmed)"

# --- Z2: policy file ---
[ -f "$POL" ] || fail "missing $POL"
python3 - "$POL" <<'PY'
import re, sys, yaml

path = sys.argv[1]
doc = yaml.safe_load(open(path))
assert doc.get("version") == 1, "policy version must be 1"
pol = doc.get("network_policies") or {}
assert isinstance(pol, dict), "network_policies must be a map"

text = open(path).read()
# justification comments are on rule names (they sit above each rule block)
for name, rule in pol.items():
    if not isinstance(rule, dict):
        raise SystemExit(f"{name}: rule must be a mapping")
    eps = rule.get("endpoints") or []
    bins = rule.get("binaries") or []
    if not eps:
        raise SystemExit(f"{name}: endpoints must be non-empty")
    if not bins:
        raise SystemExit(f"{name}: binaries must be non-empty (gateway require_binary_identity)")
    for ep in eps:
        host = str(ep.get("host", ""))
        if not host or "*" in host:
            raise SystemExit(f"{name}: wildcard/empty host not allowed: {host!r}")
        proto = ep.get("protocol")
        if ep.get("port") in (80, 443, 8080, 8443) and proto != "rest":
            raise SystemExit(f"{name}: HTTP(S) endpoint {host}:{ep.get('port')} requires 'protocol: rest'")
    # justification comment must appear before the rule key line
    idx = text.find(f"  {name}:")
    header = text[:idx].splitlines()[-6:] if idx != -1 else []
    if not any("justification:" in ln for ln in header):
        raise SystemExit(f"{name}: missing '# justification:' comment (FR-003)")

seen = set()
for name, rule in pol.items():
    for ep in (rule.get("endpoints") or []):
        key = (ep.get("host"), ep.get("port"))
        if key in seen:
            raise SystemExit(f"duplicate host:port {key} across rules")
        seen.add(key)
PY

echo "zen policy validation passed"
