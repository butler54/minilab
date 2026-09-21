# Research: Observability Overrides

## Decision: One dedicated override file `overrides/values-observability.yaml`

**Rationale**: The user directed a single override file (confirmed in clarification) and the repository already follows a one-override-per-concern pattern (`overrides/values-storage-lvm.yaml` for storage). The entire `global.observability` block (enabled, cooNamespace, stackNamespace, retention, storageClass, externalTargets, dashboards, alertRules, rbac) moves wholesale into `overrides/values-observability.yaml`. Keeping it in one file matches the existing pattern and keeps the relocation mechanical with zero behavior change.

**Alternatives considered**:

- Multiple concern-based override files (base + targets + dashboards + rules + rbac): rejected — the user chose a single file, and splitting would introduce more `sharedValueFiles` entries and merge complexity for no functional gain.
- Keeping the block in `values-global.yaml`: rejected — that is the exact state this feature removes.

## Decision: Wire via `clusterGroup.sharedValueFiles`

**Rationale**: The pattern already applies `overrides/values-storage-{{ $.Values.global.storageProvider }}.yaml` through `clusterGroup.sharedValueFiles` in `values-prod.yaml`. Adding `/overrides/values-observability.yaml` to the same list applies it automatically at install, in the same order and with the same precedence semantics (a later, operator-explicit `extraValueFiles` entry wins). This satisfies FR-002/FR-004 with no new mechanism.

**Alternatives considered**:

- Reference the override from the observability chart's application definition directly: rejected — the pattern standardizes on `sharedValueFiles`, and mixing mechanisms would diverge from the storage pattern.
- Move the block into the chart's `values.yaml` and rely on chart defaults: rejected — the operator-facing surface must remain editable in a values file, not baked into chart defaults.

## Decision: Leave the chart `values.yaml` defaults as the baseline

**Rationale**: `charts/observability-config/values.yaml` already holds identical defaults for `global.observability` so `helm template` works standalone during development. The override file supplies the operator-facing settings that previously lived in `values-global.yaml`; the chart defaults remain the fallback. This preserves SC-005 (existing render/lint/tests pass) because `helm template ... -f values-global.yaml` continues to render from chart defaults even after the global block is removed.

**Alternatives considered**:

- Delete the chart `values.yaml` defaults and require the override for every render: rejected — it would break standalone `helm template` and the existing shell tests that render with only `values-global.yaml`.

## Implementation Verification Required

- Confirm that removing `global.observability` from `values-global.yaml` and adding the override file through `sharedValueFiles` yields byte-equivalent rendered output versus the current bundled configuration (validate with `helm template` before and after).
- Confirm the `sharedValueFiles` list order is preserved so the storage override and observability override both apply without interaction.
- Confirm no other file (scripts, tests, Makefile) references `global.observability` from `values-global.yaml` in a way that the relocation would break.
