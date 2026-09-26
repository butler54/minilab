#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
prod="$root/values-prod.yaml"
wave() { yq -r ".clusterGroup.applications.$1.annotations.\"argocd.argoproj.io/sync-wave\"" "$prod"; }
[[ $(wave lvms-config) == -10 && $(wave vault) == +10 ]]
[[ $(yq -r '.clusterGroup.namespaces.openshift-storage.operatorGroup' "$prod") == true ]]
[[ $(yq -r '.clusterGroup.namespaces.openshift-storage.targetNamespaces[0]' "$prod") == openshift-storage ]] || {
  printf 'LVMS OperatorGroup must be OwnNamespace (openshift-storage), not AllNamespaces\n' >&2; exit 1;
}
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.installPlanApproval' "$prod") == Automatic ]]
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.channel' "$prod") == stable-4.22 ]]
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.csv' "$prod") == lvms-operator.v4.22.0 ]]
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.channel' "$prod") == $(yq -r '.global.lvmsCompatibility.channel' "$root/values-global.yaml") ]]
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.csv' "$prod") == $(yq -r '.global.lvmsCompatibility.startingCSV' "$root/values-global.yaml") ]]
config=$(helm template lvms-config "$root/charts/lvms-config" -f "$root/values-global.yaml")
[[ $(yq -r '.global.lvmsCompatibility.ocpRelease' "$root/values-global.yaml") == 4.22 ]]
[[ $config == *'kind: LVMCluster'* && $config == *'name: loopback'* && $config == *'argocd.argoproj.io/hook: Sync'* && $config == *'sync-wave: "-2"'* && $config == *'sync-wave: "-1"'* && $config == *'sync-wave: "0"'* && $config == *'lvms-operator.v4.22.0'* && $config == *'ocp-v4.0-art-dev@sha256:84b0aa6c19cdedba485212a5b599bdb9fd6975d5c808aaf4f115500b782ee600'* && $config == *'volumeBindingMode: WaitForFirstConsumer'* && $config == *'overprovisionRatio: 1'* && $config == *'node-role.kubernetes.io/control-plane'* ]]
printf 'LVMS rendering and sync ordering passed\n'
