#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/lvms-config"
values="$root/values-global.yaml"

rendered=$(helm template lvms-config "$chart" -f "$values")

# The LVMCluster device class must be marked default so LVMS sets the generated
# StorageClass as the cluster default (LVMS-native, survives operator reconcile).
lvm=$(echo "$rendered" | yq e 'select(.kind == "LVMCluster")' -)
echo "$lvm" | yq e '.spec.storage.deviceClasses[0].name' - | grep -q 'loopback' \
  || { echo "LVMCluster missing loopback device class"; exit 1; }
echo "$lvm" | yq e '.spec.storage.deviceClasses[0].default' - | grep -q 'true' \
  || { echo "LVMCluster device class is not marked default"; exit 1; }

# When disabled, the device class is not marked default.
disabled=$(helm template lvms-config "$chart" -f "$values" --set 'global.localStorage.defaultStorageClass.lvmClusterDefaultDeviceClass=false')
echo "$disabled" | yq e 'select(.kind == "LVMCluster") | .spec.storage.deviceClasses[0].default' - | grep -q 'false' \
  || { echo "LVMCluster device class still default when disabled"; exit 1; }

# The LVMCluster may carry no default flag (empty) when the value is unset;
# assert the schema-compatible rendering for the enabled default case only.

printf 'default storage class validation passed\n'