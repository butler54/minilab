---

description: "Task list for Bootstrap Local Storage implementation"
---

# Tasks: Bootstrap Local Storage

**Input**: Design documents from `specs/001-bootstrap-local-storage/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), and [bootstrap-storage.md](contracts/bootstrap-storage.md)

**Tests**: The review requires concrete shell, YAML/render, dependency, and override-precedence tests before cluster validation.

**Organization**: Tasks are grouped by user story so each increment can be implemented and validated independently after its stated prerequisite state is available.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Repair the current pattern values and establish shared configuration paths used by bootstrap and GitOps resources.

- [X] T001 Repair the malformed `secretsStore` mapping and validate `values-global.yaml` parses as YAML in `values-global.yaml`
- [X] T002 Repair the malformed `sharedValueFiles` list and validate `values-prod.yaml` parses as YAML in `values-prod.yaml`
- [X] T003 Add global local-storage defaults for `storageProvider`, 100 GiB usable capacity, fixed loop identity, `lvms-loopback`, backing-size formula, and host reserve in `values-global.yaml`
- [X] T004 Create the planned bootstrap, Helm chart, override, and validation directories at `bootstrap/machineconfigs/`, `scripts/`, `charts/lvms-operator/`, `charts/lvms-operator-readiness/`, `charts/lvms-config/`, `overrides/`, and `tests/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish version-pinned LVMS, node, and clustergroup compatibility facts required by every implementation phase.

**CRITICAL**: No user-story implementation starts until selected OpenShift/LVMS values, generated storage-class identity, SNO node selectors, and application-wave support are confirmed.

- [ ] T005 Record the target OpenShift release, supported `lvms-operator` channel/start CSV, verified `lvms-loopback` generated storage-class name, and SNO node selectors in `specs/001-bootstrap-local-storage/research.md`
- [ ] T006 Verify rendered clustergroup support for provider-selected `sharedValueFiles`, per-application sync waves, and Argo CD hook annotations in `specs/001-bootstrap-local-storage/research.md`
- [X] T007 Create the YAML parsing and Helm-render validation harness in `tests/validate-pattern-config.sh`

**Checkpoint**: Platform-specific values and supported rendering mechanisms are known, pinned, and covered by executable validation.

---

## Phase 3: User Story 1 - Prepare Local Persistent Storage (Priority: P1) MVP

**Goal**: An operator can run the standard Make workflow to prepare configurable, persistent local dynamic-storage capacity without an unused physical disk.

**Independent Test**: On a supported SNO with sufficient root-filesystem capacity, run `./pattern.sh make bootstrap-storage`, rerun it, and verify a successful unit, the same exact loop mapping, and 100 GiB configured capacity without manual cleanup.

- [X] T008 [US1] Create the Git-tracked MachineConfig and loopback systemd unit that creates or reattaches the fixed persistent backing file before kubelet workloads in `bootstrap/machineconfigs/99-minilab-lvms-loopback.yaml.tpl`
- [X] T009 [US1] Implement configurable capacity validation, `ceil(capacityGiB / 0.85)` backing-size rounding to 4 GiB, 20 GiB host reserve, and unsafe existing-file rejection in `scripts/bootstrap-local-storage.sh`
- [X] T010 [US1] Implement fixed-loop-device conflict detection, idempotent MachineConfig application, and post-rollout verification of systemd success, backing allocation, and exact loop mapping in `scripts/bootstrap-local-storage.sh`
- [X] T011 [US1] Make `pattern-install` depend on `bootstrap-storage` so the prerequisite remains ordered with `make -j` in `Makefile`
- [X] T012 [US1] Add capacity formula, insufficient-space, conflicting-loop-device, systemd-status, and rerun-idempotence tests in `tests/test-bootstrap-local-storage.sh`
- [X] T013 [US1] Document capacity configuration, backing-size formula, host reserve, rerun behavior, and recovery rules in `README.md`

**Checkpoint**: The bootstrap proves only host-side readiness and stops the installation workflow on invalid or unsafe host state; it does not claim LVMS or StorageClass readiness.

---

## Phase 4: User Story 2 - Install Storage Before Vault (Priority: P1)

**Goal**: After User Story 1 establishes the loop device, GitOps installs LVMS and makes its generated storage class ready before Vault can reconcile.

**Independent Test**: With a successful storage bootstrap, install the pattern and confirm the LVMS subscription CSV, controller, LVMCluster CRD, LVMCluster, storage class, and CSI components become ready before Vault enters its sync wave.

