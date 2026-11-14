# Implementation Plan: OCP 5.0.1 Operator Review & OpenShell 0.1.x Upgrade

**Branch**: direct commits on `main` (Clarifications 2026-11-14; hook branch `014-ocp501-openshell-upgrade` exists but is not used for delivery) | **Date**: 2026-11-14 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/014-ocp501-openshell-upgrade/spec.md`

## Summary

The cluster platform moved to OpenShift 5.0.1 underneath GitOps-managed pins. This feature (1) reviews every pattern-managed operator subscription against the 5.0.1 operator hub catalog and updates pins where appropriate — lvms moves to the `stable-5.0` channel, cluster-observability switches install-plan approval Manual→Automatic, and the RHBK subscription's post-upgrade resolution failure is investigated and resolved or held with rationale; (2) raises every OpenShell pin from 0.1.3 to **0.1.8** (the latest stable 0.1.x, chart verified at the pinned OCI repo, digest `sha256:39a56c7...`), including workstation CLI; and (3) runs the acceptance suite (static gates, live auth smoke, demo smoke, sandbox lifecycle) and records evidence. All changes land as direct commits on `main`, converged by Argo CD only, with any forced sync recorded (constitution I/II).

## Technical Context

**Language/Version**: Declarative GitOps configuration — YAML values (Validated Patterns clustergroup) + Helm; shell/python test harness (`tests/*.sh`); no application code.

**Primary Dependencies**: OpenShift 5.0.1 (Kubernetes 1.36; OLM v0 Subscriptions coexisting with OLM v1 `clustercatalogs`: `openshift-redhat-operators`, `openshift-certified-operators`, `openshift-community-operators`); single Argo CD instance (`singleArgoCD: true`); OpenShell 0.1.8 — chart `oci://ghcr.io/nvidia/openshell/helm-chart:0.1.8` (digest `sha256:39a56c77b78edd2a5c4ac7e17720b5720e1649e5e9f63743342a53940c01be81`, appVersion 0.1.8), images `ghcr.io/nvidia/openshell/*:0.1.8`; openshell CLI 0.1.8 (brew or GitHub release asset); RHBK (Keycloak) for OIDC auth, currently `rhbk-operator.v26.6.9-opr.1`.

**Storage**: N/A (Git is the source of truth; no data storage introduced).

**Testing**: `make test-static` (shell suite incl. `tests/test-lvms-ordering.sh`, `tests/test-openshell-pins.sh`), `make validate-openshell` (+`-live`, `-demo`), `tests/check-openshell-cli.sh`, `./pattern.sh make validate-schema`, `make argo-healthcheck` / `make validate-cluster`.

**Target Platform**: minilab single-node OpenShift (SNO), now 5.0.1, 8-CPU budget.

**Project Type**: GitOps deployment configuration (Red Hat Validated Pattern).

**Performance Goals**: All Argo CD applications Synced+Healthy within 15 minutes of the final push (SC-002); acceptance suite completes within one operator session; no regression in the 010 CPU-stabilization posture — OLM no-op copy-status PUT rate remains <1/s (010-measured baseline 0.21/s), observed via platform Prometheus during acceptance stage 4.

**Constraints**: Constitution I–IV (GitOps-only convergence, recorded imperative steps, Helm-only packaging, simplicity); version-pinned trusted sources only; no secret material in Git; direct commits on `main` (decided 2026-11-14).

**Scale/Scope**: 7 pattern-declared operator subscriptions reviewed (plus 1 framework-managed subscription, patterns-operator, recorded observationally); 1 subscription channel-updated (lvms) + 1 approval-mode change (cluster-observability) + 1 resolution-failure investigation (rhbk); 1 OpenShell pin set (chart + 3 image tags + CLI) 0.1.3→0.1.8; 7 acceptance stages (per contracts/acceptance-suite.md).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Basis |
|---|---|---|
| I. GitOps-First | PASS | All desired-state changes are values-file edits on `main`; Argo CD is the only convergence path; no `oc apply` of desired state. |
| II. Imperative Only Second | PASS (with recorded steps) | Forced Argo refresh/sync, CLI install, and (if needed) stale-installplan cleanup are imperative; each is recorded in the tracking artifact with command/output before running. Teardown steps (pre-upgrade, acceptance lifecycle) use idempotent, repeat-until-empty procedures recorded the same way — not bare one-off commands. |
| III. Helm Only, No Kustomize | PASS | No packaging changes; OpenShell stays a version-pinned Helm chart; operators stay clustergroup subscriptions. |
| IV. Simplicity First | PASS | No new components; review covers existing pattern-declared subscriptions only (Clarifications 2026-11-14). |
| Platform Constraints (SNO, pinned sources) | PASS | Chart 0.1.8 pinned by version at the existing trusted OCI repo (digest verified); images from the same upstream; no footprint growth. |
| Development Workflow (gates) | PASS | Plan requires `test-static`, `validate-schema`, `argo-healthcheck`, and `make validate-cluster` green before completion (FR-009, SC-005). |

Delivery-mode note: the constitution's "commits (and pull requests)" wording is parenthetical, not a MUST; this feature's direct-to-`main` delivery was explicitly decided in Clarifications 2026-11-14 on GitOps-convergence grounds (only `main` is converged), matching the feature-012 precedent.

No violations → Complexity Tracking section not required.

## Project Structure

### Documentation (this feature)

```text
specs/014-ocp501-openshell-upgrade/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output: operator catalog findings + 0.1.8 release analysis
├── data-model.md        # Phase 1 output: entities (pins, review decisions, evidence)
├── quickstart.md        # Phase 1 output: end-to-end validation guide
├── contracts/
│   ├── operator-review.md   # review-artifact record format (consumed by tasks + converge)
│   └── acceptance-suite.md  # acceptance stages, commands, pass criteria
├── checklists/requirements.md  # spec quality checklist (specify/clarify output)
├── review-log.md       # Phase 2+: the operator review artifact + acceptance evidence (FR-001/FR-007/FR-010)
└── tasks.md            # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
values-global.yaml                       # global.lvmsCompatibility: channel/startingCSV/ocpRelease/cliImage
values-prod.yaml                         # clusterGroup.subscriptions (lvms, coo approval mode) + applications.openshell.chartVersion
overrides/values-openshell-gateway.yaml  # gateway/sandboxRuntime/supervisor image tags 0.1.3 -> 0.1.8
charts/lvms-config/                      # renders LVMCluster from lvmsCompatibility (verify against stable-5.0 CSV)
tests/test-lvms-ordering.sh              # asserts lvms pins + rendered config (update with the pin change)
tests/test-openshell-pins.sh             # asserts openshell/agent-sandbox pins (update 0.1.3 -> 0.1.8)
tests/check-openshell-cli.sh             # CLI/chart version tie (unchanged)
Makefile / Makefile-common               # validation gates (unchanged)
```

**Structure Decision**: No new source structure — the feature edits the existing pattern values surfaces, their asserting tests, and adds evidence artifacts under `specs/014-ocp501-openshell-upgrade/`. This matches constitution III/IV (no new packaging, no new components).

## Constitution Check (post-Phase 1 re-evaluation)

Re-checked after design **and after the 2026-11-14 `/speckit.analyze` remediation pass** (findings F1–F7, C1–C4, B1–B3, E1, D1–D3, A1–A2 addressed across spec.md, plan.md, data-model.md, contracts/, and tasks.md): the data model and contracts introduce only documentation artifacts and Git-surface edits; no principle above changes status. RHBK contingency (subscription channel fix or documented hold) stays inside the GitOps subscription surface either way. **All gates remain PASS.**
