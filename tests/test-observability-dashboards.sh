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
echo "$rendered" | yq e 'select(.kind == "PersesDashboard" and .metadata.name == "external-components") | .. | select(.kind? == "PrometheusTimeSeriesQuery") | .spec.datasource' - \
  | grep -q 'minilab-stack' || { echo "external dashboard does not reference stack datasource"; exit 1; }

# UIPlugin must render with Perses enabled.
echo "$rendered" | yq e 'select(.kind == "UIPlugin") | .spec.monitoring.perses.enabled' - | grep -qx 'true' \
  || { echo "UIPlugin does not enable Perses"; exit 1; }

# Global datasource for platform metrics must render.
echo "$rendered" | yq e 'select(.kind == "PersesGlobalDatasource" and .metadata.name == "thanos-querier")' - >/dev/null \
  || { echo "missing platform global datasource"; exit 1; }

printf 'observability dashboards validation passed\n'