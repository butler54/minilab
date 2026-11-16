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
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.channel' "$prod") == stable-5.0 ]]
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.csv' "$prod") == lvms-operator.v5.0.0 ]]
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.channel' "$prod") == $(yq -r '.global.lvmsCompatibility.channel' "$root/values-global.yaml") ]]
[[ $(yq -r '.clusterGroup.subscriptions.lvms-operator.csv' "$prod") == $(yq -r '.global.lvmsCompatibility.startingCSV' "$root/values-global.yaml") ]]
config=$(helm template lvms-config "$root/charts/lvms-config" -f "$root/values-global.yaml")
[[ $(yq -r '.global.lvmsCompatibility.ocpRelease' "$root/values-global.yaml") == 5.0 ]]
[[ $config == *'kind: LVMCluster'* && $config == *'name: loopback'* && $config == *'argocd.argoproj.io/hook: Sync'* && $config == *'sync-wave: "-2"'* && $config == *'sync-wave: "-1"'* && $config == *'sync-wave: "0"'* && $config == *'lvms-operator.v5.0.0'* && $config == *'ocp-v5.0-art-dev@sha256:74e57568b3a1bcf36a85f5cef0861bc979fb86fd457710d31edc8e61d86ee02f'* && $config == *'volumeBindingMode: WaitForFirstConsumer'* && $config == *'overprovisionRatio: 1'* && $config == *'node-role.kubernetes.io/control-plane'* ]]
# Convergence T035: readiness job resolves global.lvmsCompatibility.daemonSet (no
# hardcoded topolvm-controller/topolvm-node — those never existed on this cluster),
# and the readiness netpol (LVMS 5.0.0 default-deny workaround) renders the API
# egress (TCP 6443 — OVN evaluates post-DNAT) and openshift-dns (5353 TCP/UDP).
[[ $config == *'rollout status daemonset/vg-manager'* && $config != *'topolvm-controller'* && $config != *'topolvm-node'* ]]
[[ $config == *'kind: NetworkPolicy'* && $config == *'name: lvms-config-readiness-allow'* && $config == *'app.kubernetes.io/name: lvms-config-readiness'* && $config == *'port: 6443'* && $config == *'port: 5353'* && $config == *'openshift-dns'* ]]
printf 'LVMS rendering and sync ordering passed\n'
