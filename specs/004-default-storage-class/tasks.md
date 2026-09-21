# Tasks: Default Storage Class

**Input**: Design documents from `specs/004-default-storage-class/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Default-class establishment, idempotence, and explicit-choice preservation (SC-001 to SC-005) are validation gates; test tasks are included to match the repository's shell-test convention.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Pattern chart and values at repository root (`charts/lvms-config/`, `values-global.yaml`, `tests/`)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the config surface for the default-storage mechanism

- [X] T001 Add `global.localStorage.defaultStorageClass` values block (enabled default `true`, schedule default every 10 minutes) to `values-global.yaml`
- [X] T002 Add matching `defaultStorageClass` value stubs to `charts/lvms-config/values.yaml` so `helm template` works standalone

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the least-privilege identity the scheduled Job runs under

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Create the ServiceAccount, Role (get/list/watch/patch StorageClasses), and RoleBinding templates for the default-storage Job in `charts/lvms-config/templates/default-storage-rbac.yaml`, tolerating the control-plane NoSchedule taint
- [X] T004 [P] Add the RBAC names to `charts/lvms-config/values.yaml` for render-time consistency

**Checkpoint**: The Job identity exists with minimal StorageClass permissions.

---

## Phase 3: User Story 1 - Ensure an LVMS-Based Default Storage Class Exists (Priority: P1) 🎯 MVP

**Goal**: A scheduled Job establishes `lvms-loopback` as the cluster default when no default exists, so implicit claims (e.g. Perses) can bind.

**Independent Test**: On a cluster with no default class, the Job annotates `lvms-loopback` with `is-default-class: "true"`, and an implicit PVC binds through it.

### Implementation for User Story 1

- [X] T005 [US1] Create the `CronJob` template in `charts/lvms-config/templates/default-storage-job.yaml` using `global.lvmsCompatibility.cliImage`, gated by `global.localStorage.defaultStorageClass.enabled`, targeting `global.localStorage.storageClassName`
- [X] T006 [US1] Implement the Job's idempotent logic: list StorageClasses, if none is default and the target class exists and is not already default, annotate it with `storageclass.kubernetes.io/is-default-class: "true"` in `charts/lvms-config/templates/default-storage-job.yaml`
- [X] T007 [US1] Add a shell test asserting the CronJob renders with the target class, image, and RBAC reference in `tests/test-default-storage-class.sh`

**Checkpoint**: User Story 1 complete — the Job establishes the default when none exists.

---

## Phase 4: User Story 2 - Default Storage Class is Established via a Declared Mechanism (Priority: P1)

**Goal**: The mechanism is Git-declared, idempotent, and restores the default if removed.

**Independent Test**: Rerun the Job; confirm the default annotation is unchanged, no duplicate default exists, and a removed annotation is restored on the next run.

### Implementation for User Story 2

- [X] T008 [US2] Add idempotence and drift-recovery assertions to `tests/test-default-storage-class.sh` (rerun no-op; removed annotation restored)
- [X] T009 [US2] Add a foreign-default assertion to `tests/test-default-storage-class.sh`: when another class is already default, the Job does not alter it

**Checkpoint**: User Stories 1 AND 2 work — the mechanism is idempotent and declarative.

---

## Phase 5: User Story 3 - Non-Default Workloads Remain Unaffected (Priority: P2)

**Goal**: Explicit storage-class choices still win; the default only affects implicit requests.

**Independent Test**: A claim naming an explicit supported class binds to it, while an implicit claim binds to `lvms-loopback`.

### Implementation for User Story 3

- [X] T010 [US3] Add an explicit-choice assertion to `tests/test-default-storage-class.sh` (explicit class wins over the default)
- [X] T011 [US3] Add an implicit-binding assertion to `tests/test-default-storage-class.sh` (no class binds to `lvms-loopback`)

**Checkpoint**: All user stories complete — explicit choices preserved, implicit requests use the default.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation and validation wiring

- [X] T012 [P] Document the default-storage mechanism (invocation, idempotence, verification) in `README.md`
- [X] T013 Run the full validation set (`tests/validate-pattern-config.sh`, `tests/test-default-storage-class.sh`, and the existing lvms tests) and confirm all pass

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
- **Polish (Final Phase)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - no dependencies on other stories
- **User Story 2 (P1)**: Depends on US1 (the Job must exist before idempotence/drift tests are meaningful); independently testable once US1 done
- **User Story 3 (P2)**: Depends on US1 (implicit binding requires the default established); independently testable once US1 done

### Within Each User Story

- RBAC before Job before tests
- Idempotence assertions after the Job exists
- Explicit-choice assertions after implicit-binding assertions

### Parallel Opportunities

- T003 and T004 (Foundational RBAC) can run in parallel
- T012 (documentation) can run in parallel with the story phases once the Job exists

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (values) + Phase 2 (RBAC)
2. Complete Phase 3: User Story 1 (CronJob + establish default)
3. **STOP and VALIDATE**: implicit claim binds to `lvms-loopback`
4. Continue with US2/US3 for full coverage

### Incremental Delivery

1. Setup + Foundational → values + RBAC ready
2. US1 → CronJob establishes default
3. US2 → idempotence + drift recovery proven
4. US3 → explicit choices preserved
5. Polish → documentation + full validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- The Job is a bounded, idempotent imperative exception recorded in Git (Constitution II)
- Commit after each task or logical group