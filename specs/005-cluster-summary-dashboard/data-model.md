# Data Model: Cluster Summary Dashboard

## Cluster Summary Dashboard

| Field | Meaning | Validation |
|-------|---------|------------|
| `name` | Stable Kubernetes/Perses dashboard identity | DNS-1123; unique in `minilab-observability` |
| `title` | Operator-facing dashboard title | Identifies it as single-node cluster summary |
| `datasource` | COO platform Thanos datasource | Existing `accelerators-thanos-querier-datasource` in the COO project |
| `singleNodeContext` | Explicit deployment context | Markdown/status content and one-node panel |
| `panels` | Health, capacity, and LVMS utilization visualizations | Queries resolve through platform Thanos |

**Lifecycle**: Declared in Git -> Argo CD applies `PersesDashboard` -> Perses Operator synchronizes it -> visible under `Observe > Dashboards (Perses)`.

## Platform Monitoring Enablement

| Field | Meaning | Validation |
|-------|---------|------------|
| `openshift-storage` namespace label | Enables platform monitoring discovery of LVMS ServiceMonitors | `openshift.io/cluster-monitoring: "true"` |
| `lvms-operator-metrics-monitor` | LVMS-created authenticated ServiceMonitor | Platform monitoring selects it after label reconciliation |
| LVMS metric series | Volume-group/thin-pool utilization series from `vg-manager` | Available through platform Thanos |

**Relationship**: The namespace label enables the existing ServiceMonitor; no second ServiceMonitor is created. COO's operator-managed platform datasource supplies both platform-health and LVMS-capacity series to the dashboard.

## Dashboard Signal Groups

| Signal group | Purpose |
|--------------|---------|
| Single-node identity | Makes the SNO deployment context explicit and reports node count/readiness |
| Cluster health | Node readiness and cluster-operator availability/degradation |
| Cluster capacity | CPU and memory utilization on the only node |
| LVMS capacity | `topolvm_volumegroup_available_bytes` / `topolvm_volumegroup_size_bytes` plus `topolvm_thinpool_data_percent` / `topolvm_thinpool_metadata_percent` |

**No-data state**: If LVMS metrics are temporarily absent, Perses displays the panel's native no-data behavior while the cluster-health panels continue to render.
