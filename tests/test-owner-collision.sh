#!/usr/bin/env bash
# FR-001 regression check (feature 010): no GitOps-tracked Deployment may
# collide with an OLM CSV-owned Deployment — the exact incident class that
# drove the OLM/ArgoCD reconciliation war on agent-sandbox.
# Live-cluster probe; skips gracefully when the cluster is unreachable.
set -euo pipefail

if ! oc get --raw /healthz >/dev/null 2>&1; then
  echo "skip: cluster unreachable (owner-collision)"
  exit 0
fi

# OLM-owned workloads ("namespace/deployment") from every CSV's install spec.
# CSV copies OLM replicates to other namespaces resolve back to the operator
# namespace via the olm.operatorNamespace annotation.
mapfile -t owned < <(oc get csv -A -o json | python3 -c "
import json, sys
seen = set()
for csv in json.load(sys.stdin)['items']:
    meta = csv.get('metadata', {})
    ns = meta.get('annotations', {}).get('olm.operatorNamespace', meta.get('namespace', ''))
    for dep in (((csv.get('spec') or {}).get('install') or {}).get('spec') or {}).get('deployments') or []:
        key = f\"{ns}/{dep['name']}\"
        if key not in seen:
            seen.add(key)
            print(key)
")

collisions=0
while read -r ns name track; do
  [ -n "${track:-}" ] || continue
  key="$ns/$name"
  if printf '%s\n' "${owned[@]:-}" | grep -qx "$key"; then
    echo "COLLISION: Deployment $key is ArgoCD-tracked ($track) but is owned by an OLM CSV"
    collisions=$((collisions + 1))
  fi
done < <(oc get deploy -A -o json | python3 -c "
import json, sys
for d in json.load(sys.stdin)['items']:
    m = d['metadata']
    print(m['namespace'], m['name'], m.get('annotations', {}).get('argocd.argoproj.io/tracking-id', ''))
")

if [ "$collisions" -gt 0 ]; then
  echo "owner-collision: $collisions GitOps/OLM ownership conflict(s) found"
  exit 1
fi
echo "owner-collision: no GitOps/OLM deployment ownership conflicts"
