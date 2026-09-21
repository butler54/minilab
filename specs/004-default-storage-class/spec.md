# Feature Specification: Default Storage Class

**Feature Branch**: `004-default-storage-class`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "Provide a mechanism to ensure that a default storage class is available based on LVMS. Use either the imperative framework see ../coco-pattern. Consider alternatives such as jobs."

## Clarifications

### Session 2026-09-21

- Q: Which mechanism should establish the default LVMS storage class? -> A: A dedicated scheduled Kubernetes Job in the `lvms-config` chart with least-privilege RBAC.
- Q: When another storage class is already the cluster default, what should the mechanism do? -> A: Only act when no default exists; leave an existing foreign default untouched.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ensure an LVMS-Based Default Storage Class Exists (Priority: P1)

As a pattern operator, I can install the pattern and rely on an LVMS-based storage class being the cluster default so that workloads without an explicit storage class (for example, COO-managed components) can provision persistent storage without manual cluster configuration.

**Why this priority**: The Perses server deployed by the Cluster Observability Operator requests a PVC without a storage class; with no cluster default it stays Pending, blocking dashboarding.

**Independent Test**: Install the pattern on a supported cluster where no default storage class exists, then confirm an LVMS-based storage class is present and marked as the cluster default, and a workload that requests no storage class can bind a persistent volume.

**Acceptance Scenarios**:

1. **Given** a cluster with no default storage class, **When** the pattern is installed, **Then** an LVMS-based storage class exists and is the cluster default.
2. **Given** the LVMS-based storage class is the default, **When** a workload requests persistent storage without specifying a storage class, **Then** its claim binds through the LVMS-based class.
3. **Given** the pattern is reinstalled or reconciled again, **When** the default-storage mechanism runs, **Then** it completes idempotently without creating duplicate or conflicting default classes.

---

### User Story 2 - Default Storage Class is Established via a Declared Mechanism (Priority: P1)

As a pattern operator, I can have the default storage class established through a Git-declared, reproducible mechanism rather than a manual one-off command, so that the cluster state is auditable and recreatable.

**Why this priority**: The constitution requires GitOps-First; an ad-hoc manual patch would be drift and would not survive a rebuild.

**Independent Test**: Inspect the repository and confirm a declared mechanism exists that establishes the LVMS default storage class; rerun it and confirm the class remains the default with no manual cluster-side action.

**Acceptance Scenarios**:

1. **Given** the pattern repository, **When** an operator inspects it, **Then** a declared mechanism for establishing the default storage class is present and documented.
2. **Given** the declared mechanism has already run, **When** it runs again, **Then** it is idempotent and leaves the correct default class unchanged.

---

### User Story 3 - Non-Default Workloads Remain Unaffected (Priority: P2)

As a pattern operator, I can continue to request a specific storage class explicitly and have that explicit choice respected, even when a default class exists.

**Why this priority**: The earlier storage feature deliberately avoided making the class Kubernetes-wide default so explicit choices always win; this feature must not break that contract.

**Independent Test**: Configure a workload with an explicit, supported storage class and confirm it binds to that class while the LVMS class remains the default for implicit requests.

**Acceptance Scenarios**:

1. **Given** an explicit supported storage class is requested by a workload, **When** the claim is created, **Then** it binds through the explicitly requested class, not the default.
2. **Given** a workload requests no class, **When** the claim is created, **Then** it binds through the LVMS-based default class.

---

### Edge Cases

- The LVMS storage class already exists but is not marked default; the mechanism must mark it default without recreating it.
- Another storage class is already the cluster default; the mechanism must leave it untouched and not act, since it only establishes the default when no default exists.
- The LVMS storage class is not yet ready when the mechanism runs; the mechanism must retry or fail in a way that does not leave the cluster without a default.
- The mechanism runs concurrently with a re-run; it must be idempotent and not produce conflicting default-class state.
- An operator explicitly removes the default-class marking; the mechanism must restore it on the next reconciliation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pattern MUST provide a declared mechanism that ensures an LVMS-based storage class is present and marked as the cluster default storage class.
- **FR-002**: The mechanism MUST run as part of pattern installation so the default class is available before dependent workloads reconcile.
- **FR-003**: The mechanism MUST be idempotent: repeated runs MUST NOT create duplicate storage classes or leave conflicting default-class state.
- **FR-004**: The mechanism MUST NOT require manual cluster-side commands; it MUST be driven from Git-declared configuration.
- **FR-004a**: The mechanism MUST establish the LVMS-based default class only when no storage class is already the cluster default; if another class is already default, the mechanism MUST leave it untouched.
- **FR-005**: The mechanism MUST NOT change the behavior for workloads that explicitly request a specific supported storage class; explicit choices MUST continue to win.
- **FR-006**: If the LVMS storage class is not ready when the mechanism runs, the mechanism MUST surface the failure and not silently leave the cluster without a default class.
- **FR-007**: The pattern MUST document the mechanism, its invocation, idempotence behavior, and how to verify the default class.

### Key Entities

- **Default storage class**: The LVMS-based storage class marked as the cluster-wide default used by claims that specify no class.
- **Declared mechanism**: The Git-declared process (imperative job or scheduled Kubernetes job) that establishes the default class.
- **Explicit storage choice**: A workload's explicit request for a specific supported storage class, which takes precedence over the default.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a supported cluster with no default storage class, the pattern install establishes an LVMS-based default storage class without manual cluster configuration.
- **SC-002**: In 100% of validation runs, a claim that requests no storage class binds through the LVMS-based default class.
- **SC-003**: In 100% of validation runs, a claim that explicitly requests a supported class binds through that class, not the default.
- **SC-004**: In 100% of repeated-mechanism validation runs, the default class is unchanged and no duplicate or conflicting default classes are created.
- **SC-004a**: In 100% of validation runs where another storage class is already the cluster default, the mechanism does not alter that default.
- **SC-005**: The mechanism is fully declared in Git and documented; no manual cluster-side command is required for the supported flow.

## Assumptions

- The target environment is the repository's supported single-node OpenShift lab where the only storage provider is LVMS and `lvms-loopback` is the intended default class.
- "Default storage class" means the Kubernetes default-class annotation that the scheduler uses when a claim omits a storage class.
- The mechanism is a dedicated scheduled Kubernetes Job in the `lvms-config` chart with least-privilege RBAC; the imperative framework from coco-pattern was considered and rejected as heavier than needed for this single small task.
- The mechanism establishes the default class for the LVMS storage class only; it does not manage other storage classes and does not alter an existing foreign default.