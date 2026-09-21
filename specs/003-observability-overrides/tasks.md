# Tasks: Observability Overrides

**Input**: Design documents from `specs/003-observability-overrides/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Relocation invariants (SC-001 byte-equivalence, SC-004 precedence) require test tasks; they are validation gates, not TDD.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Pattern values at repository root: `values-global.yaml`, `values-prod.yaml`, `overrides/`, `charts/observability-config/`, `tests/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Capture the pre-change baseline so equivalence can be proven

- [X] T001 Capture the current rendered observability output to `specs/003-observability-overrides/baseline-render.yaml` using `helm template observability-config charts/observability-config -f values-global.yaml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the override file that all user stories consume

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Create `overrides/values-observability.yaml` containing the complete `global.observability` block (enabled, cooNamespace, stackNamespace, retention, storageClass, externalTargets, dashboards, alertRules, rbac) copied verbatim from `values-global.yaml`

**Checkpoint**: The override file exists and holds the full observability surface.

---

## Phase 3: User Story 1 - Move Observability Configuration Out of Global Values (Priority: P1) 🎯 MVP

**Goal**: Remove the observability block from `values-global.yaml` so it stays pattern-wide only, while rendered output remains identical via chart defaults.

**Independent Test**: `values-global.yaml` no longer contains `global.observability`, and `helm template ... -f values-global.yaml` still renders the observability resources.

### Implementation for User Story 1

- [X] T003 [US1] Remove the `global.observability` block from `values-global.yaml`, leaving only pattern-wide defaults
- [X] T004 [US1] Render `helm template observability-config charts/observability-config -f values-global.yaml` and confirm it still emits the observability resources from chart defaults

**Checkpoint**: User Story 1 complete — global file is clean, rendering unaffected.

---

## Phase 4: User Story 2 - Wire the Override Through the Established Override Mechanism (Priority: P1)

**Goal**: Apply the override automatically via `sharedValueFiles`, with operator-explicit values taking precedence.

**Independent Test**: `values-prod.yaml` lists `/overrides/values-observability.yaml` in `clusterGroup.sharedValueFiles`, and a later operator value overrides it.

### Implementation for User Story 2

- [X] T005 [US2] Add `/overrides/values-observability.yaml` to `clusterGroup.sharedValueFiles` in `values-prod.yaml`, preserving the existing storage override entry and order
- [X] T006 [US2] Add a shell test `tests/test-observability-override.sh` asserting the override file is listed in `sharedValueFiles` and that `values-global.yaml` no longer contains `global.observability`
- [X] T007 [US2] Extend `tests/test-observability-override.sh` to assert an operator-explicit value file overrides the observability override (mirroring `tests/test-vault-storage-override.sh`)

**Checkpoint**: User Stories 1 AND 2 work — override applies automatically with correct precedence.

---

## Phase 5: User Story 3 - Documented Override Location (Priority: P2)

**Goal**: Document the observability override location so operators know where to edit observability settings.

**Independent Test**: `README.md` points to `overrides/values-observability.yaml` as the observability configuration location.

### Implementation for User Story 3

- [X] T008 [US3] Update `README.md` to document `overrides/values-observability.yaml` as the observability configuration surface, replacing the previous `global.observability` reference

**Checkpoint**: All user stories complete — relocation wired and documented.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Confirm full validation and equivalence

- [X] T009 [P] Run `tests/validate-pattern-config.sh` and confirm it passes
- [X] T010 [P] Run the four existing observability suites (`tests/test-observability-dashboards.sh`, `tests/test-observability-alerts.sh`, `tests/test-observability-configurability.sh`, `tests/test-observability-rbac.sh`) and confirm they pass unchanged
- [X] T011 Run `tests/test-observability-override.sh` and confirm relocation + precedence assertions pass
- [X] T012 Diff `helm template observability-config charts/observability-config -f values-global.yaml` against `specs/003-observability-overrides/baseline-render.yaml` and confirm byte-equivalence (SC-001)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
- **Polish (Final Phase)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational - no dependencies on other stories
- **User Story 2 (P1)**: Depends on US1 (the global block must be removed before wiring the override so no duplication remains); independently testable once US1 done
- **User Story 3 (P2)**: Can start after Foundational - depends on the override file path (T002) but not on US1/US2

### Within Each User Story

- Override file before removal before wiring
- Test assertions follow the implementation they verify

### Parallel Opportunities

- T009 and T010 (Polish validation suites) can run in parallel
- US3 (documentation) can run in parallel with US2 once T002 exists

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (baseline) + Phase 2 (override file)
2. Complete Phase 3: User Story 1 (remove from global)
3. **STOP and VALIDATE**: render still emits observability resources
4. Continue with US2 (wiring) for the full feature

### Incremental Delivery

1. Setup + Foundational → override file ready
2. US1 → global file clean, rendering unaffected
3. US2 → wired via sharedValueFiles with precedence test
4. US3 → documented
5. Polish → full validation + byte-equivalence proof

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- This is a config relocation with zero behavior change; the byte-equivalence check (T012) is the primary correctness gate
- Commit after each task or logical group
