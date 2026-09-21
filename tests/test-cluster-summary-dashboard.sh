#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/observability-config"
global="$root/values-global.yaml"
prod="$root/values-prod.yaml"

# The existing LVMS ServiceMonitor is selected by platform monitoring only when
# this namespace label is declared through GitOps.
yq -e '.clusterGroup.namespaces.openshift-storage.labels."openshift.io/cluster-monitoring" == "true"' "$prod" >/dev/null \
  || { echo "openshift-storage is not enabled for platform monitoring"; exit 1; }

rendered=$(helm template observability-config "$chart" -f "$global")
dashboard=$(echo "$rendered" | yq e 'select(.kind == "PersesDashboard" and .metadata.name == "single-node-cluster-summary")' -)

echo "$dashboard" | yq e '.spec.config.display.name' - | grep -q 'Single-Node OpenShift Cluster Summary' \
  || { echo "single-node cluster summary dashboard missing"; exit 1; }

# All summary queries use the existing global platform Thanos datasource.
datasource_count=$(echo "$dashboard" | yq e '.. | select(.kind? == "PrometheusTimeSeriesQuery") | .spec.datasource' - | grep -c 'thanos-querier' || true)
[ "$datasource_count" -ge 9 ] \
  || { echo "cluster summary panels do not use the platform Thanos datasource"; exit 1; }

# Single-node context and cluster health/capacity panels must be present.
for panel in singleNodeCount readyNodes degradedOperators clusterCpu clusterMemory; do
  echo "$dashboard" | yq e ".spec.config.panels.$panel.kind" - | grep -q Panel \
    || { echo "missing cluster summary panel: $panel"; exit 1; }
done

# LVMS queries use verified vg-manager capacity metrics for the loopback device class.
queries=$(echo "$dashboard" | yq e '.. | select(.kind? == "PrometheusTimeSeriesQuery") | .spec.query' -)
for metric in topolvm_volumegroup_size_bytes topolvm_volumegroup_available_bytes topolvm_thinpool_data_percent topolvm_thinpool_metadata_percent; do
  [[ "$queries" == *"$metric"* ]] || { echo "missing LVMS metric query: $metric"; exit 1; }
done

printf 'cluster summary dashboard render validation passed\n'
