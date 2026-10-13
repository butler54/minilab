#!/usr/bin/env bash
# ZEN DEMO driver (011-zen-sandbox-demo). Lifecycle proof for a governed
# sandbox answering a free-tier OpenCode Zen model behind least-privilege
# egress. Modes:
#   run-zen-demo.sh             interactive: setup (incl. fence proof), then attach
#   run-zen-demo.sh --setup     setup only (preflight+provider+create+policy+fence+inject), leave running
#   run-zen-demo.sh --query     one classified zen-query attempt on the running sandbox
#   run-zen-demo.sh --proofs    deny probes + cleanup on an already-running sandbox
#   run-zen-demo.sh --smoke     fully automatic: setup + query + proofs + cleanup
# Env: SANDBOX_NAME, DEMO_SANDBOX_IMAGE, GATEWAY (default k8s),
#      SKIP_FENCE_WAIT=1 (skip the +5.5min alive check; CI/dev only),
#      DEMO_MODEL (default from opencode-zen.json)
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
GATEWAY="${GATEWAY:-k8s}"
SANDBOX="${SANDBOX_NAME:-zen-$(date +%s)}"
IMAGE="${DEMO_SANDBOX_IMAGE:-ghcr.io/butler54/openshell-sandbox:latest}"
POLICY="$root/charts/openshell-policy/policies/zen-demo.yaml"
TEMPLATE="$root/deploy/openshell/demo/zen/opencode-zen.json"
PROFILE="$root/deploy/openshell/profiles/zen.yaml"
PROMPT='Reply with exactly: ZEN_HI_OK'
FENCE_WINDOW_S=330   # 5.5 min (fence reaper kills bootstrapping sandboxes ~5min in; FR/011 edge case)
MODE="interactive"
case "${1:-}" in --setup|--query|--proofs|--smoke) MODE="${1#--}" ;; esac

created=0
keep_alive=0
cleanup() {
  [ "$keep_alive" = 1 ] && { echo "sandbox left running (teardown: openshell sandbox delete $SANDBOX)"; return 0; }
  [ "$created" != 1 ] && { echo "skip cleanup (nothing created)"; return 0; }
  openshell sandbox delete "$SANDBOX" >/dev/null 2>&1
  created=0
  if openshell sandbox list -g "$GATEWAY" 2>/dev/null | grep -q "$SANDBOX"; then
    echo "FAIL cleanup ($SANDBOX still listed)"; return 1
  fi
  echo "PASS cleanup ($SANDBOX)"
}
# Unconditional cleanup on ANY exit (proof FAIL paths included) once a sandbox exists.
trap 'cleanup' EXIT

preflight() {
  make -C "$root" check-openshell-cli >/dev/null 2>&1 \
    || { echo "FAIL preflight: openshell CLI/chart pin mismatch (make check-openshell-cli)"; exit 1; }
  openshell status -g "$GATEWAY" >/dev/null 2>&1 \
    && echo "PASS preflight" \
    || { echo "FAIL preflight (run: OPENSHELL_NO_BROWSER=1 openshell gateway login $GATEWAY)"; exit 1; }
  # zen provider/profile are keyless (T004 verdict) but the gateway admission
  # requires the records to exist; recreate idempotently from Git sources.
  openshell profile list 2>/dev/null | grep -q '^zen[[:space:]]' \
    || openshell provider profile import --file "$PROFILE" --global >/dev/null 2>&1 \
    || { echo "FAIL preflight: zen profile import"; exit 1; }
  openshell provider list 2>/dev/null | grep -q '^zen[[:space:]]' \
    || openshell provider create --name zen --type zen --global-profile >/dev/null 2>&1 \
    || { echo "FAIL preflight: zen provider create"; exit 1; }
  echo "PASS provider zen (keyless profile present)"
}

create_one() {
  # FI1 (2026-10-13): custom --from sandboxes are born admission-rejected until
  # a policy lands; the policy-set retry loop below must run CONCURRENTLY with
  # the create RPC (which can hang ~300s during gateway<->apiserver flaps).
  CREATE_EPOCH=$(date +%s)
  openshell sandbox create --name "$SANDBOX" --from "$IMAGE" --detach >/dev/null 2>&1 &
  create_pid=$!
  applied=""
  for _ in $(seq 1 30); do
    if openshell policy set "$SANDBOX" --policy "$POLICY" >/dev/null 2>&1; then applied=1; break; fi
    sleep 3
  done
  [ -n "$applied" ] || { echo "FAIL create/policy (sandbox never registered)"; return 1; }
  wait $create_pid 2>/dev/null || true
  # Ready-wait: admission flips rejected->accepted once the policy lands.
  ready=""
  for _ in $(seq 1 30); do
    phase=$(openshell sandbox get "$SANDBOX" -o json 2>/dev/null \
      | python3 -c 'import json,sys;print(json.load(sys.stdin).get("phase","?"))' 2>/dev/null)
    [ "$phase" = "Ready" ] && { ready=1; break; }
    sleep 10
  done
  [ -n "$ready" ] || { echo "FAIL create/policy (phase=$phase)"; return 1; }
  READY_EPOCH=$(date +%s)
  echo "PASS create+policy ($SANDBOX, create->Ready $((READY_EPOCH-CREATE_EPOCH))s)"
}

