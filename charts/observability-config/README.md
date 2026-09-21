# observability-config

Configures the Cluster Observability Operator (COO) dashboarding and alerting for the Minilab pattern.

## Components

- **Monitoring `UIPlugin`**: enables the Red Hat build of Perses in the OpenShift console under `Observe > Dashboards (Perses)`.
- **`MonitoringStack`**: one lightweight Prometheus (plus Thanos and Alertmanager) used to scrape external Prometheus exporters and evaluate alert rules; 30-day retention, persistent storage on the pattern's LVMS class.
- **Perses datasources and dashboards**: `PersesGlobalDatasource`/`PersesDatasource` for the in-cluster Thanos Querier and the stack Prometheus; `PersesDashboard` resources for OCP system workloads, application workloads, and external components. All dashboards are managed as code in this chart.
- **Alertmanager to PagerDuty**: single PagerDuty receiver and default route delivered through the operator-native config Secret (`alertmanager-<stack>` with `alertmanager.yaml`, rendered by the ExternalSecret with the routing key templated from Vault — never in Git).
- **RBAC**: Perses viewer/editor role bindings to OpenShift groups for controlled access.

## Configuration Surface

| Value | Purpose |
|-------|---------|
| `global.observability.enabled` | Enable/disable the whole observability configuration |
| `global.observability.stackNamespace` | Namespace hosting the stack, dashboards, and alert resources |
| `global.observability.retention` | Time-series retention for the stack (default `30d`) |
| `global.observability.storageClass` | PVC class for stack persistence (default `lvms-loopback`) |
| `global.observability.externalTargets` | List of external HTTP/HTTPS Prometheus exporter endpoints |
| `global.observability.dashboards` | Additional `PersesDashboard` definitions (Dashboards-as-Code) |
| `global.observability.alertRules` | Additional `PrometheusRule` definitions |
| `global.observability.rbac.viewerGroup` / `editorGroup` | OpenShift groups granted Perses viewer/editor roles |
| `pagerduty.*` | External-secret mapping for the PagerDuty routing key |

## Notes

- Requires the COO subscription (declared in the cluster values) and the pattern's vault/external-secrets and storage prerequisites.
- Exact COO channel/CSV and CRD API versions must be verified against the target OpenShift release; see `specs/002-deploy-dashboarding/research.md`.