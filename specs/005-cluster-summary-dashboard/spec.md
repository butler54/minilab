# Feature Specification: Cluster Summary Dashboard

**Feature Branch**: `005-cluster-summary-dashboard`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "Create a sample perses dashboard that summarizes the state of the openshift cluster noting it's single node. Be sure to cover off the LVMS storage disks utilisation."

## Clarifications

### Session 2026-09-21

- Q: Should this feature add the LVMS metric scraping needed to actually populate the storage-utilization panels, or only add the dashboard and accept a no-data state when those metrics aren't collected? -> A: Add LVMS/topolvm metric scraping (ServiceMonitor) so utilization panels are populated.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Single-Node Cluster Summary (Priority: P1)

As a pattern operator, I can open a single Perses dashboard that summarizes the overall state of the OpenShift cluster and makes it explicit that the cluster is a single-node deployment, so I can assess cluster health at a glance.

**Why this priority**: The core request is a summary view of the cluster; without the single-node context the summary could be misleading.

**Independent Test**: Deploy the pattern with dashboarding enabled and confirm a dashboard appears that reports overall cluster state and identifies the deployment as single-node.

**Acceptance Scenarios**:

1. **Given** the pattern is installed with dashboarding enabled, **When** an operator opens the cluster summary dashboard, **Then** it shows the deployment is a single-node cluster.
2. **Given** the cluster summary dashboard, **When** an operator views it, **Then** it reports overall cluster state (for example, node readiness, cluster operators, capacity).

---

### User Story 2 - LVMS Storage Utilization Coverage (Priority: P1)

As a pattern operator, I can see LVMS storage disk utilization on the cluster summary dashboard so that I can spot storage capacity pressure before it becomes a problem.

**Why this priority**: LVMS disk utilization is explicitly required by the request and is a key operational concern on a single-node lab with finite local storage.

**Independent Test**: Open the cluster summary dashboard and confirm it shows LVMS storage utilization, including disk/capacity usage.

**Acceptance Scenarios**:

1. **Given** the cluster summary dashboard, **When** an operator views the storage section, **Then** it reports LVMS disk utilization.
2. **Given** LVMS storage is in use, **When** an operator views the dashboard, **Then** the displayed utilization reflects the actual storage consumption.

---

### User Story 3 - Dashboard Managed as Code (Priority: P2)

As a pattern operator, I can have the cluster summary dashboard managed as code in the pattern repository so that it is versioned, reviewed, and reconciled like every other dashboard.

**Why this priority**: The pattern constitution requires all dashboards to be managed as code and GitOps-reconciled.

**Independent Test**: Add the cluster summary dashboard through the chart, reconcile, and confirm it appears without manual cluster-side action.

**Acceptance Scenarios**:

1. **Given** the dashboard is declared in the chart, **When** the pattern is reconciled, **Then** the dashboard appears in the dashboarding access point.
2. **Given** the dashboard exists, **When** it is changed in the chart and reconciled, **Then** the change is reflected.

---

### Edge Cases

- LVMS metrics are not yet scraped by the dashboarding datasource; the dashboard must show a clear no-data state rather than failing, while the scraping addition (FR-005a) is the primary mechanism to avoid this state.
- The single-node cluster has one node; dashboards must not imply multiple nodes where only one exists.
- Storage capacity is near or at full; the dashboard must surface the high utilization clearly.
- The dashboard references metrics that differ between the platform monitoring and the observability stack; the datasource wiring must resolve correctly.
- Cluster operators are degraded; the summary must reflect this rather than showing a falsely healthy state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pattern MUST provide a Perses dashboard that summarizes the overall state of the OpenShift cluster.
- **FR-002**: The dashboard MUST make explicit that the deployment is a single-node cluster.
- **FR-003**: The dashboard MUST report cluster health signals, including node readiness and cluster operator status.
- **FR-004**: The dashboard MUST report cluster capacity signals, including node capacity and utilization.
- **FR-005**: The dashboard MUST report LVMS storage disk utilization.
- **FR-005a**: The pattern MUST enable scraping of LVMS/topolvm metrics so that the storage-utilization panels are populated, not empty.
- **FR-006**: The dashboard MUST be managed as code in the pattern's observability chart and reconciled by the pattern's GitOps mechanism.
- **FR-007**: If the underlying metrics (for example, LVMS metrics) are not available to the dashboard's datasource, the dashboard MUST present a clear no-data state rather than failing to render.
- **FR-008**: The dashboard MUST reflect degraded cluster state (for example, a not-ready node or degraded cluster operator) rather than showing a falsely healthy summary.

### Key Entities

- **Cluster summary dashboard**: The Perses dashboard presenting overall cluster state, single-node context, capacity, and LVMS storage utilization.
- **Cluster health signals**: Node readiness and cluster operator status metrics shown on the dashboard.
- **LVMS storage utilization**: The disk and capacity usage of the LVMS-backed storage presented on the dashboard.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a supported single-node cluster, the cluster summary dashboard is reachable from the dashboarding access point and clearly identifies the deployment as single-node.
- **SC-002**: In 100% of validation runs, the dashboard displays node readiness and cluster operator status.
- **SC-003**: In 100% of validation runs, the dashboard displays LVMS storage disk utilization that reflects actual storage consumption.
- **SC-004**: In 100% of validation runs, the dashboard is reconciled through the chart without manual cluster-side action.
- **SC-005**: In 100% of validation runs where underlying metrics are unavailable despite the scraping addition, the dashboard renders a no-data state instead of failing.
- **SC-006**: In 100% of validation runs where a cluster operator is degraded, the dashboard reflects the degraded state.

## Assumptions

- The cluster summary dashboard is added alongside the existing domain dashboards in the observability chart and surfaced under the same Perses access point.
- Cluster health signals (node readiness, cluster operators) are available from the platform Thanos Querier datasource, consistent with the existing system-overview dashboard.
- LVMS storage utilization is collected by adding a ServiceMonitor that scrapes the LVMS/topolvm metrics endpoint into the observability stack's Prometheus; the exact metric names are resolved during planning and verified on the target cluster.
- The dashboard is a single PersesDashboard resource managed as code; no interactive console-authoring is required.
- The single-node context is conveyed through the dashboard's display metadata and panel content, not through a separate mechanism.
