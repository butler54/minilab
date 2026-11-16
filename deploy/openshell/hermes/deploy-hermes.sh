#!/usr/bin/env bash
# deploy-hermes.sh — recorded imperative deployment driver for the Hermes
# agent sandbox (docs/hermes-agent.md). Source of truth: Git (policy chart,
# config templates, sandbox definition ConfigMap). Every mutating action here
# is recorded in docs/hermes-agent.md's imperative-steps table (constitution II).
#
# Usage:
#   deploy-hermes.sh create   # S1: create sandbox + inject config + smoke
#   deploy-hermes.sh smoke    # S1 measure: model + policy + path verification
#   deploy-hermes.sh gateway  # S4: (re)create with hermes-gateway-start as
#                             #     the main process (always-on posture)
#   deploy-hermes.sh teardown # remove the sandbox (state volume is deleted!)
#
# Env: HERMES_IMAGE (default from the hermes-agent ConfigMap)
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
NAME="hermes"
POLICY="$root/charts/openshell-policy/policies/hermes.yaml"
CFG="$root/deploy/openshell/hermes/hermes-config.yaml"
ENV_TEMPLATE="$root/deploy/openshell/hermes/hermes-env.template"

IMAGE="${HERMES_IMAGE:-$(oc -n openshell get cm hermes-agent-sandbox -o jsonpath='{.data.sandbox\.yaml}' 2>/dev/null | awk '/^image:/{print $2}')}"
# Chart value is empty until the S1 digest pin; fall back to the family tag
# (script-side reference only — YAML references must be digest-pinned).
[ -n "$IMAGE" ] || IMAGE="ghcr.io/butler54/openshell-sandbox-hermes:latest"

stage="${1:-create}"

inject_config() {
  openshell sandbox exec -n "$NAME" -- mkdir -p /sandbox/.hermes
  openshell sandbox exec -n "$NAME" -- tee /sandbox/.hermes/config.yaml < "$CFG" >/dev/null
  openshell sandbox exec -n "$NAME" -- grep -q 'qwen-coder:latest' /sandbox/.hermes/config.yaml
  # .env: substitute vault-backed tokens (when slack enabled) + signal values
  local env_src
  env_src=$(mktemp)
  cp "$ENV_TEMPLATE" "$env_src"
  if oc -n openshell get secret hermes-slack-tokens >/dev/null 2>&1; then
    local bot app
    bot=$(oc -n openshell get secret hermes-slack-tokens -o jsonpath='{.data.bot-token}' | base64 -d)
    app=$(oc -n openshell get secret hermes-slack-tokens -o jsonpath='{.data.app-token}' | base64 -d)
    [ -n "$bot" ] && [ -n "$app" ] || { echo "FAIL: hermes-slack-tokens incomplete (bot-token/app-token)" >&2; exit 2; }
    sed -i '' -e "s|{{SLACK_BOT_TOKEN}}|$bot|" -e "s|{{SLACK_APP_TOKEN}}|$app|" "$env_src"
  else
    echo "note: hermes-slack-tokens absent — Slack disabled in .env (S2)" >&2
    sed -i '' -e '/SLACK_/d' "$env_src"
  fi
  local sig_account
  sig_account=$(yq -r '.global.openshell.hermes.signal.account // ""' "$root/overrides/values-openshell.yaml")
  if [ -n "$sig_account" ]; then
    sed -i '' -e "s|{{SIGNAL_ACCOUNT}}|$sig_account|" "$env_src"
  else
    echo "note: signal.account blank — Signal disabled in .env (S3 spike)" >&2
    sed -i '' -e '/SIGNAL_ACCOUNT/d' "$env_src"
  fi
  openshell sandbox exec -n "$NAME" -- tee /sandbox/.hermes/.env < "$env_src" >/dev/null
  openshell sandbox exec -n "$NAME" -- chmod 600 /sandbox/.hermes/.env
  rm -f "$env_src"
  echo "PASS inject ($NAME)"
}

case "$stage" in
  create)
    openshell status -g k8s >/dev/null 2>&1 \
      || { echo "FAIL preflight (run: OPENSHELL_NO_BROWSER=1 openshell gateway login k8s)" >&2; exit 1; }
    # S1: bash main process (measure loop); `gateway` stage recreates always-on.
    openshell sandbox create --name "$NAME" --from "$IMAGE" --policy "$POLICY" --detach -- bash -c 'sleep infinity'
    for _ in $(seq 1 60); do
      phase=$(openshell sandbox list 2>/dev/null | awk -v n="$NAME" '$1==n {print $NF}')
      [ "$phase" = Ready ] && break
      sleep 5
    done
    [ "$phase" = Ready ] || { echo "FAIL: sandbox not Ready" >&2; exit 1; }
    inject_config
    echo "PASS create ($NAME from $IMAGE) — next: deploy-hermes.sh smoke"
    ;;
  smoke)
    # S1 measure: binary paths (policy binaries must be kernel-resolved real
    # paths), model reachability through the policy, hermes self-report.
    echo "--- binary path resolution (policy binaries) ---"
    openshell sandbox exec -n "$NAME" -- sh -c 'readlink -f "$(command -v hermes)"; readlink -f "$JAVA_HOME/bin/java"; readlink -f "$(command -v signal-cli)"'
    echo "--- what is the hermes launcher (venv python?) ---"
    openshell sandbox exec -n "$NAME" -- sh -c 'head -1 "$(readlink -f "$(command -v hermes)")" 2>/dev/null || file "$(readlink -f "$(command -v hermes)")"; ls /opt/hermes/hermes-agent/.venv/bin/python* 2>/dev/null'
    echo "--- model via policy (expect qwen-coder:latest) ---"
    openshell sandbox exec -n "$NAME" -- curl -s -m 15 http://192.168.4.190:11434/v1/models | grep -o 'qwen-coder:latest'
    echo "--- hermes self-report ---"
    openshell sandbox exec -n "$NAME" -- hermes --version
    echo "PASS smoke ($NAME) — record outputs in docs/hermes-agent.md"
    ;;
  gateway)
    # S4: always-on posture — recreate with hermes-gateway-start as the main
    # process. NOTE: delete drops the state volume (re-pair Signal if linked).
    openshell sandbox delete "$NAME" >/dev/null 2>&1 || true
    sleep 5
    openshell sandbox create --name "$NAME" --from "$IMAGE" --policy "$POLICY" --detach -- hermes-gateway-start
    for _ in $(seq 1 60); do
      phase=$(openshell sandbox list 2>/dev/null | awk -v n="$NAME" '$1==n {print $NF}')
      [ "$phase" = Ready ] && break
      sleep 5
    done
    [ "$phase" = Ready ] || { echo "FAIL: sandbox not Ready" >&2; exit 1; }
    inject_config
    echo "PASS gateway ($NAME, main process hermes-gateway-start)"
    ;;
  teardown)
    openshell sandbox delete "$NAME"
    ;;
  *) echo "usage: $0 {create|smoke|gateway|teardown}" >&2; exit 2 ;;
esac
