# Data Model: OCP 5.0.1 Operator Review & OpenShell 0.1.x Upgrade

**Date**: 2026-11-14 | Derived from [spec.md](spec.md) Key Entities and FR-001…FR-011.

This feature stores no runtime data; its "data" is the Git-declared pin configuration and the evidence artifacts produced during execution. Entities below define those records, their validation rules, and relationships.

## Entities

### OperatorSubscription

The Git-declared desired state for one operator, projected onto the cluster by the clustergroup chart as an OLM v0 Subscription.

| Field | Type / values | Validation |
|---|---|---|
| `name` | subscription key in `values-prod.yaml` `clusterGroup.subscriptions` | must match an installed subscription on the cluster |
| `namespace` | target namespace | must exist in `clusterGroup.namespaces` with OperatorGroup where required |
| `channel` | catalog channel name (e.g., `stable-5.0`) | MUST resolve in the 5.0.1 operator hub catalog (FR-004), except documented holds |
| `csv` | optional starting CSV pin (e.g., `lvms-operator.v5.0.0`) | when present, must be the channel's head or a deliberate pin |
| `installPlanApproval` | `Automatic` \| `Manual` | FR-011 changes only the cluster-observability subscription to `Automatic`; `eso` declares no approval in Git and its record states the OLM default explicitly |

**Relationships**: 1:1 with a `ReviewDecision`; lvms additionally joins to `global.lvmsCompatibility` (channel, startingCSV, ocpRelease, cliImage digest) — asserted equal by `tests/test-lvms-ordering.sh`.

**State transitions (observed on cluster)**: `AtLatestKnown` (healthy), `UpgradePending` (approval awaited — only legal pre-FR-011 for cluster-observability), `ResolutionFailed/ConstraintsNotSatisfiable` (catalog cannot satisfy pin — must resolve to a decision: update pin or documented hold). End state for every subscription: healthy installed CSV on a 5.0.1-compatible channel, or hold recorded.

### ReviewDecision

One record per OperatorSubscription in the review artifact (`specs/014-ocp501-openshell-upgrade/review-log.md`). Format contract: [contracts/operator-review.md](contracts/operator-review.md).

| Field | Content |
|---|---|
| operator | subscription name |
| pinBefore / pinAfter | channel + CSV + approval mode, before and after |
| catalogState | what the 5.0.1 hub offers (channels → CSVs), plus subscription conditions observed |
| decision | `UPDATE` \| `KEEP` \| `HOLD` |
| rationale | why, referencing catalog evidence |
| evidence | command outputs / dates |

**Validation**: the set of ReviewDecisions MUST cover 100% of `clusterGroup.subscriptions` keys (FR-001, SC-001) — the seven pattern-declared keys; the framework-managed `patterns-operator` subscription is an observational note, not a record; `UPDATE`/`HOLD` decisions MUST have their values change (or not) in Git exactly as recorded.

### OpenShellVersionPinSet

The single source of truth for platform version; all fields MUST hold the identical version (drift-asserted).

| Field | Location |
|---|---|
| chartVersion | `values-prod.yaml` → `clusterGroup.applications.openshell.chartVersion` |
| gateway image tag | `overrides/values-openshell-gateway.yaml` |
| sandboxRuntime image tag | `overrides/values-openshell-gateway.yaml` |
| supervisor image tag | `overrides/values-openshell-gateway.yaml` |
| CLI version (workstation) | installed binary, checked by `tests/check-openshell-cli.sh` |

**Validation**: all five equal `0.1.8` after the upgrade commit; the tie check MUST pass unmodified (FR-005/FR-006). Rollback (decided policy) flips all pins back in one commit — the set is atomic.

### AcceptanceStageResult

One record per acceptance stage executed (FR-007), stored in `review-log.md`.

| Field | Content |
|---|---|
| stage | `static-suite` \| `schema` \| `cli-tie` \| `convergence` \| `auth-smoke` \| `demo-smoke` \| `sandbox-lifecycle` |
| command | the exact make target / script invocation |
| outcome | `pass` \| `fail` \| `fail→fixed→pass` \| `fail→documented` |
| evidence | output capture or pointer |

**State transitions**: `fail` MUST transition to `fail→fixed→pass` (Git fix + re-run) or `fail→documented` (root cause + upstream reference); skipping or weakening a stage is prohibited (FR-008). Contract: [contracts/acceptance-suite.md](contracts/acceptance-suite.md).

### ImperativeStepRecord

Every imperative action taken (constitution II): forced Argo refresh/sync, CLI install, stale-installplan cleanup, RHBK investigation commands that mutate state.

| Field | Content |
|---|---|
| action | what was run (command) |
| rationale | why no declarative mechanism applied |
| result | outcome / output pointer |
| reconcileBack | how desired state returned under GitOps |

**Validation**: at feature end, zero unrecorded imperative steps; cluster state reconciles from `main` alone (FR-003, SC-005).

## Relationships summary

```text
OperatorSubscription 1—1 ReviewDecision        (review covers every subscription)
OperatorSubscription 1—1 cluster Subscription  (Argo CD projection; Git is source of truth)
OpenShellVersionPinSet 1—* AcceptanceStageResult (the upgraded platform is the system under test)
AcceptanceStageResult *—1 ImperativeStepRecord  (a stage's fix may require recorded steps)
```

## Invariants

1. **Pin atomicity**: OpenShell pin fields always hold one identical version (statically asserted).
2. **Review completeness**: ReviewDecision set ≡ `clusterGroup.subscriptions` key set.
3. **Evidence durability**: every decision/result record lives in Git under `specs/014-ocp501-openshell-upgrade/`.
4. **Zero residual**: at completion, no sandboxes, no port-forwards, no manual drift (FR-010).
