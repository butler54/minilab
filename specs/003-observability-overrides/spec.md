# Feature Specification: Observability Overrides

**Feature Branch**: `003-observability-overrides`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "the configuration is bundled currently into values-global.yaml. Use overrides files to break out the observability overrides."

## Clarifications

### Session 2026-09-21

- Q: Should all observability settings move into a single override file, or be split into multiple override files by concern? -> A: A single dedicated override file (`values-observability.yaml`) holding the entire observability surface.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Move Observability Configuration Out of Global Values (Priority: P1)

As a pattern operator, I can keep the observability configuration separate from the pattern's global values so that the global file stays focused on pattern-wide defaults and observability settings are edited in a dedicated location.

**Why this priority**: The configuration is currently bundled into `values-global.yaml`; separating it is the entire purpose of this feature.

**Independent Test**: After the change, the global values file no longer contains the observability block, and the pattern still renders the same observability resources from the dedicated override file.

**Acceptance Scenarios**:

1. **Given** the pattern is installed, **When** the observability configuration lives in a dedicated override file, **Then** the rendered observability resources are identical to those produced by the previous bundled configuration.
2. **Given** the global values file, **When** an operator inspects it, **Then** it no longer contains observability-specific settings.

---

### User Story 2 - Wire the Override Through the Established Override Mechanism (Priority: P1)

As a pattern operator, I can have the observability override applied automatically through the pattern's existing shared-value-files mechanism so that the override is reconciled without a separate step.

**Why this priority**: The pattern already has an override mechanism for storage; reusing it keeps the behavior consistent and declarative.

**Independent Test**: Install the pattern and confirm the observability override file is applied through the shared-value-files mechanism and takes effect.

**Acceptance Scenarios**:

1. **Given** the pattern's shared-value-files configuration, **When** the observability override file is listed there, **Then** it is applied automatically on install.
2. **Given** an operator's later explicit value file, **When** it overrides an observability setting, **Then** the operator's value takes precedence over the observability override, matching the existing storage override behavior.

---

### User Story 3 - Documented Override Location (Priority: P2)

As a pattern operator, I can find and edit the observability override file easily so that changing external targets, dashboards, alert rules, and access groups does not require touching the global values.

**Why this priority**: A clear, documented location is what makes the separation usable in practice.

**Independent Test**: Locate the observability override file from the pattern documentation and confirm it contains the configurable observability surface.

**Acceptance Scenarios**:

1. **Given** the pattern documentation, **When** an operator looks up where observability settings live, **Then** it points to the dedicated override file.
2. **Given** the override file, **When** an operator edits external targets, dashboards, alert rules, or access groups, **Then** the change is reflected after reconciliation without editing the global values.

---

### Edge Cases

- The observability override file is missing or not referenced; the pattern must not silently lose observability configuration — installation or validation must surface it.
- An operator removes or renames the override file; reconciliation must not apply stale observability settings.
- Values exist in both the global file and the override (migration state); the override must deterministically take precedence so behavior is predictable during transition.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pattern MUST move all observability-specific configuration out of `values-global.yaml` into a single dedicated override file (`values-observability.yaml`).
- **FR-002**: The observability override file MUST be wired into the pattern through the existing shared-value-files mechanism so it is applied automatically during installation.
- **FR-003**: The override file MUST preserve every existing observability setting (enablement flag, namespaces, retention, storage class, external targets, dashboards, alert rules, and access groups) with equivalent rendered output.
- **FR-004**: The observability override MUST follow the same precedence rules as the existing storage override: a later, operator-explicit value file takes precedence over the observability override.
- **FR-005**: The pattern MUST document the observability override location and its configuration surface.
- **FR-006**: Existing validation (render, lint, and shell tests) MUST continue to pass after the configuration is relocated, confirming rendered output is unchanged.
- **FR-007**: The global values file MUST remain focused on pattern-wide defaults and MUST NOT contain observability-specific settings after the change.

### Key Entities

- **Observability override file**: The single dedicated values file (`values-observability.yaml`) holding the observability configuration surface, referenced by the shared-value-files mechanism.
- **Global values file**: The pattern-wide defaults file that must no longer contain observability-specific settings.
- **Shared-value-files mechanism**: The existing declarative mechanism that applies override files during reconciliation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of validation runs, the rendered observability resources produced from the override file are identical to those produced by the prior bundled configuration.
- **SC-002**: The global values file contains zero observability-specific settings after the change.
- **SC-003**: In 100% of install validation runs, the observability override is applied automatically through the shared-value-files mechanism without a manual step.
- **SC-004**: In 100% of validation runs, an operator-explicit value file overrides the observability override, matching the storage override precedence.
- **SC-005**: All existing render, lint, and shell validation tests pass unchanged after the configuration is relocated.

## Assumptions

- The existing storage override (`overrides/values-storage-<provider>.yaml`) is the reference pattern for how overrides are structured and wired via shared-value-files.
- The observability configuration is broken into a single dedicated override file, consistent with the one-override-per-concern pattern already used for storage.
- The chart's own `values.yaml` defaults remain the baseline; the override file supplies the operator-facing observability settings that previously lived in `values-global.yaml`.
- No observability behavior changes are intended — this is a relocation of configuration only, not a functional change.
