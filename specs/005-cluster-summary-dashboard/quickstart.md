# Quickstart: Validate Cluster Summary Dashboard

## Prerequisites

- Connected single-node OpenShift 4.22 cluster with LVMS and the observability feature installed.
- Platform Thanos Querier and COO Perses UIPlugin available.
- LVMS-generated `lvms-operator-metrics-monitor` ServiceMonitor exists in `openshift-storage`.

## Enable and Verify LVMS Metric Collection

1. Confirm the pattern renders the platform-monitoring label on `openshift-storage`:
   ```bash
   yq e '.clusterGroup.namespaces.openshift-storage.labels' values-prod.yaml
   ```
2. After reconciliation, confirm the namespace has the label:
   ```bash
   oc get namespace openshift-storage -o jsonpath='{.metadata.labels.openshift\.io/cluster-monitoring}'
   ```
   Expected: `true`.
3. Confirm the LVMS ServiceMonitor exists:
   ```bash
   oc get servicemonitor lvms-operator-metrics-monitor -n openshift-storage
   ```
4. Query platform Thanos for `topolvm_volumegroup_size_bytes`, `topolvm_volumegroup_available_bytes`, `topolvm_thinpool_data_percent`, and `topolvm_thinpool_metadata_percent`, filtering on `device_class="loopback"` and `node="sno"`.

## Dashboard Validation

1. Run `./pattern.sh make install` or let Argo CD reconcile the updated chart.
2. Open **Observe > Dashboards (Perses)** and select the single-node cluster summary dashboard.
3. Confirm it explicitly identifies the deployment as single-node.
4. Confirm node readiness, cluster-operator state, CPU/memory capacity, and LVMS volume-group/thin-pool utilization panels populate.
5. Induce or observe a degraded cluster operator and confirm the health signal reflects it.

## Regression Validation

```bash
tests/validate-pattern-config.sh
tests/test-cluster-summary-dashboard.sh
tests/test-observability-dashboards.sh
```

For the metric-source relationship and signal groups, see [data-model.md](data-model.md). For the dashboard and namespace-label contract, see [cluster-summary-dashboard.md](contracts/cluster-summary-dashboard.md).
