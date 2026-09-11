# Feature Specification: Bootstrap Local Storage

**Feature Branch**: `001-bootstrap-local-storage`

**Created**: 2026-09-10

**Status**: Draft

**Input**: User description: "The pattern needs Vault and therefore needs local dynamic storage for persistent volume claims. Add a pre-pattern bootstrap action to the standard Make workflow, install the local storage operator before Vault through reconciliation ordering, and configure Vault to use the resulting storage class by default."

## Clarifications

### Session 2026-09-11

- Q: How much local capacity should the default storage bootstrap reserve for Vault? -> A: Reserve 100 GiB by default for multiple workloads, with a configurable capacity parameter.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prepare Local Persistent Storage (Priority: P1)

As a pattern operator, I can run the standard installation workflow on a single-node lab with no spare disk so that the cluster has local dynamic storage available before pattern workloads are installed.

**Why this priority**: Vault cannot reliably persist its data without a storage class that can satisfy persistent volume claims.

**Independent Test**: Run the documented pre-install workflow on a supported fresh cluster and confirm that a storage class is available for a test persistent volume claim.

**Acceptance Scenarios**:

1. **Given** a supported cluster with no unused physical disk, **When** the operator runs the pre-install workflow, **Then** the workflow prepares local storage capacity without requiring manual cluster changes.
2. **Given** local storage has already been prepared, **When** the operator reruns the pre-install workflow, **Then** it completes safely without duplicating or disrupting the existing storage configuration.
3. **Given** the local storage preparation cannot complete, **When** the workflow runs, **Then** it stops before pattern installation and provides an actionable failure message.

---

### User Story 2 - Install Storage Before Vault (Priority: P1)

As a pattern operator, I can install the pattern knowing that the local storage service is available before Vault is reconciled, so Vault does not start without persistent storage.

**Why this priority**: The storage service must be ready before Vault requests its persistent volume.

**Independent Test**: Install the pattern after storage preparation and verify that the storage service is reconciled before Vault and Vault receives persistent storage.

**Acceptance Scenarios**:

1. **Given** the storage bootstrap completed successfully, **When** the pattern is installed, **Then** the local storage service is scheduled for reconciliation before Vault.
2. **Given** the local storage service is not healthy, **When** Vault would otherwise be installed, **Then** Vault is not reported ready until its storage requirement can be met.

---

### User Story 3 - Use Local Storage for Vault (Priority: P2)

As a pattern operator, I can install Vault without supplying storage overrides so that it uses the pattern-provided local storage class by default.

**Why this priority**: A safe default removes a manual and error-prone installation step for the primary supported environment.

**Independent Test**: Install Vault using the pattern's default values and verify that its persistent volume claim is bound through the designated local storage class.

**Acceptance Scenarios**:

1. **Given** the local storage service is ready, **When** Vault is installed with default pattern values, **Then** its persistent storage request uses the designated local storage class.
2. **Given** an operator supplies a supported alternative storage configuration, **When** Vault is installed, **Then** the explicit operator configuration takes precedence over the default.

### Edge Cases

- The cluster has insufficient local capacity for the selected shared-storage capacity.
- A previous incomplete bootstrap leaves partial local-storage state.
- The designated local storage class already exists but does not meet the pattern's requirements.
- Vault is enabled while the local storage service is unavailable or unhealthy.
- An operator intentionally configures Vault to use a different supported storage class.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pattern MUST provide a documented pre-install action that prepares local dynamic storage on supported single-node clusters without an unused physical disk.
- **FR-002**: The pre-install action MUST be available from the pattern's standard Make-based workflow.
- **FR-003**: The pre-install action MUST be idempotent: repeated successful runs MUST preserve the usable local storage configuration and MUST NOT require manual cleanup.
- **FR-004**: The pre-install action MUST reserve 100 GiB of local dynamic storage by default and MUST provide a documented configuration parameter for operators to select a different capacity.
- **FR-005**: The pre-install action MUST validate that the selected local capacity is available before allowing pattern installation to proceed.
- **FR-006**: The pattern MUST stop and report the failed prerequisite when local storage preparation or validation cannot complete.
- **FR-007**: The pattern MUST declare the local storage service as a dependency that is reconciled before Vault.
- **FR-008**: The pattern MUST prevent Vault from reaching a ready state until its default persistent storage request can be satisfied.
- **FR-009**: The pattern MUST configure Vault to request the designated local storage class by default.
- **FR-010**: The pattern MUST allow an operator's supported Vault storage override to replace the default storage-class selection.
- **FR-011**: The pattern MUST document the supported environment, required local capacity, capacity configuration parameter, bootstrap invocation, verification steps, failure recovery, and the scope of the local-storage configuration.

### Key Entities

- **Local storage capacity**: The configurable cluster-local capacity prepared for dynamically provisioned persistent volumes; it defaults to 100 GiB.
- **Designated storage class**: The default persistent-volume selection provided by the pattern for Vault.
- **Storage bootstrap state**: The recorded condition indicating whether local capacity was prepared and validated successfully.
- **Vault persistence request**: Vault's request for durable storage, which uses the designated storage class unless an operator overrides it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a supported fresh single-node cluster with no spare disk, an operator can prepare 100 GiB of local dynamic storage and complete the default pattern installation without manual cluster configuration in one documented workflow.
- **SC-002**: In 100% of clean-install validation runs, the designated storage class is available before Vault's persistent storage request is evaluated.
- **SC-003**: In 100% of clean-install validation runs using default values, Vault's persistent storage request is bound through the designated storage class before Vault is reported ready.
- **SC-004**: In 100% of repeated bootstrap validation runs, the workflow completes without creating duplicate usable storage configurations or requiring manual cleanup.
- **SC-005**: Operators can identify and resolve an insufficient-capacity or failed-bootstrap condition from the workflow output and documentation without inspecting cluster internals.

## Assumptions

- The target environment is the repository's supported single-node OpenShift lab and has enough host capacity to reserve the selected local-storage capacity, although it has no unused physical disk.
- The bootstrap action is an approved imperative exception because local storage must exist before GitOps can reconcile dependent workloads; its resulting desired configuration remains represented in Git.
- The mechanism used to provide local capacity and the selected storage provider will be chosen during planning, subject to platform compatibility validation.
- The local storage capacity supports multiple workloads; this feature configures the default storage class only for Vault.
