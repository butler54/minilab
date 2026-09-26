#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for value in values-global.yaml values-prod.yaml overrides/values-storage-lvm.yaml overrides/values-openshell.yaml; do yq eval '.' "$root/$value" >/dev/null; done
for chart in charts/lvms-config charts/observability-config charts/openshell-platform charts/openshell-policy charts/openshell-demo charts/cert-manager-config charts/openshell-keycloak-config; do helm lint "$root/$chart" -f "$root/values-global.yaml" >/dev/null; helm template "${chart##*/}" "$root/$chart" -f "$root/values-global.yaml" >/dev/null; done
bash -n "$root/scripts/bootstrap-local-storage.sh"
printf 'pattern configuration validation passed\n'
