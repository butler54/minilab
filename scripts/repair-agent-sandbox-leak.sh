#!/usr/bin/env bash
# repair-agent-sandbox-leak.sh — feature 010 (specs/010-reduce-cpu-usage)
#
# One-time, Git-recorded imperative repair: delete the leaked ArgoCD
# Application `agent-sandbox` whose Helm-rendered Deployment collides with the
# OLM CSV-owned `agent-sandbox-controller` Deployment, driving the OLM hot
# retry loop that saturates cluster CPU (see ANALYSIS.md).
#
# Behaviour contract: specs/010-reduce-cpu-usage/contracts/repair-runbook-contract.md
#   - Preconditions verified before ANY change (exit 1, nothing touched, otherwise)
#   - Action executed exactly once; safe to re-run (idempotent)
#   - Postconditions probed until timeout
#
# Usage: scripts/repair-agent-sandbox-leak.sh
set -euo pipefail

APP_NAME="agent-sandbox"
WORK_NS="agent-sandbox-system"
DEPLOY="agent-sandbox-controller"
CSV_NAME="agent-sandbox-operator.v0.9.0"
PROBE_TIMEOUT=600          # 10m overall postcondition budget
QUIET_S=300                # 5m quiet window with zero InstallComponentFailed
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

log() { printf '[repair %s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

command -v oc >/dev/null 2>&1 || die "oc not found"
oc get --raw /healthz >/dev/null 2>&1 || die "cluster unreachable"

# Detect the GitOps namespace holding the Application (expect vp-gitops; do not
# hardcode - the pattern can rename it).
ARGO_NS=$(oc get application -A -o json 2>/dev/null | python3 -c "
import json, sys
hits = [i['metadata']['namespace'] for i in json.load(sys.stdin)['items']
        if i['metadata']['name'] == '$APP_NAME']
print(hits[0] if len(hits) == 1 else '')
")

if [ -z "$ARGO_NS" ]; then
  log "No Application/$APP_NAME found in exactly one namespace — no leak present, nothing to do."
  exit 0
fi
log "Leaked Application found in namespace: $ARGO_NS"

# --- Preconditions (contract 1..4) -------------------------------------------------

# P2: the app must not be declared in the local Git desired state (guards against
# resurrecting it in Git first, which would make deletion fight ArgoCD selfHeal).
python3 - "$ROOT/values-prod.yaml" <<'PY' || die "Application still declared in values-prod.yaml clusterGroup.applications — remove it from Git first"
import sys, yaml
apps = (yaml.safe_load(open(sys.argv[1])).get("clusterGroup") or {}).get("applications") or {}
sys.exit(0 if "agent-sandbox" not in apps else 1)
PY
log "precondition 2/4 OK: $APP_NAME absent from values-prod.yaml applications"

# P3: zero sandbox workloads anywhere (deleting the app cascades to its tracked
# controller Deployment; that is only safe while nothing uses the CRDs).
workloads=$(oc get sandboxes,sandboxclaims,sandboxtemplates,sandboxwarmpools -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$workloads" = "0" ] || die "found $workloads sandbox workload(s) — refusing to recycle the controller"
log "precondition 3/4 OK: zero sandbox custom resources"

# P4: the OLM side of the conflict must exist so ownership can transfer to it.
oc get csv "$CSV_NAME" -n "$WORK_NS" >/dev/null 2>&1 || die "CSV $CSV_NAME missing in $WORK_NS"
log "precondition 4/4 OK: CSV $CSV_NAME present (phase: $(oc get csv "$CSV_NAME" -n "$WORK_NS" -o jsonpath='{.status.phase}'))"

# --- Action (exactly once) ----------------------------------------------------------

log "deleting Application/$APP_NAME in $ARGO_NS (foreground finalizer cascades to the 4 tracked objects)"
oc delete application "$APP_NAME" -n "$ARGO_NS" --wait=true --timeout="${PROBE_TIMEOUT}s"
log "Application deleted"

# --- Postconditions (probe until timeout) -------------------------------------------

deadline=$(( $(date +%s) + PROBE_TIMEOUT ))
remaining() { echo $(( deadline - $(date +%s) )); }

# P5.1: app NotFound
if oc get application "$APP_NAME" -n "$ARGO_NS" >/dev/null 2>&1; then
  die "Application $APP_NAME still present after delete"
fi
log "postcondition 1/5 OK: Application gone"

# P5.2: OLM recreated the Deployment and it is no longer Helm/ArgoCD-marked
log "waiting for OLM to recreate Deployment/$DEPLOY ..."
while true; do
  [ "$(remaining)" -gt 0 ] || die "timed out waiting for OLM to recreate $DEPLOY"
  if oc get deploy "$DEPLOY" -n "$WORK_NS" >/dev/null 2>&1; then
    labels=$(oc get deploy "$DEPLOY" -n "$WORK_NS" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}{"|"}{.metadata.annotations.argocd\.argoproj\.io/tracking-id}')
    managed_by="${labels%%|*}"
    track="${labels##*|}"
    if [ "$managed_by" != "Helm" ] && [ -z "$track" ]; then
      log "postcondition 2/5 OK: Deployment recreated by OLM (managed-by='${managed_by:-none}', no ArgoCD tracking)"
      break
    fi
  fi
  sleep 5
done

# P5.3: CSV reaches Succeeded
log "waiting for CSV $CSV_NAME to reach Succeeded ..."
while true; do
  [ "$(remaining)" -gt 0 ] || die "timed out waiting for CSV Succeeded (break-glass: capture 'oc get csv $CSV_NAME -n $WORK_NS -o yaml' and events, then escalate)"
  phase=$(oc get csv "$CSV_NAME" -n "$WORK_NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  [ "$phase" = "Succeeded" ] && break
  sleep 10
done
log "postcondition 3/5 OK: CSV phase Succeeded"

# P5.4: no InstallComponentFailed events for a quiet window
log "watching $((QUIET_S / 60))m quiet window for InstallComponentFailed events ..."
quiet_deadline=$(( $(date +%s) + QUIET_S ))
while [ "$(date +%s)" -lt "$quiet_deadline" ]; do
  if oc get events -n "$WORK_NS" --field-selector reason=InstallComponentFailed -o json 2>/dev/null | python3 -c "
import json, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc)
for e in json.load(sys.stdin).get('items', []):
    ts = e.get('lastTimestamp') or e.get('eventTime') or ''
    try:
        t = datetime.datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except ValueError:
        continue
    if (now - t).total_seconds() < $QUIET_S:
        sys.exit(1)
"; then
    :
  else
    die "new InstallComponentFailed event during quiet window — OLM still fighting"
  fi
  sleep 30
done
log "postcondition 4/5 OK: no install-failure events in last 5m"

# P5.5: CSV PUT rate collapsed (PromQL via in-cluster Prometheus)
rate=$(oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -- \
  curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=sum(rate(apiserver_request_total{verb="PUT", resource="clusterserviceversions"}[5m]))' \
  | python3 -c "
import json, sys
r = json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else '0')
" 2>/dev/null || echo "unknown")
if [ "$rate" != "unknown" ]; then
  python3 -c "import sys; sys.exit(0 if float('$rate') < 0.1 else 1)" \
    || die "CSV PUT rate still high: ${rate}/s (threshold 0.1/s)"
  log "postcondition 5/5 OK: CSV PUT rate ${rate}/s (< 0.1/s)"
else
  log "postcondition 5/5 SKIPPED: prometheus exec probe unavailable — measure at G1 acceptance instead"
fi

log "REPAIR COMPLETE — $((PROBE_TIMEOUT - $(remaining)))s elapsed"
