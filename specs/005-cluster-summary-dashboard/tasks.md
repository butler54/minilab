# Tasks: Cluster Summary Dashboard

**Input**: Design documents from `specs/005-cluster-summary-dashboard/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Render and target-cluster validation tasks are required by SC-002 through SC-006.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Pattern values and charts at repository root (`values-prod.yaml`, `charts/observability-config/`, `tests/`)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Enable the existing LVMS metric source through platform monitoring

- [X] T001 Add `openshift.io/cluster-monitoring: "true"` to the `openshift-storage` namespace labels in `values-prod.yaml`
- [X] T002 [P] Add a render assertion for the `openshift-storage` platform-monitoring label in `tests/test-cluster-summary-dashboard.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Verify the existing LVMS ServiceMonitor is collected by platform monitoring before building utilization panels

**⚠️ CRITICAL**: LVMS metric collection must be available before the dashboard can satisfy storage-utilization requirements

- [X] T003 Verify and record the target-cluster LVMS `vg-manager` metric names/labels exposed through platform Thanos in `specs/005-cluster-summary-dashboard/research.md`
- [X] T004 Add target-cluster validation steps for the `lvms-operator-metrics-monitor` ServiceMonitor and its healthy platform-monitoring scrape targets in `specs/005-cluster-summary-dashboard/quickstart.md`

**Checkpoint**: Platform Thanos exposes the verified LVMS volume-group/thin-pool metric series.

---

## Phase 3: User Story 1 - Single-Node Cluster Summary (Priority: P1) 🎯 MVP

**Goal**: Provide a Perses dashboard that explicitly identifies the SNO cluster and summarizes health/capacity.

**Independent Test**: Reconcile the chart and confirm the dashboard appears in Perses with single-node context, node readiness, operator status, CPU, and memory panels.

### Implementation for User Story 1

- [X] T005 [US1] Add the `single-node-cluster-summary` `PersesDashboard` resource with single-node context, node readiness, cluster-operator health, CPU, and memory panels in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T006 [US1] Configure all cluster summary health/capacity panels to query the existing platform Thanos global datasource in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T007 [US1] Add render assertions for the dashboard identity, single-node context, and platform datasource panels in `tests/test-cluster-summary-dashboard.sh`

**Checkpoint**: User Story 1 complete — the SNO dashboard appears with core cluster health/capacity signals.

---

## Phase 4: User Story 2 - LVMS Storage Utilization Coverage (Priority: P1)

**Goal**: Display actual LVMS volume-group and thin-pool utilization on the cluster summary dashboard.

**Independent Test**: With LVMS metrics scraped by platform monitoring, dashboard panels return verified volume-group available/total capacity and thin-pool data/metadata utilization values.

### Implementation for User Story 2

- [X] T008 [US2] Add LVMS volume-group total/available capacity panels using the verified target-cluster metric names in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T009 [US2] Add LVMS thin-pool data and metadata utilization panels using the verified target-cluster metric names in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T010 [US2] Add render assertions for the LVMS utilization panels and platform datasource queries in `tests/test-cluster-summary-dashboard.sh`
- [ ] T011 [US2] Verify on the target cluster that the dashboard panels return utilization values and show native no-data behavior only if the LVMS metric source is unavailable; record results in `specs/005-cluster-summary-dashboard/quickstart.md`

**Checkpoint**: User Stories 1 AND 2 complete — the dashboard reports real SNO cluster and LVMS utilization state.

---

## Phase 5: User Story 3 - Dashboard Managed as Code (Priority: P2)

**Goal**: Ensure the cluster summary dashboard is versioned and reconciled through the observability chart.

**Independent Test**: Change the dashboard definition in Git, reconcile, and confirm the change appears in Perses without a manual cluster-side edit.

### Implementation for User Story 3

- [X] T012 [US3] Add a reconciliation assertion for `single-node-cluster-summary` to `tests/test-cluster-summary-dashboard.sh`
- [X] T013 [US3] Document the chart-managed dashboard location and platform-monitoring LVMS dependency in `README.md`

**Checkpoint**: All user stories complete — dashboard and scrape enablement are GitOps-managed.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validate behavior end-to-end and document verified metric wiring

- [X] T014 [P] Run `tests/validate-pattern-config.sh`, `tests/test-observability-dashboards.sh`, and `tests/test-cluster-summary-dashboard.sh`
- [ ] T015 Run the full target-cluster quickstart in `specs/005-cluster-summary-dashboard/quickstart.md` and record the verified LVMS metric names/labels

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS LVMS dashboard panels
- **User Story 1 (Phase 3)**: Depends on Setup; core health panels can proceed before LVMS metric discovery
- **User Story 2 (Phase 4)**: Depends on Foundational and User Story 1
- **User Story 3 (Phase 5)**: Depends on the dashboard resource from User Story 1
- **Polish (Final Phase)**: Depends on all user stories

### Parallel Opportunities

- T001 and the initial chart-panel work can proceed independently, but T008/T009 wait for metric discovery (T003)
- T002 and T007 are separate test-file work only after their matching resources exist
- T013 documentation can proceed in parallel with T012

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Enable platform monitoring for `openshift-storage` (T001)
2. Add the single-node cluster summary health/capacity panels (T005-T007)
3. **STOP and VALIDATE**: Dashboard appears and identifies the SNO cluster
4. Add verified LVMS utilization panels after metrics are available (T003, T008-T011)

### Incremental Delivery

1. Platform-monitoring label + SNO summary dashboard
2. LVMS metrics verification + utilization panels
3. Chart reconciliation and documentation validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Metric names must be taken from the target cluster after platform monitoring begins scraping the existing LVMS ServiceMonitor; do not invent them from upstream TopoLVM documentation.
