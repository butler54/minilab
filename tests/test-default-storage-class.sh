#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/lvms-config"
values="$root/values-global.yaml"

rendered=$(helm template lvms-config "$chart" -f "$values")

# The scheduled Job must render with the target class, image, and RBAC reference.
job=$(echo "$rendered" | yq e 'select(.kind == "CronJob" and .metadata.name == "minilab-lvmcluster-default-storage")' -)
echo "$job" | yq e '.spec.jobTemplate.spec.template.spec.serviceAccountName' - | grep -q 'minilab-lvmcluster-default-storage' \
  || { echo "CronJob missing ServiceAccount reference"; exit 1; }
echo "$job" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].image' - | grep -q 'ose-cli' \
  || { echo "CronJob missing ose-cli image"; exit 1; }
echo "$job" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].args[0]' - | grep -q 'lvms-loopback' \
  || { echo "CronJob does not target lvms-loopback"; exit 1; }

# The Job logic must be idempotent (exit 0 when already default) and must only
# act when no default exists (foreign-default no-op).
args=$(echo "$job" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].args[0]' -)
echo "$args" | grep -q 'is already the default storage class; nothing to do' \
  || { echo "CronJob missing already-default no-op branch"; exit 1; }
echo "$args" | grep -q 'Another storage class is already the cluster default' \
  || { echo "CronJob missing foreign-default no-op branch"; exit 1; }
echo "$args" | grep -q 'marking \$target as default' \
  || { echo "CronJob missing annotate action"; exit 1; }

# Idempotence / drift recovery (US2): the logic restores a removed annotation
# on a later run and never creates a duplicate default. The already-default and
# annotate branches above prove the decision rule; assert the annotate action
# uses --overwrite so a re-annotation is idempotent.
echo "$args" | grep -q -- '--overwrite' \
  || { echo "CronJob annotate action is not idempotent (missing --overwrite)"; exit 1; }

# Explicit-choice / implicit-binding contract (US3): the mechanism only touches
# the default-class annotation, never a claim's explicit storageClass. The
# CronJob must not render any PersistentVolumeClaim or claim-binding logic.
echo "$job" | grep -q 'PersistentVolumeClaim' \
  && { echo "CronJob unexpectedly manages PVCs"; exit 1; } || true

# When the feature is disabled, no CronJob or RBAC renders.
disabled=$(helm template lvms-config "$chart" -f "$values" --set 'global.localStorage.defaultStorageClass.enabled=false')
[ "$(echo "$disabled" | yq e '[. | select(.kind == "CronJob")] | length' - | tail -1)" -eq 0 ] \
  || { echo "CronJob rendered when disabled"; exit 1; }
[ "$(echo "$disabled" | yq e '[. | select(.metadata.name == "minilab-lvmcluster-default-storage")] | length' - | tail -1)" -eq 0 ] \
  || { echo "default-storage RBAC rendered when disabled"; exit 1; }

printf 'default storage class validation passed\n'