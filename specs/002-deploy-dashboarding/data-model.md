# Data Model: Deploy Dashboarding Tools

## Dashboarding Platform

| Field | Meaning | Validation |
|-------|---------|------------|
| `uiPlugin` | Monitoring `UIPlugin` enabling the Perses server and console integration | `spec.type: monitoring`, `spec.monitoring.perses.enabled: true`; reconciled condition Available |
| `accessPoint` | OpenShift console `Observe > Dashboards (Perses)` | Reachable under cluster OAuth; unauthorized access denied |
| `persesProject` | Namespace-to-Perses-project mapping for dashboard scoping | One Perses project per namespace; RBAC-scoped |

**Lifecycle**: COO installed -> UIPlugin created -> Perses server available -> dashboards/datasources synced into projects -> console access available.

## Metrics Stack

| Field | Meaning | Validation |
|-------|---------|------------|
| `retention` | Time-series retention for the stack | `30d` (FR-011a) |
| `replicas` | Prometheus replica count | 1 for the SNO budget |
| `resourceSelector` | Labels selecting ServiceMonitor/ScrapeConfig/PrometheusRule | Must match declared resources for the stack |
| `namespaceSelector` | Labels selecting namespaces the stack monitors | Covers external-component and application namespaces |
| `storageClass` | PVC class for the stack Prometheus TSDB | `lvms-loopback` via override |
| `alertmanagerEnabled` | Alertmanager deployed with the stack | Enabled; receivers/route declared |

**Lifecycle**: MonitoringStack created -> Prometheus/Thanos/Alertmanager deployed -> targets discovered -> metrics scraped -> alerts evaluated.

## Datasources

| Field | Meaning | Validation |
|-------|---------|------------|
| `kind` | `PersesDatasource` (namespaced) or `PersesGlobalDatasource` (cluster-scoped) | Appropriate scope for the target |
| `target` | Metrics backend | In-cluster Thanos Querier for system/application; COO stack Prometheus/Thanos for external |
| `plugin` | Datasource plugin type | Prometheus/Thanos |

**Relationships**: A datasource is referenced by one or more dashboards' panels; a global datasource is available to all projects, a namespaced one only within its project.

## Dashboards

| Field | Meaning | Validation |
|-------|---------|------------|
| `domain` | Monitoring domain | One of: OCP system, application, external |
| `name` | `PersesDashboard` metadata name | DNS-1123, unique per project |
| `namespace` | Perses project (namespace) | Dashboard appears in that project |
| `panels` | Panel definitions (`TimeSeriesChart`, `StatChart`, etc.) | Queries resolve against an available datasource |
| `variables` | Optional dynamic variables | Values resolvable from the datasource |
| `revision` | Git-tracked definition version | Reconciles via Argo CD |

**Lifecycle**: Declared in Git -> Argo CD applies -> Perses operator syncs to project -> visible in console. Invalid declaration fails validation without breaking other resources.

## Alert Rules

| Field | Meaning | Validation |
|-------|---------|------------|
| `domain` | Monitoring domain | One of: OCP system, application, external |
| `expr` | PromQL threshold condition | Evaluates against the stack Prometheus |
| `for` | Duration the condition must hold | Drives firing latency (SC-003 evaluation interval) |
| `labels.severity` | critical/warning/info | Used for routing and inhibition |
| `namespace` | Matches the `PrometheusRule` namespace | Selected by stack `resourceSelector` |

**Lifecycle**: Declared -> selected by stack -> evaluated -> firing/resolved -> routed to Alertmanager -> PagerDuty.

## Alert Delivery

| Field | Meaning | Validation |
|-------|---------|------------|
| `receiver` | Alertmanager receiver | Single PagerDuty receiver (sole destination, FR-009) |
| `routingKey` | PagerDuty Events API v2 integration key | Sourced from a vault-backed Secret; never in Git |
| `route` | Default route and any domain sub-routes | All stack alerts reach PagerDuty |
| `sendResolved` | Resolution notifications | Enabled so auto-resolved alerts are delivered (FR-010) |
| `groupBy` / intervals | Grouping and repeat controls | Defaults with critical-warning inhibition to avoid floods |

**Relationship**: Alert rules produce alerts; Alertmanager groups/routes them to the PagerDuty receiver; alert state remains visible in the dashboarding platform even if delivery fails.

## Access Control

| Field | Meaning | Validation |
|-------|---------|------------|
| `role` | Perses ClusterRole | `*-viewer-role` or `*-editor-role` per resource |
| `binding` | `RoleBinding` (project) or `ClusterRoleBinding` (cluster) | Grant to OpenShift groups |
| `subjectGroup` | OpenShift group receiving the grant | Authenticated via cluster OAuth (FR-012) |

**Relationship**: One access-control scope (viewer vs editor, project vs cluster) per user group.