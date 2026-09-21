# Implementation Plan: Observability Overrides

**Branch**: `003-observability-overrides` | **Date**: 2026-09-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-observability-overrides/spec.md`

## Summary

Relocate the observability configuration from `values-global.yaml` into a single dedicated override file `overrides/values-observability.yaml`, wired through the pattern's existing `sharedValueFiles` mechanism so it is applied automatically on install. This mirrors the existing storage override (`overrides/values-storage-lvm.yaml`). No observability behavior changes; rendered output must remain identical.

## Technical Context

**Language/Version**: YAML, Helm, and shell; versions supplied by the Validated Patterns utility container.

**Primary Dependencies**: Validated Patterns clustergroup chart `sharedValueFiles` mechanism; the existing `charts/observability-config` chart.

**Storage**: N/A (configuration relocation only).

**Testing**: Existing shell validation (`tests/validate-pattern-config.sh`, `tests/test-observability-*.sh`) and Helm render/lint must continue to pass unchanged; a new precedence test mirrors `tests/test-vault-storage-override.sh`.

**Target Platform**: Connected single-node OpenShift 4.22 lab.

**Project Type**: Validated Pattern repository (GitOps configuration).

**Performance Goals**: None — no runtime change.

**Constraints**: `values-global.yaml` must no longer contain observability-specific settings; the override file must be applied via `sharedValueFiles`; rendered observability resources must be byte-equivalent to the current bundled output.

**Scale/Scope**: One new override file, one edit to `values-global.yaml`, one edit to `values-prod.yaml`, one documentation update, one new test.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Plan response | Status |
|-----------|---------------|--------|
| GitOps-First | The observability override is a Git-versioned values file reconciled via the existing shared-value-files mechanism; no on-cluster mutation. | Pass |
| Imperative Only Second | No imperative step is introduced. | Pass |
| Helm Only, No Kustomize | Values-file relocation only; no Kustomize artifacts. | Pass |
| Simplicity First | Reuses the existing one-override-per-concern pattern (storage); a single override file, not multiple. | Pass |

**Post-design re-check**: Pass. The design adds one values file and one shared-value-files entry, removing duplication from the global file.

## Project Structure

### Documentation (this feature)

```text
specs/003-observability-overrides/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/observability-override.md
└── tasks.md                 # Created by /speckit.tasks
```

### Source Code (repository root)

```text
values-global.yaml                            # Remove global.observability block (stays pattern-wide only)
values-prod.yaml                              # Add overrides/values-observability.yaml to sharedValueFiles
overrides/values-observability.yaml           # NEW: the relocated observability configuration surface
tests/test-observability-override.sh          # NEW: precedence + relocation assertions
README.md                                     # Document the observability override location
```

**Structure Decision**: Follow the repository's established override model — one concern per override file under `overrides/`, wired via `clusterGroup.sharedValueFiles` in `values-prod.yaml`, exactly as `values-storage-lvm.yaml` is today. The chart's own `values.yaml` defaults remain the baseline so standalone `helm template` still works.

## Complexity Tracking

No constitution violations. No exceptions required.