- [X] T014 [P] [US2] Create the version-pinned LVMS operator Helm chart for the `openshift-storage` namespace, OperatorGroup, and Subscription in `charts/lvms-operator/Chart.yaml`, `charts/lvms-operator/values.yaml`, and `charts/lvms-operator/templates/operator.yaml`
- [X] T015 [P] [US2] Create the operator-readiness Helm chart metadata and values stubs in `charts/lvms-operator-readiness/Chart.yaml` and `charts/lvms-operator-readiness/values.yaml`
- [X] T016 [P] [US2] Create the LVMS configuration Helm chart metadata and values stubs in `charts/lvms-config/Chart.yaml` and `charts/lvms-config/values.yaml`
- [X] T017 [US2] Add an operator-readiness ServiceAccount, Role, and RoleBinding with read-only access to Subscription, CSV, CRD, and controller status in `charts/lvms-operator-readiness/templates/readiness-rbac.yaml`
- [X] T018 [US2] Add an Argo CD Sync hook that blocks configuration until the LVMS CSV is succeeded, controller is available, and LVMCluster CRD exists in `charts/lvms-operator-readiness/templates/readiness-job.yaml`
- [X] T019 [US2] Add an explicit loop-device LVMCluster with SNO selector/toleration, a thin pool sufficient for configured usable capacity, `WaitForFirstConsumer`, `Retain`, and no overprovisioning in `charts/lvms-config/templates/lvmcluster.yaml`
- [X] T020 [US2] Add the least-privilege readiness ServiceAccount, Role, and RoleBinding for LVMCluster, storage-class, and CSI workload reads in `charts/lvms-config/templates/readiness-rbac.yaml`
- [X] T021 [US2] Add an Argo CD Sync hook that blocks until the LVMCluster, verified storage class, and CSI components are ready in `charts/lvms-config/templates/readiness-job.yaml`
- [X] T022 [US2] Register LVMS operator, operator-readiness, LVMS configuration, and Vault applications at sync waves `-20`, `-15`, `-10`, and `+10` in `values-prod.yaml`
- [X] T023 [US2] Add render and ordering assertions for the LVMS subscription, operator-readiness hook, LVMCluster, and Vault wave in `tests/test-lvms-ordering.sh`

**Checkpoint**: `make install`, not `bootstrap-storage`, verifies the StorageClass readiness boundary and prevents Vault from progressing when LVMS is unavailable.

---

## Phase 5: User Story 3 - Use Local Storage for Vault (Priority: P2)

**Goal**: Vault selects the generated local storage class by default through the provider-selected override mechanism, while a later explicit storage selection remains authoritative.

**Independent Test**: Render LVM provider values with no later override and verify `vault.server.dataStorage.storageClass` is `lvms-loopback`; render a later explicit value and verify that it wins.

- [X] T024 [US3] Create the provider-specific Vault override with `vault.server.dataStorage.storageClass: lvms-loopback` in `overrides/values-storage-lvm.yaml`
- [X] T025 [US3] Attach the provider-specific override through `clusterGroup.sharedValueFiles` after base values and document the later-value override precedence in `values-prod.yaml`
- [X] T026 [US3] Add default-class and later-explicit-override rendering assertions in `tests/test-vault-storage-override.sh`
- [X] T027 [US3] Document the provider-selected Vault class, shared-storage scope, and supported override precedence in `README.md`

**Checkpoint**: Vault receives `lvms-loopback` by default without changing the Kubernetes-wide default StorageClass.

---

## Phase 6: Polish and Cross-Cutting Validation

**Purpose**: Verify completed configuration, capacity boundaries, and operational recovery against the documented workflow.

- [X] T028 [P] Run the scripted YAML, Helm-render, bootstrap, ordering, and Vault-override tests in `tests/validate-pattern-config.sh`, `tests/test-bootstrap-local-storage.sh`, `tests/test-lvms-ordering.sh`, and `tests/test-vault-storage-override.sh`
- [ ] T029 Execute post-install LVMS readiness, Vault binding, a 5 GiB PVC write/read, retained-volume cleanup, and pod-restart validation in `specs/001-bootstrap-local-storage/quickstart.md`
- [ ] T030 Execute node-restart, 100 GiB capacity-boundary, and 101 GiB rejection scenarios in `specs/001-bootstrap-local-storage/quickstart.md`
- [ ] T031 Record target-cluster results, retained-volume cleanup procedure, and version-specific deviations in `specs/001-bootstrap-local-storage/quickstart.md`

---

## Dependencies and Execution Order

1. Complete T001-T007 before user-story work.
2. Complete T008-T013 to deliver the bootstrap MVP.
3. Complete T014-T023 after the bootstrap has a stable loop-device contract.
4. Complete T024-T027 after T006 and T022 establish the provider override path.
5. Complete T028-T031 after all desired user stories.

### User Story Dependencies

- **US1**: Depends on T001-T007; independently delivers verified host-side local-capacity preparation.
- **US2**: Depends on US1 because LVMS consumes the loop device established by the bootstrap.
- **US3**: Depends on US2 because it selects the storage class generated by LVMS.

### Parallel Opportunities

- T001 and T002 can run in parallel; T003 follows their corrected YAML structure.
- T005 and T006 can run in parallel once target-cluster access is available.
- T014-T016 can run in parallel.
- T017 and T019 can run in parallel after their respective chart scaffolds exist.
- T024 and T027 can run in parallel; T025 and T026 follow the selected shared-value path.
- T028 can run after its test files exist; T029-T031 remain sequential target-cluster validation tasks.

