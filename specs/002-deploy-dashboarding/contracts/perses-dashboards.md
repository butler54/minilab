# Perses Dashboards Contract

## Dashboard-as-Code Contract

| Field | Contract |
|-------|----------|
| API version | `perses.dev/v1alpha2` (assert against target COO release) |
| Kind | `PersesDashboard` |
| Namespace | Maps to a Perses project; dashboards appear under `Observe > Dashboards (Perses)` for that project |
| Metadata name | DNS-1123; unique within the project |
| `spec.config.display.name` | Human-readable dashboard title |
| `spec.config.panels` | Panel definitions using supported plugins (TimeSeriesChart, StatChart, GaugeChart, Markdown) |
| `spec.config.panels.*.queries` | `PrometheusTimeSeriesQuery` referencing a datasource plugin |
| Datasource resolution | Explicit `datasource` on the query, or automatic default detection from datasources present in the project |

## Managed Domains

| Domain | Dashboard identity | Datasource target |
|--------|--------------------|-------------------|
| OCP system workloads | e.g., `openshift-system-overview` | In-cluster Thanos Querier (platform metrics) |
| Application workloads | e.g., `application-overview` | In-cluster Thanos Querier (user-workload metrics) or stack Prometheus |
| External components | e.g., `external-components` | COO stack Prometheus/Thanos (external scrape targets) |

## RBAC Contract

| Role binding | Effect |
|--------------|--------|
| `persesdashboard-viewer-role` (RoleBinding in project) | View dashboards in that project |
| `persesdashboard-editor-role` (RoleBinding in project) | Create/edit/delete dashboards in that project |
| `persesdatasource-viewer-role` / `-editor-role` | View/manage namespaced datasources |
| `persesglobaldatasource-viewer-role` / `-editor-role` (ClusterRoleBinding) | View/manage cluster-scoped datasources |
| No binding | User sees no dashboards; dashboard list is filtered by authorization |

## Change Flow

1. Author/edit the `PersesDashboard` YAML in `charts/observability-config/templates/`.
2. Commit to the pattern repository (reviewed, versioned).
3. Argo CD reconciles the resource; the Perses Operator syncs it into the project.
4. Verify in the console under `Observe > Dashboards (Perses)`.

## Acceptance Scenarios

- Given a dashboard is added solely via Git, when the pattern is reconciled, the dashboard appears in the console for authorized users (SC-005).
- Given a user has no binding, when they open the dashboard list, only dashboards they are authorized to view appear (SC-006).
- Given an invalid dashboard YAML, when applied, reconciliation reports an actionable error and does not break other dashboards (FR-014).