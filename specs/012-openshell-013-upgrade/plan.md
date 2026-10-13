# Implementation Plan: Upgrade OpenShell Stack to 0.1.3

**Branch**: none — direct commits on `main` (Clarifications 2026-10-13) | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-openshell-013-upgrade/spec.md` (tracks butler54/minilab#8)

## Summary

Raise the minilab openshell pin set from 0.1.1 to **0.1.3** (chart + 3 component
image tags + workstation CLI), commit-and-push directly on `main`, force Argo CD
convergence (`refresh=hard` + sync op, recorded imperative step), then validate
that **policy attached at sandbox-create time is honored from birth** (issue #8
action 1) and adopt that mechanism in the 008/011 demo drivers — with the
racing create+policy-set loop retained as documented fallback if validation
fails. All pin bumps land in ONE atomic commit so the five version values never
diverge. Research (`research.md`) verified upstream assets exist, the values
schema diff is purely additive, and the CLI parity path via the Makefile's
upstream-installer fallback + `brew unlink`.

## Technical Context

**Language/Version**: N/A (YAML values, bash scripts, make targets)

**Primary Dependencies**: NVIDIA OpenShell OCI chart `ghcr.io/nvidia/openshell/helm-chart` 0.1.3 (verified present), component images `ghcr.io/nvidia/openshell/{gateway,sandbox-runtime,supervisor}:0.1.3`; `openshell` CLI 0.1.3 (upstream installer; brew 0.1.1 shadowing resolved via `brew unlink`), `helm` 3.22, `oc` (kube:admin), Argo CD in `vp-gitops`

**Storage**: N/A (Git is system of record)

**Testing**: `make test-static` (repo bash+yaml suite incl. `test-openshell-pins.sh`, `test-external-refs.sh`, `test-openshell-render.sh`, `check-openshell-cli.sh`), `./pattern.sh make validate-schema`, live demo-log assertions

**Target Platform**: minilab sno (OCP 4.22 SNO), ArgoCD-driven GitOps

**Project Type**: infrastructure / GitOps values-and-scripts change

**Performance Goals**: Argo CD convergence ≤ 15 min (SC-001); ready-from-create sandbox with policy active ≤ 5 min (SC-004); zen smoke ≤ 15 min incl. fence-wait

**Constraints**: GitOps-first (constitution I); single-sync imperative step recorded (constitution II); Helm-only (III); simplicity (IV — no new components); zero residual; chart pin = CLI pin = image tags enforced

**Scale/Scope**: 5 edited files (2 values, 3 test), 2 demo scripts, 3 docs (demo-log/runbook/issues), zero new charts

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Gate | Status |
|---|---|---|
| I. GitOps-First | All platform change flows through Git → Argo CD; no `oc` mutations of platform resources | **PASS** — pin bumps are Git commits; validation probes are read/exec-only; forced sync is trigger-only (desired state remains Git) |
| II. Imperative Only Second | One imperative step allowed (Argo CD force refresh + sync operation) — MUST be recorded in Git | **PASS** — recorded in `quickstart.md` G2 and the sprint's demo-log entry before it is run |
| III. Helm Only | Change set is values files + tests + bash; no kustomize | **PASS** |
| IV. Simplicity First | No new components — pins only; optional ocsfLog toggle explicitly deferred unless free | **PASS** |
| Platform Constraints | SNO footprint unchanged (replicaCount stays 1); secrets untouched; trusted pinned sources only | **PASS** |

Post-design re-evaluation: **all gates PASS**, no violations, no Complexity
Tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/012-openshell-013-upgrade/
├── plan.md              # this file
├── research.md          # Phase 0 — upstream assets, values diff, CLI path, sync mechanics
├── data-model.md        # Phase 1 — VersionPinSet, ArgoCDConvergence, PolicyAtCreateProof
├── contracts/
│   └── README.md        # U1 pins converged, U2 policy-at-create, U3 demo regression guard
├── quickstart.md        # G0–G6 validation guide
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
values-prod.yaml                              # chartVersion 0.1.1 -> 0.1.3 (openshell app only)
overrides/values-openshell-gateway.yaml       # gateway/sandboxRuntime/supervisor image.tag -> 0.1.3
tests/test-external-refs.sh                   # expected openshell chartVersion -> 0.1.3
tests/test-openshell-pins.sh                  # OSC_VER -> 0.1.3
tests/test-openshell-render.sh                # OSC_VER -> 0.1.3
deploy/openshell/demo/zen/run-zen-demo.sh     # adopt create --policy (post-validation)
deploy/openshell/demo/run-demo.sh             # adopt create --policy (post-validation)
docs/openshell-demo-opencode.md               # 0.1.3 runbook updates
specs/011-zen-sandbox-demo/demo-log.md        # link-forward note (011 evidence stays immutable)
                                  # (feature evidence log lives at specs/012-openshell-013-upgrade/demo-log.md)
```

**Structure Decision**: values-and-tests edit set matching the R5 pin-surface
list; demo scripts touched only after Contract U2 passes so a failed
validation never leaves scripts half-migrated.

## Complexity Tracking

No violations — no entries.
