# Research: Cluster Summary Dashboard

## Decision: Reuse the LVMS-provided ServiceMonitor through platform monitoring

**Rationale**: The target LVMS 4.22 deployment already creates `lvms-operator-metrics-monitor` in `openshift-storage`. It scrapes the authenticated HTTPS metrics endpoints on `lvms-operator-metrics-service` and `vg-manager-metrics-service`, using the service-account bearer token and serving-cert CA expected by platform monitoring. The namespace currently lacks `openshift.io/cluster-monitoring: "true"`, so platform monitoring does not discover this ServiceMonitor. Add that namespace label through `clusterGroup.namespaces.openshift-storage.labels`, then query the collected metrics through the existing Perses global platform Thanos datasource.

**Alternatives considered**:

- Add a new ServiceMonitor to the COO stack: rejected — the LVMS metrics endpoints require the authenticated bearer-token and serving-cert configuration already supplied by the LVMS ServiceMonitor; duplicating it adds RBAC/TLS complexity and a second scrape.
- Scrape the legacy `topolvm-node` endpoint directly: rejected — this LVMS 4.22 deployment has `lvms-operator` and `vg-manager`, not a `topolvm-node` workload exposing the legacy endpoint.
- Dashboard only with no-data LVMS panels: rejected by clarification — the user chose populated LVMS utilization panels.

## Decision: Query LVMS metrics via the platform Thanos datasource

**Rationale**: Existing cluster-state panels (node readiness and cluster operators) already use the platform Thanos datasource. Once platform monitoring scrapes the existing LVMS ServiceMonitor, the same datasource provides the LVMS series. This keeps the summary dashboard in one datasource context and avoids forwarding metrics into the COO stack.

**Alternatives considered**:

- Query the COO stack Prometheus: rejected — it is not configured with the authenticated LVMS ServiceMonitor and would duplicate collection.
- Add a separate LVMS datasource: rejected — one platform datasource is sufficient.

## Decision: LVMS utilization panels focus on volume-group and thin-pool capacity

**Rationale**: TopoLVM documents the capacity signals required for the dashboard: volume-group total and available bytes, plus thin-pool data and metadata usage percentages. The LVMS 4.22 `vg-manager` endpoint is the target source. Target-cluster inspection verified these exact series, all labeled with `device_class="loopback"` and `node="sno"`: `topolvm_volumegroup_size_bytes`, `topolvm_volumegroup_available_bytes`, `topolvm_thinpool_data_percent`, `topolvm_thinpool_metadata_percent`, `topolvm_thinpool_size_bytes`, and `topolvm_thinpool_overprovisioned_available`.

**Alternatives considered**:

- PVC filesystem metrics alone: rejected — they show consumer filesystem use but not LVMS disk/thin-pool pressure requested by the user.
- Host filesystem metrics: rejected — they do not represent LVMS capacity.

## Decision: Surface single-node context explicitly in the dashboard

**Rationale**: A Markdown/status panel identifies the lab as a single-node OpenShift deployment, and a node-count/ready-node panel makes the one-node condition observable. This prevents operators interpreting an unavailable second replica or reduced redundancy as a generic multi-node failure.

**Implementation Verification Required**

- After the `openshift.io/cluster-monitoring: "true"` namespace label is reconciled, confirm the platform Thanos Querier exposes the verified LVMS `vg-manager` capacity metrics.
- Confirm the platform monitoring ServiceMonitor is selected after the namespace label is added and its targets are `up`.
- Confirm the dashboard's platform Thanos datasource has RBAC access to these series for intended Perses viewers.