fence_verify() {
  # T013: the fence reaper kills sandboxes ~5min into bootstrap. Alive at
  # +5.5min == G2 fence-survival proof. On fence-death: recreate ONCE (spec
  # edge case / 008 mitigation); a second death fails the run.
  [ "${SKIP_FENCE_WAIT:-0}" = 1 ] && { echo "SKIP fence-wait (SKIP_FENCE_WAIT=1)"; return 0; }
  local remaining=$(( CREATE_EPOCH + FENCE_WINDOW_S - $(date +%s) ))
  [ "$remaining" -gt 0 ] && { echo "fence-window wait ${remaining}s..."; sleep "$remaining"; }
  if openshell sandbox get "$SANDBOX" >/dev/null 2>&1; then
    echo "PASS fence-window ($SANDBOX alive past +5.5min)"
    return 0
  fi
  echo "FENCE-DEATH ($SANDBOX gone at +5.5min) — auto-recreating once"
  SANDBOX="zen-$(date +%s)"
  create_one || { echo "FAIL fence-recreate"; return 1; }
  remaining=$(( CREATE_EPOCH + FENCE_WINDOW_S - $(date +%s) ))
  [ "$remaining" -gt 0 ] && sleep "$remaining"
  openshell sandbox get "$SANDBOX" >/dev/null 2>&1 \
    && echo "PASS fence-window after recreate ($SANDBOX)" \
    || { echo "FAIL fence-window (second fence-death)"; return 1; }
}

inject() {
  "$root/deploy/openshell/demo/inject-config.sh" "$SANDBOX" "$TEMPLATE" "opencode.ai" \
    || { echo "FAIL inject"; return 1; }
}

query() {
  # Guard: probes against a dead/absent sandbox produce false classifications
  # (gateway records can outlive the workload — verified 2026-10-13 R3).
  openshell sandbox exec -n "$SANDBOX" -- true >/dev/null 2>&1 \
    || { echo "FAIL query (sandbox $SANDBOX not exec-live)"; return 1; }
  # Classified zen-query attempt (contract Z3): never "fix" the wrong layer.
  out=$(openshell sandbox exec -n "$SANDBOX" -- sh -c "cd /sandbox && opencode run --print-logs \"$PROMPT\"" 2>&1 | tail -40)
  rc=$?
  if echo "$out" | grep -q "ZEN_HI_OK"; then
    echo "PASS query (zen free-tier response: ZEN_HI_OK)"; return 0
  fi
  if echo "$out" | grep -qiE "ProviderModelNotFoundError|Model not found"; then
    echo "FAIL query (classification: provider/model-catalog — model absent from client registry, DR1/DR2)"
  elif echo "$out" | grep -qiE "FreeTierError|401|invalid_api_key"; then
    echo "FAIL query (classification: auth/free-tier gating)"
  elif echo "$out" | grep -qiE "Permission denied|ENETUNREACH|ETIMEDOUT|ECONNREFUSED|timeout|denied|connect |transport error|fetch failed|resolve"; then
    echo "FAIL query (classification: policy-deny/network)"
  else
    echo "FAIL query (classification: unknown — $rc)"
  fi
  echo "$out" | head -15
  return 1
}

proofs() {
  # Guard: curl failures against a dead sandbox would falsely count as policy
  # denies — require exec liveness (record-exists is NOT sufficient, R3).
  openshell sandbox exec -n "$SANDBOX" -- true >/dev/null 2>&1 \
    || { echo "FAIL proofs (sandbox $SANDBOX not exec-live)"; return 1; }
  denied=0
  for host in example.com github.com pypi.org api.openai.com registry-1.docker.io; do
    openshell sandbox exec -n "$SANDBOX" -- curl -m 6 -s -o /dev/null "https://$host" >/dev/null 2>&1 \
      || denied=$((denied+1))
  done
  [ "$denied" -ge 5 ] && echo "PASS deny (${denied}/5 varied probes refused)" || { echo "FAIL deny (only ${denied}/5 refused)"; return 1; }
  openshell policy get "$SANDBOX" -o json 2>/dev/null | grep -q '"status".*effective' \
    && echo "PASS policy (effective)" || echo "WARN policy-status (non-effective status reported)"
}

setup() {
  preflight
  create_one || exit 1
  created=1
  fence_verify || exit 1
  inject || exit 1
}

case "$MODE" in
  setup)       setup; keep_alive=1 ;;
  query)       query || exit 1 ;;
  proofs)      proofs || exit 1; cleanup ;;
  smoke)       setup; query || true; proofs || exit 1; cleanup ;;
  interactive) setup; keep_alive=1; echo "attach: openshell sandbox connect $SANDBOX (detach Ctrl-P Ctrl-Q; then: SANDBOX_NAME=$SANDBOX $0 --query)"; openshell sandbox connect "$SANDBOX" ;;
esac
