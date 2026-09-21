#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/observability-config"
values="$root/values-global.yaml"

rendered=$(helm template observability-config "$chart" -f "$values")

# The Alertmanager config Secret must contain a PagerDuty receiver and a
# default route (rendered by the ExternalSecret with the routing key from Vault).
amsec=$(echo "$rendered" | python3 -c "
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind') == 'ExternalSecret' and d.get('metadata',{}).get('name') == 'alertmanager-minilab':
        print(d['spec']['target']['template']['data']['alertmanager.yaml'])
")
echo "$amsec" | grep -q 'routing_key:' || { echo "Alertmanager config missing PagerDuty routing key"; exit 1; }
echo "$amsec" | grep -q 'receiver: pagerduty' || { echo "Alertmanager config default route does not target pagerduty"; exit 1; }
echo "$amsec" | grep -q 'send_resolved: true' || { echo "Alertmanager config does not send resolved alerts"; exit 1; }
echo "$amsec" | grep -q 'pagerduty_configs' || { echo "Alertmanager config missing PagerDuty receiver"; exit 1; }

# One PrometheusRule per domain, selected by the stack resourceSelector label.
for rule in minilab-system-alerts minilab-application-alerts minilab-external-alerts; do
  echo "$rendered" | yq e 'select(.kind == "PrometheusRule" and .metadata.name == "'"$rule"'") | .metadata.labels["app.kubernetes.io/part-of"]' - | grep -q 'minilab-observability' \
    || { echo "PrometheusRule $rule missing stack selector label"; exit 1; }
done

# Each domain rule must define at least one alert.
for rule in minilab-system-alerts minilab-application-alerts minilab-external-alerts; do
  count=$(echo "$rendered" | yq e 'select(.kind == "PrometheusRule" and .metadata.name == "'"$rule"'") | .spec.groups[].rules | length' - | tail -1)
  [ "$count" -ge 1 ] || { echo "PrometheusRule $rule has no rules"; exit 1; }
done

printf 'observability alerts validation passed\n'