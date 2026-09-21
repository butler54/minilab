#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/observability-config"
values="$root/values-global.yaml"

rendered=$(helm template observability-config "$chart" -f "$values")

# Three PersesDashboards must render in the configured stack namespace.
for dashboard in openshift-system-overview application-overview external-components; do
  echo "$rendered" | yq e 'select(.kind == "PersesDashboard" and .metadata.name == "'"$dashboard"'")' - >/dev/null \
    || { echo "missing dashboard: $dashboard"; exit 1; }
done

# The external dashboard must reference the stack datasource.
external_datasources=$(echo "$rendered" | yq e 'select(.kind == "PersesDashboard" and .metadata.name == "external-components") | .. | select(.kind? == "PrometheusTimeSeriesQuery") | .spec.datasource' -)
[[ "$external_datasources" == *"minilab-stack"* ]] \
  || { echo "external dashboard does not reference stack datasource"; exit 1; }

# UIPlugin must render with Perses enabled.
echo "$rendered" | yq e 'select(.kind == "UIPlugin") | .spec.monitoring.perses.enabled' - | grep -qx 'true' \
  || { echo "UIPlugin does not enable Perses"; exit 1; }

# Platform-backed dashboards live in COO's project and use its operator-managed
# authenticated default Thanos datasource rather than a duplicate custom proxy.
for dashboard in openshift-system-overview application-overview; do
  echo "$rendered" | yq e 'select(.kind == "PersesDashboard" and .metadata.name == "'"$dashboard"'") | .metadata.namespace' - \
    | grep -qx 'openshift-cluster-observability-operator' \
    || { echo "platform dashboard $dashboard is not in the COO project"; exit 1; }
done
application_variable=$(echo "$rendered" | yq e 'select(.kind == "PersesDashboard" and .metadata.name == "application-overview") | .spec.config.variables[0].spec.plugin.spec' -)
echo "$application_variable" | yq e 'has("metricName")' - | grep -qx 'false' \
  || { echo "application namespace variable uses unsupported metricName"; exit 1; }

printf 'observability dashboards validation passed\n'