## Parallel Example: User Story 2

```text
Task: "Create the LVMS operator chart in charts/lvms-operator/"
Task: "Create the operator-readiness chart in charts/lvms-operator-readiness/"
Task: "Create the LVMS configuration chart metadata in charts/lvms-config/"
```

## Implementation Strategy

### MVP First

1. Complete baseline repair and platform-specific verification.
2. Implement User Story 1 through T013.
3. Run the bootstrap test suite and the independent host-readiness validation.
4. Stop if the bootstrap does not prove the successful unit state and exact loop mapping.

### Incremental Delivery

1. Add US2 after bootstrap is proven; verify the operator/CRD gate before applying LVMCluster and then verify post-install storage readiness before Vault.
2. Add US3 after the storage-class identity and provider-selected shared-value path are proven; render both default and later override precedence.
3. Finish with the complete quickstart capacity, recovery, and retained-volume cleanup matrix.

## Notes

- Every task uses the required checklist format: checkbox, sequential ID, optional parallel marker, story label for story work, and exact path.
- The plan intentionally does not make `lvms-loopback` the Kubernetes-wide default StorageClass.
- The loopback-backed design is limited to the SNO lab and is not a node-loss-resilient storage solution.

## Phase 7: Convergence

- [X] T032 Forward `LOCAL_STORAGE_CAPACITY_GIB` through the utility-container environment and add an invocation-level forwarding test in `pattern.sh` and `tests/test-pattern-wrapper.sh` per FR-004 (contradicts)
- [X] T033 Make the LVMS Subscription converge to its pinned CSV without manual cluster mutation by selecting and validating an approved InstallPlan strategy in `values-prod.yaml`, `charts/lvms-operator/`, and `tests/test-lvms-ordering.sh` per FR-007 (contradicts)
- [X] T034 Consolidate the OpenShift/LVMS channel, starting CSV, readiness CSV, and CLI image into one validated release compatibility configuration in `values-global.yaml`, `charts/lvms-operator/`, `charts/lvms-operator-readiness/`, and `tests/test-lvms-ordering.sh` per plan: LVMS compatibility (contradicts)
- [X] T035 Fix empty-PKI-array handling under `set -u` and add a remote-Podman/no-host-PKI wrapper smoke test in `pattern.sh` and `tests/test-pattern-wrapper.sh` per Constitution Development Workflow (partial)
- [X] T036 Replace the repository-local LVMS Namespace, OperatorGroup, and Subscription chart with `clusterGroup.namespaces` and `clusterGroup.subscriptions` declarations; remove redundant chart ownership and validate rendered output in `values-prod.yaml`, `charts/lvms-operator/`, and `tests/test-lvms-ordering.sh` per Constitution I, III, and IV (unrequested)
- [ ] T037 Verify the target-generated StorageClass for the `loopback` device class and record or correct its identity consistently in `charts/lvms-config/templates/lvmcluster.yaml`, `values-global.yaml`, `overrides/values-storage-lvm.yaml`, and `specs/001-bootstrap-local-storage/research.md` per FR-008 (partial)
- [X] T038 Evaluate Argo Sync hooks against the Validated Patterns imperative framework for both readiness gates; retain the least-complex synchronous mechanism that blocks initial Vault reconciliation and remove redundant Job/RBAC resources in `charts/lvms-operator-readiness/`, `charts/lvms-config/`, `values-prod.yaml`, and `specs/001-bootstrap-local-storage/research.md` per Constitution II and IV (unrequested)

## Phase 8: Convergence

- [X] T039 [US1] Validate `LOCAL_STORAGE_CAPACITY_GIB` before arithmetic and preflight the existing backing-file size/allocation and fixed loop-device mapping on the target node before rendering or applying the MachineConfig; reject malformed capacity, an incompatible file, or an occupied loop device without an MCO rollout, and add mocked `oc` tests in `scripts/bootstrap-local-storage.sh` and `tests/test-bootstrap-local-storage.sh` per FR-003, FR-005, and FR-006 (partial)
- [X] T040 Reconcile the obsolete LVMS application topology and sync-order contract in `specs/001-bootstrap-local-storage/contracts/bootstrap-storage.md` and `specs/001-bootstrap-local-storage/plan.md` with implemented `clusterGroup` namespace/subscription ownership and the single `lvms-config` Sync hook at wave `-10` before Vault at `+10`; state only readiness guarantees verified by T006 per FR-007, FR-011, and Constitution II and IV (partial)

## Phase 9: Convergence

- [X] T041 Reject an existing backing file that is already attached to any loop device other than the configured fixed loop device before applying the MachineConfig, and add a mocked preflight regression test in `scripts/bootstrap-local-storage.sh` and `tests/test-bootstrap-local-storage.sh` per FR-003 and the plan's single stable loop-device constraint
