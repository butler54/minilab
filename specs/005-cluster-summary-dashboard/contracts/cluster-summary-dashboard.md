# Cluster Summary Dashboard Contract

## Namespace Label Contract

| Resource | Required state |
|----------|----------------|
| `openshift-storage` Namespace | Label `openshift.io/cluster-monitoring: "true"` |
| Existing `lvms-operator-metrics-monitor` ServiceMonitor | Selected by platform monitoring after label reconciliation |
| Platform Thanos Querier | Exposes the LVMS series used by the dashboard |

## Dashboard Contract

| Requirement | Contract |
|-------------|----------|
| Identity | One `PersesDashboard` managed in `charts/observability-config/templates/perses-dashboards.yaml` |
| Datasource | COO operator-managed platform datasource (`accelerators-thanos-querier-datasource`) in the COO project |
| Single-node context | Markdown/status panel plus ready-node/node-count signal |
| Health | Node readiness and cluster operator health/degradation panels |
| Capacity | CPU and memory utilization panels |
| LVMS | Volume-group total/available capacity and thin-pool data/metadata utilization panels from verified LVMS metric names |
| Failure behavior | LVMS panels display native no-data behavior when metric series are unavailable; dashboard resource still renders |

## Acceptance Queries

The target cluster verified the following LVMS `vg-manager` capacity series (all labeled `device_class="loopback"`, `node="sno"`):

- `topolvm_volumegroup_size_bytes`
- `topolvm_volumegroup_available_bytes`
- `topolvm_thinpool_data_percent`
- `topolvm_thinpool_metadata_percent`
- `topolvm_thinpool_size_bytes`
- `topolvm_thinpool_overprovisioned_available`

## Validation Contract

1. Render the dashboard and namespace label through Helm.
2. Confirm platform monitoring has selected `lvms-operator-metrics-monitor` and its targets are up.
3. Query platform Thanos for verified LVMS capacity series.
4. Confirm the dashboard appears and its LVMS panels return values rather than no-data.
