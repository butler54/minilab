#!/usr/bin/env bash
# Hermes agent deployment (docs/hermes-agent.md): static guards for the
# hermes policy and config templates.
# - hermes.yaml: valid YAML, every rule has endpoints+binaries, expected
#   host set present (qwen/Slack/Signal), no secret material, no wildcards,
#   no duplicate host:port pairs, tls:skip only on Signal (tcp) endpoints
# - hermes-config.yaml: model config points at the donnager qwen endpoint
#   with the server-reported model id, and carries no secret material
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POL="$ROOT/charts/openshell-policy/policies/hermes.yaml"
CFG="$ROOT/deploy/openshell/hermes/hermes-config.yaml"

fail() { echo "test-hermes-policy: FAIL: $*" >&2; exit 1; }

# --- hermes.yaml ---
[ -f "$POL" ] || fail "missing $POL"
python3 - "$POL" <<'PY' || fail "hermes.yaml failed structural checks"
import sys, yaml
p = yaml.safe_load(open(sys.argv[1]))
assert p.get("version") == 1, "version must be 1"
rules = p.get("network_policies") or {}
assert rules, "network_policies must not be empty"
seen = set()
for name, rule in rules.items():
    eps = rule.get("endpoints") or []
    bins = rule.get("binaries") or []
    assert eps and bins, f"rule {name}: endpoints and binaries are mandatory"
    for e in eps:
        host, port, proto = e.get("host"), e.get("port"), e.get("protocol")
        assert host and port and proto, f"rule {name}: host/port/protocol mandatory"
        assert "*" not in str(host), f"rule {name}: wildcards forbidden ({host})"
        key = (host, port)
        assert key not in seen, f"duplicate host:port {key}"
        seen.add(key)
        if e.get("tls") == "skip":
            assert proto == "tcp", f"tls:skip requires protocol tcp ({host})"
# Expected host set: qwen + Slack socket mode + Signal service endpoints
expected = {
    ("192.168.4.190", 11434),
    ("slack.com", 443), ("api.slack.com", 443), ("hooks.slack.com", 443),
    ("wss-primary.slack.com", 443), ("wss-backup.slack.com", 443),
    ("chat.signal.org", 443), ("cdn.signal.org", 443), ("cdn2.signal.org", 443),
    ("cdn3.signal.org", 443), ("storage.signal.org", 443),
    ("cdsi.signal.org", 443), ("svr2.signal.org", 443),
}
missing = expected - seen
assert not missing, f"missing expected endpoints: {sorted(missing)}"
# Qwen endpoint must be plain IPv4 (0.1.8: IPv4-mapped IPv6 is evaluated as IPv4)
assert "192.168.4.190" in str(p), "qwen endpoint must use the direct LAN IP"
PY
# No secret material in the policy
! grep -Eq 'xoxb-|xoxa-|xapp-|sk-[A-Za-z0-9]{8}|api[_-]?key:\s*[A-Za-z0-9]' "$POL" \
  || fail "hermes.yaml appears to contain secret material"

# --- hermes-config.yaml (only when the deployment templates exist) ---
if [ -f "$CFG" ]; then
  python3 - "$CFG" <<'PY' || fail "hermes-config.yaml failed checks"
import sys, yaml
c = yaml.safe_load(open(sys.argv[1]))
m = c["model"]
assert m["provider"] == "custom", "provider must be custom (self-hosted qwen)"
assert m["base_url"] == "http://192.168.4.190:11434/v1", "base_url must be the direct-IP qwen endpoint"
assert m["default"] == "qwen-coder:latest", "model id must be the server-reported qwen-coder:latest"
PY
  ! grep -Eq 'xoxb-|xoxa-|xapp-|sk-[A-Za-z0-9]{8}' "$CFG" \
    || fail "hermes-config.yaml appears to contain secret material"
fi

echo "hermes policy validation passed"
