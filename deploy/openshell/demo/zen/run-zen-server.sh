#!/usr/bin/env bash
# ZEN SERVER-MODE demo driver (011-zen-sandbox-demo, US3). Runs opencode in
# server mode INSIDE a governed sandbox and attaches a LOCAL opencode client
# via the gateway-native TCP forward (FR-007 default path; T007 verdict).
#
#   run-zen-server.sh           setup + serve + forward + attach instructions + Enter-to-teardown
#   run-zen-server.sh --teardown  kill forward, delete sandbox, assert zero residual
#
# Env: SANDBOX_NAME, GATEWAY (default k8s), SERVE_PORT (default 4096),
#      OPENCODE_SERVER_PASSWORD (optional; never persisted — console only, Z4)
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
GATEWAY="${GATEWAY:-k8s}"
SANDBOX="${SANDBOX_NAME:-zen-$(date +%s)}"
IMAGE="${DEMO_SANDBOX_IMAGE:-ghcr.io/butler54/openshell-sandbox:latest}"
POLICY="$root/charts/openshell-policy/policies/zen-demo.yaml"
TEMPLATE="$root/deploy/openshell/demo/zen/opencode-zen.json"
PROFILE="$root/deploy/openshell/profiles/zen.yaml"
SERVE_PORT="${SERVE_PORT:-4096}"
FWD_PID=""

cleanup() {
  [ -n "$FWD_PID" ] && kill "$FWD_PID" >/dev/null 2>&1; openshell forward stop "$SANDBOX" >/dev/null 2>&1
  openshell sandbox delete "$SANDBOX" >/dev/null 2>&1
  if openshell sandbox list -g "$GATEWAY" 2>/dev/null | grep -q "$SANDBOX"; then
    echo "FAIL cleanup ($SANDBOX still listed)"; exit 1
  fi
  echo "PASS teardown ($SANDBOX, forward stopped, zero residual)"
}
trap 'cleanup' EXIT

preflight() {
  make -C "$root" check-openshell-cli >/dev/null 2>&1 \
    || { echo "FAIL preflight: openshell CLI/chart pin mismatch"; exit 1; }
  openshell status -g "$GATEWAY" >/dev/null 2>&1 \
    || { echo "FAIL preflight (run: OPENSHELL_NO_BROWSER=1 openshell gateway login $GATEWAY)"; exit 1; }
  openshell profile list 2>/dev/null | grep -q '^zen[[:space:]]' \
    || openshell provider profile import --file "$PROFILE" --global >/dev/null 2>&1 \
    || { echo "FAIL preflight: zen profile import"; exit 1; }
  openshell provider list 2>/dev/null | grep -q '^zen[[:space:]]' \
    || openshell provider create --name zen --type zen --global-profile >/dev/null 2>&1 \
    || { echo "FAIL preflight: zen provider create"; exit 1; }
  echo "PASS preflight"
}

case "${1:-}" in
  --teardown) cleanup; exit 0 ;;
esac

preflight
openshell sandbox create --name "$SANDBOX" --from "$IMAGE" --detach >/dev/null 2>&1 &
create_pid=$!
applied=""
for _ in $(seq 1 30); do
  openshell policy set "$SANDBOX" --policy "$POLICY" >/dev/null 2>&1 && { applied=1; break; }
  sleep 3
done
[ -n "$applied" ] || { echo "FAIL create/policy"; exit 1; }
wait $create_pid 2>/dev/null || true
ready=""
for _ in $(seq 1 30); do
  phase=$(openshell sandbox get "$SANDBOX" -o json 2>/dev/null \
    | python3 -c 'import json,sys;print(json.load(sys.stdin).get("phase","?"))' 2>/dev/null)
  [ "$phase" = "Ready" ] && { ready=1; break; }
  sleep 10
done
[ -n "$ready" ] || { echo "FAIL create (phase=$phase)"; exit 1; }
echo "PASS create+policy ($SANDBOX)"

"$root/deploy/openshell/demo/inject-config.sh" "$SANDBOX" "$TEMPLATE" "opencode.ai" \
  || { echo "FAIL inject"; exit 1; }

# Start the opencode server detached inside the sandbox (loopback-reachable;
# forward service Phase 1 is loopback-only anyway — T022).
env_prefix=""
[ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && env_prefix="OPENCODE_SERVER_PASSWORD=$OPENCODE_SERVER_PASSWORD"
openshell sandbox exec -n "$SANDBOX" -- sh -c \
  "cd /sandbox && setsid nohup env $env_prefix opencode serve --hostname 0.0.0.0 --port $SERVE_PORT >/tmp/opencode-serve.log 2>&1 < /dev/null &" \
  || { echo "FAIL serve (start)"; exit 1; }

health=""
for _ in $(seq 1 12); do
  code=$(openshell sandbox exec -n "$SANDBOX" -- curl -m 5 -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:$SERVE_PORT/config" 2>/dev/null | tr -dc '0-9')
  case "$code" in 2*|401|403) health=1; break ;; esac
  sleep 5
done
[ -n "$health" ] || { echo "FAIL serve (no health on :$SERVE_PORT)"; openshell sandbox exec -n "$SANDBOX" -- sh -c 'tail -15 /tmp/opencode-serve.log'; exit 1; }
echo "PASS serve (opencode server healthy on sandbox loopback :$SERVE_PORT)"

# Gateway-native forward: local TCP -> sandbox loopback over gRPC (FR-007).
openshell forward service "$SANDBOX" --target-port "$SERVE_PORT" --local "$SERVE_PORT" >/tmp/zen-forward.log 2>&1 &
FWD_PID=$!
fwd=""
for _ in $(seq 1 12); do
  code=$(curl -m 5 -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$SERVE_PORT/config" 2>/dev/null | tr -dc '0-9')
  case "$code" in 2*|401|403) fwd=1; break ;; esac
  kill -0 $FWD_PID 2>/dev/null || break
  sleep 5
done
if [ -n "$fwd" ]; then
  echo "PASS forward (local :$SERVE_PORT -> sandbox :$SERVE_PORT via openshell gateway)"
  echo "==> attach with:  opencode attach http://localhost:$SERVE_PORT"
else
  echo "WARN forward: gateway-native forward unhealthy — recorded fallback (FR-007): oc port-forward"
  echo "     oc port-forward -n openshell <sandbox-pod> $SERVE_PORT:$SERVE_PORT &  # then attach"
fi
[ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && echo "server password: set in-session (not persisted)"

echo "server live — press Enter to teardown"
read -r </dev/tty 2>/dev/null || sleep 3600
