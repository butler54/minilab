# Observability Configuration Contract

## Cluster Values Interface

| Value | Contract |
|-------|----------|
| `global.observability.enabled` | When true, the observability configuration chart and COO resources are declared. |
| `global.observability.stackNamespace` | Namespace hosting the `MonitoringStack`, datasources, dashboards, and alert rules. |
| `global.observability.retention` | Time-series retention for the stack; default `30d`. |
| `global.observability.storageClass` | PVC class for stack persistence; defaults to the pattern's `lvms-loopback`. |
| `global.observability.externalTargets` | List of external HTTP/HTTPS Prometheus exporter endpoints (`url`, optional `labels`) for `ScrapeConfig` static targets. |
| `values-secret.yaml.template` | Declares the `pagerduty-routing-key` secret field; real key lives only in vault. |

## GitOps Declaration

| Component | Where declared | Reconcile effect |
|-----------|----------------|------------------|
| COO subscription | `values-prod.yaml` `clusterGroup.subscriptions` | Installs COO and Perses Operator + CRDs |
| COO namespace | `values-prod.yaml` `clusterGroup.namespaces` | Creates `openshift-cluster-observability-operator` (and stack namespace) |
| Monitoring `UIPlugin` | `charts/observability-config/templates/` | Deploys Perses server + console plugin |
| `MonitoringStack` | `charts/observability-config/templates/` | Deploys Prometheus/Thanos/Alertmanager with retention |
| `PersesDashboard` / `PersesDatasource` / `PersesGlobalDatasource` | `charts/observability-config/templates/` | Synced into Perses projects; visible in console |
| `PrometheusRule` / `ServiceMonitor` / `ScrapeConfig` | `charts/observability-config/templates/` | Selected by stack; targets and alerts live |
| `Alertmanager` config Secret + PagerDuty routing key | `charts/observability-config/templates/` (ExternalSecret) | Alerts routed to PagerDuty via the operator-native `alertmanager-<stack>` secret |
| RBAC bindings | `charts/observability-config/templates/` | Viewer/editor grants to OpenShift groups |

## Exit Behavior

| Condition | Expected result |
|-----------|-----------------|
| COO/Perses not ready | Dashboards do not appear; reconciliation continues to be retried; other pattern workloads unaffected. |
| External target unreachable | Only that target's dashboards show no data; system/application domains unaffected. |
| Invalid dashboard/datasource/alert-rule declaration | Applies fail with an actionable validation error; existing valid resources remain reconciled. |
| PagerDuty unreachable | Alert state remains visible in the dashboarding platform; retries continue. |
| Node/cluster restart | Stack PVCs and CR definitions persist; dashboards and alert rules restored by Argo CD. |

For domain fields and state transitions, see [data-model.md](../data-model.md).