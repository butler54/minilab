#!/usr/bin/env bash
# Feature 010 US3 / monitoring-config-contract: the openshift-monitoring-config
# chart ships exactly one ConfigMap carrying prometheusK8s.collectionProfile:
# minimal (and nothing else), is registered in values-prod.yaml, and the
# pattern-owned scrape interval is pinned to 60s end-to-end.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# 1. Application registered in values-prod.yaml pointing at the local chart.
python3 - "$root/values-prod.yaml" <<'PY'
import sys, yaml

apps = (yaml.safe_load(open(sys.argv[1])).get("clusterGroup") or {}).get("applications") or {}
app = apps.get("openshift-monitoring-config")
if not app:
    sys.exit("clusterGroup.applications['openshift-monitoring-config'] missing from values-prod.yaml")
if app.get("path") != "charts/openshift-monitoring-config":
    sys.exit("openshift-monitoring-config path=%r (expect charts/openshift-monitoring-config)" % app.get("path"))
PY

# 2. Chart is present and renders exactly one scoped ConfigMap.
chart="$root/charts/openshift-monitoring-config"
for f in Chart.yaml values.yaml templates/cluster-monitoring-config.yaml; do
  [ -f "$chart/$f" ] || { echo "missing $chart/$f"; exit 1; }
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
helm template openshift-monitoring-config "$chart" >"$tmpdir/render.yaml"

python3 - "$tmpdir/render.yaml" <<'PY'
import sys, yaml

docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
if len(docs) != 1:
    sys.exit("expected exactly 1 rendered object, got %d" % len(docs))
cm = docs[0]
if cm.get("kind") != "ConfigMap" or cm["metadata"]["name"] != "cluster-monitoring-config" \
        or cm["metadata"]["namespace"] != "openshift-monitoring":
    sys.exit("unexpected rendered object: %r" % cm["metadata"])
cfg = yaml.safe_load(cm["data"]["config.yaml"])
if list(cfg) != ["prometheusK8s"]:
    sys.exit("config.yaml claims unexpected CMO keys (scope discipline): %r" % sorted(cfg))
if cfg["prometheusK8s"].get("collectionProfile") != "minimal":
    sys.exit("collectionProfile=%r (expect minimal)" % cfg["prometheusK8s"].get("collectionProfile"))
PY

# 3. Pattern-owned scrape cadence pinned to 60s in the overlay values.
python3 - "$root/overrides/values-observability.yaml" <<'PY'
import sys, yaml

obs = (yaml.safe_load(open(sys.argv[1])).get("global") or {}).get("observability") or {}
if str(obs.get("scrapeInterval")) != "60s":
    sys.exit("global.observability.scrapeInterval=%r (expect '60s')" % obs.get("scrapeInterval"))
PY

# 4. The 60s lands on every external-target ServiceMonitor endpoint.
rendered=$(helm template observability-config "$root/charts/observability-config" \
  -f "$root/values-global.yaml" -f "$root/overrides/values-observability.yaml" \
  --set 'global.observability.externalTargets[0].url=http://192.0.2.10:9100/metrics')
interval=$(echo "$rendered" | yq e 'select(.kind == "ServiceMonitor" and .metadata.name == "external-0") | .spec.endpoints[0].interval' -)
[ "$interval" = "60s" ] || { echo "external ServiceMonitor interval=$interval (expect 60s)"; exit 1; }

echo "monitoring config validation passed"
