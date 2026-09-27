#!/usr/bin/env bash
# V-DEMO runbook driver (008-opencode-sandbox-demo). Modes:
#   run-demo.sh             interactive: setup, then attach via openshell sandbox connect
#   run-demo.sh --smoke     fully automatic: one-shot agent + proofs + cleanup
#   run-demo.sh --proofs    proofs + cleanup on an already-running sandbox
# Env: DEMO_SANDBOX_IMAGE (default ghcr.io/butler54/openshell-sandbox:latest)
#      SANDBOX_NAME, DEMO_PROMPT, GATEWAY (default k8s)
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
GATEWAY="${GATEWAY:-k8s}"
SANDBOX="${SANDBOX_NAME:-demo-$(date +%s)}"
IMAGE="${DEMO_SANDBOX_IMAGE:-ghcr.io/butler54/openshell-sandbox:latest}"
PROMPT="${DEMO_PROMPT:-Reply with exactly: OPENSHELL_VDEMO_OK}"
POLICY="$root/charts/openshell-policy/policies/sample-matilda-demo.yaml"
TEMPLATE="$root/deploy/openshell/demo/opencode-matilda.json"
MODE="interactive"
[ "${1:-}" = "--smoke" ] && MODE="smoke"
[ "${1:-}" = "--proofs" ] && MODE="proofs"

created=0
cleanup() {
  [ "$created" != 1 ] && { echo "skip cleanup (nothing created)"; return 0; }
  openshell sandbox delete "$SANDBOX" >/dev/null 2>&1
  created=0
  echo "PASS cleanup ($SANDBOX)"
}

preflight() {
  openshell status -g "$GATEWAY" >/dev/null 2>&1 \
    && echo "PASS preflight" \
    || { echo "FAIL preflight (run: OPENSHELL_NO_BROWSER=1 openshell gateway login $GATEWAY)"; exit 1; }
}

setup() {
  preflight
  openshell sandbox create --name "$SANDBOX" --from "$IMAGE" --provider matilda --detach >/dev/null 2>&1 &
  create_pid=$!
  # A policy-less sandbox never leaves Provisioning — apply early, and retry
  # until the gateway has registered the sandbox record (create RPC latency
  # varies with first-time image pulls).
  applied=""
  for _ in $(seq 1 40); do
    if openshell policy set "$SANDBOX" --policy "$POLICY" >/dev/null 2>&1; then applied=1; break; fi
    sleep 5
  done
  [ -n "$applied" ] || { echo "FAIL create/policy (sandbox never registered)"; exit 1; }
  openshell policy set "$SANDBOX" --policy "$POLICY" --wait >/dev/null 2>&1 || true
  wait $create_pid 2>/dev/null || true
  phase=$(openshell sandbox list 2>/dev/null | awk -v n="$SANDBOX" '$1==n {print $NF}')
  [ "$phase" = "Ready" ] \
    && echo "PASS create+policy ($SANDBOX)" || { echo "FAIL create/policy (phase=$phase)"; exit 1; }
  "$root/deploy/openshell/demo/inject-config.sh" "$SANDBOX" "$TEMPLATE" || { echo "FAIL inject"; exit 1; }
  created=1
}

agent_check() {
  out=$(openshell sandbox exec -n "$SANDBOX" -- sh -lc "cd /sandbox && opencode run \"$PROMPT\"" 2>&1 | tail -20)
  echo "$out" | grep -q "OPENSHELL_VDEMO_OK" \
    && echo "PASS agent (matilda response)" \
    || { echo "FAIL agent"; echo "$out" | head -10; exit 1; }
}

proofs() {
  denied=0
  for host in example.com github.com pypi.org api.openai.com registry-1.docker.io; do
    openshell sandbox exec -n "$SANDBOX" -- curl -m 6 -s -o /dev/null "https://$host" >/dev/null 2>&1 \
      || denied=$((denied+1))
  done
  [ "$denied" -ge 5 ] && echo "PASS deny (${denied}/5 varied probes refused)" || { echo "FAIL deny (only ${denied}/5 refused)"; exit 1; }
  env_hits=$(openshell sandbox exec -n "$SANDBOX" -- sh -c 'env | grep -cE "mc_live_[a-f0-9]{20}|sk-[A-Za-z0-9]{20,}" || true' 2>/dev/null | tr -dc '0-9')
  fs_hits=$(openshell sandbox exec -n "$SANDBOX" -- sh -c 'grep -rlE "mc_live_[a-f0-9]{20}|sk-[A-Za-z0-9]{20,}" /sandbox --include="opencode.json" --include="*.json" --include="*.sh" --include="*.env" --include="*.txt" --include="*.md" 2>/dev/null | wc -l' 2>/dev/null | tr -dc '0-9')
  [ "${env_hits:-0}" -eq 0 ] && [ "${fs_hits:-0}" -eq 0 ] \
    && echo "PASS no-secrets (zero key bytes in env+/sandbox)" \
    || { echo "FAIL no-secrets (env=$env_hits fs=$fs_hits)"; exit 1; }
  openshell policy get "$SANDBOX" -o json 2>/dev/null | grep -q '"status".*effective' \
    && echo "PASS policy (effective)" || { echo "FAIL policy-status"; exit 1; }
}

case "$MODE" in
  proofs)     proofs; cleanup ;;
  smoke)      setup; agent_check; proofs; cleanup ;;
  interactive) setup; echo "attach: openshell sandbox connect $SANDBOX (detach Ctrl-P Ctrl-Q; then: SANDBOX_NAME=$SANDBOX $0 --proofs)"; openshell sandbox connect "$SANDBOX" ;;
esac
