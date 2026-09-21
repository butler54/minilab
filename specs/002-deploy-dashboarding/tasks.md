# Tasks: Deploy Dashboarding Tools

**Input**: Design documents from `specs/002-deploy-dashboarding/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: The repository has an established shell/Helm validation convention (`tests/validate-pattern-config.sh` and per-feature shell tests). Test tasks are included to match the repository gates described in plan.md; they are not TDD tasks.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Pattern values and charts at repository root (`values-global.yaml`, `values-prod.yaml`, `charts/`, `overrides/`, `tests/`)
- Observability configuration chart: `charts/observability-config/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create `charts/observability-config/` Helm chart scaffold (`Chart.yaml`, `.helmignore`, empty `values.yaml`, `templates/`) per plan.md structure
- [X] T002 Add `global.observability` configuration block (enabled, stackNamespace, retention, storageClass, externalTargets) with stubs to `values-global.yaml`
- [X] T003 Add COO namespace, COO subscription, and `observability-config` application entries to `values-prod.yaml` per contracts/observability-config.md
- [X] T004 [P] Add PagerDuty routing-key secret definition (`pagerduty-routing-key`) to `values-secret.yaml.template` (no real secret material)
- [X] T005 [P] Add `charts/observability-config` to the render/lint loop in `tests/validate-pattern-config.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 Create `charts/observability-config/values.yaml` with stubs for all `.Values.global.*` and `.Values.clusterGroup.*` references so `helm template` works standalone
- [X] T007 [P] Create monitoring `UIPlugin` template (`apiVersion: monitoring.rhobs/v1alpha2`, `spec.type: monitoring`, `spec.monitoring.perses.enabled: true`) in `charts/observability-config/templates/uiplugin.yaml`
- [X] T008 [P] Create `MonitoringStack` template (Prometheus single replica, Thanos, Alertmanager enabled, retention 30d, storage class `lvms-loopback`, resource/namespace selectors) in `charts/observability-config/templates/monitoring-stack.yaml`
- [X] T009 [P] Create the PagerDuty `ExternalSecret` template referencing the vault key in `charts/observability-config/templates/external-secret.yaml`
- [X] T010 Create a README/summary of the observability configuration surface in `charts/observability-config/README.md`

**Checkpoint**: COO and the observability stack are installable; dashboards, alerts, and access control can now be layered on.

---

## Phase 3: User Story 1 - Unified Dashboarding for All Workload Domains (Priority: P1) 🎯 MVP

**Goal**: Deploy Perses via COO and provide populated dashboards for OpenShift system workloads, application workloads, and external components through one console access point.

**Independent Test**: Deploy the pattern with dashboarding enabled and confirm each of the three domains has at least one populated dashboard reachable from the OpenShift console `Observe > Dashboards (Perses)`.

### Implementation for User Story 1

- [X] T011 [P] [US1] Create `PersesGlobalDatasource` (or `PersesDatasource`) pointing at the in-cluster Thanos Querier for system/application metrics in `charts/observability-config/templates/perses-datasources.yaml`
- [X] T012 [P] [US1] Create `PersesDatasource` pointing at the COO stack Prometheus/Thanos for external metrics in `charts/observability-config/templates/perses-datasources.yaml`
- [X] T013 [P] [US1] Create `ScrapeConfig`/`ServiceMonitor` templates for external HTTP/HTTPS exporter targets driven by `global.observability.externalTargets` in `charts/observability-config/templates/scrape-configs.yaml`
- [X] T014 [US1] Create the OCP system workload `PersesDashboard` (cluster, nodes, capacity panels; platform Thanos datasource) in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T015 [US1] Create the application workload `PersesDashboard` (namespaces/workloads panels; user-workload or stack datasource) in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T016 [US1] Create the external components `PersesDashboard` (external exporter panels; stack datasource) in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T017 [US1] Add a shell test asserting the three `PersesDashboard` resources render with expected names, namespaces, and datasource references in `tests/test-observability-dashboards.sh`
- [X] T018 [US1] Add a shell test asserting the monitoring `UIPlugin` renders with Perses enabled in `tests/test-observability-dashboards.sh`

**Checkpoint**: At this point, User Story 1 should be fully functional — all three domains have dashboards visible in the console.

---

## Phase 4: User Story 2 - Alerting Across All Workload Domains (Priority: P1)

**Goal**: Deliver alerts for OpenShift system workloads, application workloads, and external components to PagerDuty based on configurable thresholds.

**Independent Test**: Configure a threshold on one metric per domain, drive the metric over the threshold, and confirm an alert fires, resolves when the condition clears, and is delivered to the PagerDuty service.

### Implementation for User Story 2

- [X] T019 [P] [US2] Create the Alertmanager configuration template with a single PagerDuty receiver (routing key from the vault-backed secret, `sendResolved: true`) and default route in `charts/observability-config/templates/alertmanager-config.yaml`
- [X] T020 [P] [US2] Create `PrometheusRule` template for OCP system workload alert thresholds (selected by the stack resourceSelector) in `charts/observability-config/templates/prometheus-rules.yaml`
- [X] T021 [P] [US2] Create `PrometheusRule` template for application workload alert thresholds in `charts/observability-config/templates/prometheus-rules.yaml`
- [X] T022 [P] [US2] Create `PrometheusRule` template for external component alert thresholds in `charts/observability-config/templates/prometheus-rules.yaml`
- [X] T023 [US2] Add grouping and critical-warning inhibition to the Alertmanager config to prevent alert floods in `charts/observability-config/templates/alertmanager-config.yaml`
- [X] T024 [US2] Add a shell test asserting the Alertmanager config renders a PagerDuty receiver and default route in `tests/test-observability-alerts.sh`
- [X] T025 [US2] Add a shell test asserting one `PrometheusRule` per domain renders and is selected by the stack resourceSelector in `tests/test-observability-alerts.sh`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work — alerts fire per domain and are delivered to PagerDuty.

---

## Phase 5: User Story 3 - Configurable Dashboards and Alerts (Priority: P2)

**Goal**: Allow operators to add data sources, dashboards, and alert rules through pattern configuration so the environment stays GitOps-declared.

**Independent Test**: Add a new data source and a new dashboard definition through the pattern values, apply the change, and confirm the new dashboard appears without any manual cluster-side action.

### Implementation for User Story 3

- [X] T026 [P] [US3] Parameterize external exporter `externalTargets` so new targets produce a new `ScrapeConfig` entry without chart edits in `charts/observability-config/templates/scrape-configs.yaml`
- [X] T027 [P] [US3] Parameterize additional `PersesDashboard` definitions via a values-driven list (`global.observability.dashboards`) in `charts/observability-config/templates/perses-dashboards.yaml`
- [X] T028 [US3] Parameterize additional `PrometheusRule` definitions via a values-driven list (`global.observability.alertRules`) in `charts/observability-config/templates/prometheus-rules.yaml`
- [X] T029 [US3] Add validation that an invalid datasource/dashboard/alert-rule declaration produces an actionable error without breaking reconciliation of existing resources in `charts/observability-config/values.yaml` and templates
- [X] T030 [US3] Add a shell test asserting a values-added dashboard renders and appears in the dashboard list in `tests/test-observability-configurability.sh`

**Checkpoint**: User Stories 1-3 work — configuration-driven additions reconcile through Git.

---

## Phase 6: User Story 4 - Controlled Access to Dashboards and Alerts (Priority: P2)

**Goal**: Control who can view dashboards and manage alerts through OpenShift-backed identities using Perses RBAC roles.

**Independent Test**: Configure restricted access, then verify that an unauthenticated or unauthorized user cannot reach the dashboards or alter alert configuration.

### Implementation for User Story 4

- [X] T031 [P] [US4] Create `RoleBinding`/`ClusterRoleBinding` templates granting Perses viewer roles (`persesdashboard-viewer-role`, `persesdatasource-viewer-role`) to the configured lab viewer group in `charts/observability-config/templates/rbac.yaml`
- [X] T032 [P] [US4] Create `RoleBinding`/`ClusterRoleBinding` templates granting Perses editor roles (`persesdashboard-editor-role`, `persesdatasource-editor-role`, `persesglobaldatasource-*-role`) to the configured admin group in `charts/observability-config/templates/rbac.yaml`
- [X] T033 [US4] Parameterize viewer/editor group names via `global.observability.rbac` values in `charts/observability-config/values.yaml`
- [X] T034 [US4] Add a shell test asserting viewer and editor bindings render against the configured groups in `tests/test-observability-rbac.sh`

**Checkpoint**: All user stories are independently functional and access-controlled.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [X] T035 [P] Document the dashboarding scope, configuration surface, external-target declaration, alerting configuration, access control, and verification steps in `README.md` (or a feature quickstart reference)
- [X] T036 [P] Wire the observability chart into the repository validation gates (`make validate-schema`, `make validate-cluster`, `make argo-healthcheck`) in `Makefile`
- [X] T037 Run `specs/002-deploy-dashboarding/quickstart.md` end-to-end validation and record target-cluster results (COO channel/CSV, CRD versions, datasource URLs, Perses project mapping)
- [X] T038 Review the implementation against the constitution (GitOps-First, no committed secrets, Helm-only, simplicity) and update `specs/002-deploy-dashboarding/plan.md` Complexity Tracking if any deviation is needed

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (US1 → US2 → US3 → US4)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - Uses the same stack; independently testable
- **User Story 3 (P2)**: Can start after Foundational (Phase 2) - Parameterizes US1/US2 resources; independently testable
- **User Story 4 (P2)**: Can start after Foundational (Phase 2) - Applies RBAC to Perses resources; independently testable

### Within Each User Story

- Templates before tests
- Datasources before dashboards (within US1)
- Alertmanager receiver before alert rules (within US2)
- Story complete before moving to next priority

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel (within Phase 1)
- All Foundational tasks marked [P] can run in parallel (within Phase 2)
- Once Foundational phase completes, all user stories can start in parallel (if team capacity allows)
- US1 datasources/scrape-configs (T011-T013) marked [P] can run in parallel
- US2 receiver/rules (T019-T022) marked [P] can run in parallel
- US4 viewer/editor bindings (T031-T032) marked [P] can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch datasources and scrape configs together:
Task: "Create PersesGlobalDatasource pointing at Thanos Querier in charts/observability-config/templates/perses-datasources.yaml"
Task: "Create PersesDatasource pointing at the COO stack Prometheus in charts/observability-config/templates/perses-datasources.yaml"
Task: "Create ScrapeConfig/ServiceMonitor templates in charts/observability-config/templates/scrape-configs.yaml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Add User Story 4 → Test independently → Deploy/Demo

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together
2. Once Foundational is done:
   - Developer A: User Story 1
   - Developer B: User Story 2
   - Developer C: User Story 3 (after 1/2 parameterization points exist)
   - Developer D: User Story 4

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Avoid: vague tasks, same file conflicts, cross-story dependencies that break independence
- Verify exact COO channel/CSV and CRD API versions on the target OpenShift 4.22 cluster before applying (see research.md "Implementation Verification Required")
---

## Phase 8: Convergence

**Purpose**: Close gaps between the feature artifacts and the implemented code identified by `/speckit.converge`.

- [X] T039 Move `resourceSelector` out of `spec.prometheusConfig` to top-level `spec.resourceSelector` in `charts/observability-config/templates/monitoring-stack.yaml` so the stack selects the `PrometheusRule` and `ScrapeConfig` resources per FR-007/FR-008/data-model (contradicts)
- [X] T040 Verify and correct the `prometheusConfig.persistentVolumeClaim` field shape (storage size request) against the COO `MonitoringStack` API in `charts/observability-config/templates/monitoring-stack.yaml` so 30-day metrics persistence is actually provisioned per FR-011a (partial)
- [X] T041 Verify that the COO-generated Alertmanager selects the `AlertmanagerConfig` (or switch to the operator-native config secret) so alert notifications reach PagerDuty per FR-009 in `charts/observability-config/templates/alertmanager-config.yaml` (partial)
