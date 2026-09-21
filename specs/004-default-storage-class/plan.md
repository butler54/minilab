# Implementation Plan: Default Storage Class

**Branch**: `004-default-storage-class` | **Date**: 2026-09-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-default-storage-class/spec.md`

## Summary

Ensure the LVMS-based `lvms-loopback` storage class is the cluster-wide default so workloads that request no storage class (e.g. the COO-managed Perses server) can provision persistent storage on the single-node lab. A dedicated scheduled Kubernetes Job in the `lvms-config` chart checks whether any storage class is already the default; if none is, it annotates `lvms-loopback` with `storageclass.kubernetes.io/is-default-class: "true"`. The Job is idempotent, least-privilege, and only acts when no default exists (it never alters an existing foreign default or changes explicit storage choices).

## Technical Context

**Language/Version**: YAML, Helm, and shell; versions supplied by the Validated Patterns utility container (the `ose-cli` image used by the existing readiness Job).

**Primary Dependencies**: OpenShift LVM Storage Operator (already deployed), the `lvms-loopback` StorageClass it generates, and the existing `lvms-config` chart conventions (Sync hook Job + least-privilege RBAC).

**Storage**: N/A — this feature annotates an existing StorageClass; it does not provision storage.

**Testing**: Helm render tests; shell tests asserting the Job renders with the correct RBAC, image, and logic; and an idempotence assertion that the default-class annotation is applied only when no default exists (mirrors the existing `test-lvms-ordering.sh` style).

**Target Platform**: Connected single-node OpenShift 4.22 lab with LVMS.

**Project Type**: Validated Pattern repository (GitOps configuration).

**Performance Goals**: None — the Job runs on a schedule and does negligible work.

**Constraints**: Must be GitOps-declared, idempotent, least-privilege, and must not override explicit storage-class choices or an existing foreign default. Must not require manual cluster-side commands.

**Scale/Scope**: One scheduled Job manifest, one RBAC set, one values entry, one test, and documentation.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Plan response | Status |
|-----------|---------------|--------|
| GitOps-First | The scheduled Job and its RBAC are declared in the `lvms-config` chart and reconciled by Argo CD; the default-class marking is a Git-declared, reproducible action. | Pass |
| Imperative Only Second | The Job is a bounded, idempotent imperative exception (annotating a StorageClass that cannot be expressed declaratively today); it is automated, idempotent, recorded in Git, and its effect is a declarative annotation. | Pass |
| Helm Only, No Kustomize | Implemented as a Helm chart template; no Kustomize artifacts. | Pass |
| Simplicity First | A single scheduled Job reusing existing `lvms-config` conventions; rejected the heavier Ansible imperative framework (coco-pattern) for this one small task. | Pass |

**Post-design re-check**: Pass. The design adds one scheduled Job and RBAC to an existing chart, with no new runtime, no committed secrets, and no override of explicit or foreign-default state.

## Project Structure

### Documentation (this feature)

```text
specs/004-default-storage-class/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/default-storage-class.md
└── tasks.md                 # Created by /speckit.tasks
```

### Source Code (repository root)

```text
charts/lvms-config/values.yaml                     # Add defaultStorageClassJob enable flag + schedule
charts/lvms-config/templates/                      # New scheduled Job template (CronJob) + RBAC
values-global.yaml                                 # global.localStorage.defaultStorageClass toggle (if needed)
tests/test-default-storage-class.sh                # NEW: render + logic + idempotence assertions
README.md                                          # Document the default-storage-class mechanism
```

**Structure Decision**: Follow the repository's established `lvms-config` chart pattern. Add a `CronJob` (scheduled, idempotent) plus its ServiceAccount/Role/RoleBinding in the same chart, gated by a values flag so operators can disable it. Use the same `ose-cli` image and least-privilege RBAC conventions as the existing readiness Job.

## Complexity Tracking

No constitution violations. No exceptions required. The Job is a bounded imperative exception recorded in Git, consistent with Constitution II (Imperative Only Second).