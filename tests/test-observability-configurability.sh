#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/observability-config"
values="$root/values-global.yaml"

rendered=$(helm template observability-config "$chart" -f "$values" \
  --set 'global.observability.externalTargets[0].url=http://192.168.1.50:9100/metrics' \
  --set 'global.observability.dashboards[0].name=my-app' \
  --set 'global.observability.dashboards[0].title=My App' \
  --set 'global.observability.dashboards[0].panels[0].name=reqRate' \
  --set 'global.observability.dashboards[0].panels[0].title=Request Rate' \
  --set 'global.observability.dashboards[0].panels[0].query=rate(http_requests_total[5m])' \
  --set 'global.observability.alertRules[0].name=my-rules' \
  --set 'global.observability.alertRules[0].rules[0].name=HighErrors' \
  --set 'global.observability.alertRules[0].rules[0].expr=rate(errors_total[5m]) > 10')

# Values-added external target produces a ScrapeConfig without chart edits.
echo "$rendered" | yq e 'select(.kind == "ScrapeConfig") | .spec.staticConfigs[0].targets[0]' - | grep -q '192.168.1.50:9100' \
  || { echo "external target not rendered"; exit 1; }

# Values-added dashboard appears in the rendered set.
echo "$rendered" | yq e 'select(.kind == "PersesDashboard" and .metadata.name == "my-app")' - >/dev/null \
  || { echo "values-added dashboard not rendered"; exit 1; }

# Values-added alert rule is active.
echo "$rendered" | yq e 'select(.kind == "PrometheusRule" and .metadata.name == "my-rules") | .spec.groups[].rules[] | select(.alert == "HighErrors") | .expr' - | grep -q 'errors_total' \
  || { echo "values-added alert rule not rendered"; exit 1; }

# Invalid dashboard name must be rejected by the chart schema.
if helm template observability-config "$chart" -f "$values" \
    --set 'global.observability.dashboards[0].name=Bad Name!' \
    --set 'global.observability.dashboards[0].title=x' \
    --set 'global.observability.dashboards[0].panels[0].name=p' \
    --set 'global.observability.dashboards[0].panels[0].title=t' \
    --set 'global.observability.dashboards[0].panels[0].query=q' >/dev/null 2>&1; then
  echo "invalid dashboard name was not rejected"; exit 1
fi

printf 'observability configurability validation passed\n'