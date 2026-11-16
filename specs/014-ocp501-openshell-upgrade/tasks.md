# Tasks: OCP 5.0.1 Operator Review & OpenShell 0.1.x Upgrade

**Input**: Design documents from `/specs/014-ocp501-openshell-upgrade/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Acceptance testing is explicitly required by the spec (FR-007) — the acceptance stages are the test tasks, organized under User Story 3 per contracts/acceptance-suite.md.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

**Delivery**: Direct commits on `main`, each pushed as it becomes operative (Clarifications 2026-11-14). Commit after each task or logical group; Argo CD is the only convergence path (constitution I); every imperative action (forced sync, CLI install, installplan cleanup) is recorded in `specs/014-ocp501-openshell-upgrade/review-log.md` (constitution II).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This feature edits the pattern's Git surfaces (no `src/` tree): `values-global.yaml`, `values-prod.yaml`, `overrides/values-openshell-gateway.yaml`, `charts/`, `tests/`, `deploy/openshell/demo/`, and evidence artifacts under `specs/014-ocp501-openshell-upgrade/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify execution preconditions before any change lands.

- [x] T001 Verify preconditions and record them in the review-log preamble: cluster `oc get clusterversion` shows 5.0.1 Available; chart 0.1.8 pullable at `oci://ghcr.io/nvidia/openshell/helm-chart` (digest `sha256:39a56c77b78edd2a5c4ac7e17720b5720e1649e5e9f63743342a53940c01be81`); openshell CLI 0.1.8 installable; working tree clean on `main` and pushed
- [x] T002 Create `specs/014-ocp501-openshell-upgrade/review-log.md` skeleton per `specs/014-ocp501-openshell-upgrade/contracts/operator-review.md`: sections for the 7 per-subscription-key records (plus one observational note for the framework-managed patterns-operator subscription), upgrade evidence, acceptance evidence, imperative steps

**Checkpoint**: Preconditions hold; tracking artifact exists. If chart/CLI 0.1.8 unavailable → hold per spec edge case and stop.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared evidence baseline that every user story records into.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T003 Capture the 5.0.1 operator-hub catalog snapshot into `specs/014-ocp501-openshell-upgrade/review-log.md` evidence, dated: query the OLM v1 clustercatalogs (`oc get clustercatalog`, catalog content queries) for the 7 pattern-declared packages — the legacy `oc get packagemanifests` API is incomplete on 5.0.1, so use it only as a supplement — plus `oc get csv -A` / `oc get subscription -A` for installed state; for rhbk-operator (packagemanifest absent), record subscription conditions (`ResolutionFailed/ConstraintsNotSatisfiable`) and clustercatalog evidence as the fallback source

**Checkpoint**: Review source data recorded — user story implementation can begin.

---

## Phase 3: User Story 1 - Operator hub subscriptions reviewed and aligned to OCP 5.0.1 (Priority: P1) 🎯 MVP

**Goal**: Every pattern-managed operator healthy on a 5.0.1-compatible channel (or documented hold), with the review recorded in Git.

**Independent Test**: `yq` completeness check from contracts/operator-review.md passes; `oc get csv -A` shows lvms v5.0.0 and no `UpgradePending`/`ResolutionFailed` without a recorded HOLD; `make test-static` passes.

### Implementation for User Story 1

- [x] T004 [P] [US1] Record KEEP decisions with catalog evidence for eso, cert-manager, ztwim, agent-sandbox in `specs/014-ocp501-openshell-upgrade/review-log.md` (per-subscription-key record format; rationale from research.md §1 re-verified live), and add the observational note for the framework-managed patterns-operator subscription (no Git pin decision)
- [x] T005 [P] [US1] Update lvms subscription pin in `values-prod.yaml`: `clusterGroup.subscriptions.lvms-operator.channel` → `stable-5.0`, `csv` → `lvms-operator.v5.0.0`
- [x] T006 [P] [US1] Update `global.lvmsCompatibility` in `values-global.yaml`: channel `stable-5.0`, startingCSV `lvms-operator.v5.0.0`, `ocpRelease` → `5.0` (major.minor, matching the channel), `cliImage` → OCP 5.0 payload digest, discovered via `oc adm release info --image-for=cli` against the 5.0 payload and independently verified in the rendered chart (do not keep the 4.22 `ocp-v4.0-art-dev@sha256:84b0aa6...` digest)
- [x] T007 [P] [US1] Update assertions in `tests/test-lvms-ordering.sh`: channel/CSV/ocpRelease expectations and the rendered-config digest/CSV strings (keep the equality assertions between values-prod and values-global intact); verify the rendered LVMCluster against the 5.0 API with a server-side dry run (`oc apply --dry-run=server -f <rendered>`) or an equivalent CRD schema check
- [x] T008 [US1] Switch `clusterGroup.subscriptions.cluster-observability-operator.installPlanApproval` from `Manual` to `Automatic` in `values-prod.yaml`, in the same commit as the cluster-observability review record from T004 (FR-011 — the channel stays `stable`; only the approval mode changes)
- [x] T009 [US1] Resolve the RHBK finding in `specs/014-ocp501-openshell-upgrade/review-log.md` + `values-prod.yaml`: enumerate what the 5.0.1 catalogs serve for `rhbk-operator` (clustercatalog `openshift-redhat-operators` contents / Red Hat docs for the 5.0-era RHBK package+channel); update `clusterGroup.subscriptions.rhbk.channel` accordingly, or record a HOLD citing the `ResolutionFailed/ConstraintsNotSatisfiable` evidence and the healthy installed CSV v26.6.9-opr.1
- [x] T010 [US1] Run static gates and record outcomes: `make test-static` and `./pattern.sh make validate-schema` (this run is superseded for evidence purposes by T021's authoritative acceptance run)
- [x] T011 [US1] Commit the operator changes to `main` and push; if convergence needs a nudge, perform one forced Argo CD refresh/sync and record it (command + output) in the imperative-steps section of `specs/014-ocp501-openshell-upgrade/review-log.md`
- [x] T012 [US1] Verify and record convergence in `specs/014-ocp501-openshell-upgrade/review-log.md`: all subscriptions `AtLatestKnown` (or documented HOLD), lvms CSV `v5.0.0` Succeeded, cluster-observability upgraded past v1.5.3 (or hold recorded), no unapproved installplans stuck

**Checkpoint**: Operator layer aligned to 5.0.1 and review artifact complete — US1 independently testable via the quickstart Scenario 1 checks.

---

## Phase 4: User Story 2 - OpenShell platform upgraded to the latest 0.1.x release via GitOps (Priority: P1)

**Goal**: All openshell pins (chart, 3 image tags, CLI) at 0.1.8, converged by Argo CD, with demo drivers compatible with 0.1.8 behavior.

**Independent Test**: `make check-openshell-cli` passes unmodified; gateway pod image tag is 0.1.8; `openshell status -g k8s` succeeds; Argo CD openshell applications Synced+Healthy (quickstart Scenario 2).

### Implementation for User Story 2

- [x] T013 [P] [US2] Audit and remediate release-flagged 0.1.8 behavior deltas (FR-012, contract deltas 1–5) in `deploy/openshell/demo/` (run-demo.sh, zen/run-zen-demo.sh) and any policy files they reference: no filesystem policy path traversing a symlink inside a writable workspace, no IPv4-mapped IPv6 endpoint hosts (`::ffff:a.b.c.d` → plain IPv4), WebSocket flows need explicit `protocol: websocket` rules, scripts using `openshell status --gateway` expect non-zero exit for unregistered gateways; also re-test `gateway.ocsfLog.enabled` on 0.1.8 (dead value at 0.1.3, upstream #3264/#3876) and update the comment in `overrides/values-openshell-gateway.yaml`
- [x] T014 [P] [US2] Update `clusterGroup.applications.openshell.chartVersion` from `"0.1.3"` to `"0.1.8"` in `values-prod.yaml`
- [x] T015 [P] [US2] Update the three image tags (gateway, sandboxRuntime, supervisor) from `"0.1.3"` to `"0.1.8"` in `overrides/values-openshell-gateway.yaml`; keep the digest-pinned sandbox base image untouched
- [x] T016 [P] [US2] Update the expected openshell version in `tests/test-openshell-pins.sh` (0.1.3 → 0.1.8); do not touch the agent-sandbox `preview-0.9` assertions
- [x] T017 [US2] Teardown before upgrade using an idempotent, recorded procedure (list sandboxes/forwards, delete/close, repeat until `openshell sandbox list` is empty — constitution II automation requirement), and record the pre-upgrade zero-residual state in `specs/014-ocp501-openshell-upgrade/review-log.md`
- [x] T018 [US2] Update the workstation CLI: `make install-openshell-cli` (installs 0.1.8 from the chart pin), run `openshell gateway login` once to replace pre-0.1.8 token files, confirm `make check-openshell-cli` passes unmodified; record the CLI install and gateway login in the imperative-steps section of `specs/014-ocp501-openshell-upgrade/review-log.md`
- [x] T019 [US2] Run pre-push gates and fix any 0.1.8 value-schema fallout in `overrides/values-openshell-gateway.yaml`: `make validate-openshell`, `make test-static`, `./pattern.sh make validate-schema`
- [x] T020 [US2] Commit the pin change to `main` and push; record any forced sync in `specs/014-ocp501-openshell-upgrade/review-log.md`; verify and record: gateway pod image tag 0.1.8, all openshell Argo CD applications Synced+Healthy within 15 minutes, `openshell status -g k8s` succeeds

**Checkpoint**: Platform at 0.1.8 with CLI parity — US2 independently testable via the quickstart Scenario 2 checks.

---

## Phase 5: User Story 3 - Acceptance testing verifies expected OpenShell behavior post-upgrade (Priority: P2)

**Goal**: Recorded evidence that the upgraded platform behaves as expected, per contracts/acceptance-suite.md.

**Independent Test**: All 7 acceptance stages pass (or `fail→fixed→pass` / `fail→documented`) with results in review-log.md; demo smoke runs with NO skip message; zero residual state at the end.

### Tests for User Story 3 (the acceptance suite — FR-007)

- [x] T021 [P] [US3] Run and record stages 1–3 in `specs/014-ocp501-openshell-upgrade/review-log.md`: `make test-static && make validate-openshell`, `./pattern.sh make validate-schema`, `make check-openshell-cli` (this is the authoritative gate evidence; it supersedes the per-story runs T010/T019)
- [x] T022 [P] [US3] Run and record stage 4 (convergence): `make argo-healthcheck && make validate-cluster` — all applications Synced+Healthy, zero OutOfSync, OLM no-op PUT posture unchanged from the 010 baseline (<1/s)
- [x] T023 [US3] Run and record stage 5 (auth smoke): `make validate-openshell-live` — Keycloak OIDC login + gateway status end-to-end; a skip counts as FAIL (FR-008)
- [x] T024 [US3] Run and record stage 6 (demo smoke): `DEMO_PROMPT="Reply with exactly: OPENSHELL_VDEMO_OK" make validate-openshell-demo` — must run (no cluster-unreachable/auth-missing skip), expected prompt exchange succeeds, clean teardown
- [x] T025 [US3] Run and record stage 7 (sandbox lifecycle): create a sandbox with policy supplied at create (feature-012 mechanism), verify the policy is effective from the first operation (allowlisted egress succeeds / non-allowlisted denied), delete via the same idempotent recorded teardown procedure as T017, confirm `openshell sandbox list` empty
- [x] T026 [US3] Handle any failure per FR-008 and the decided rollback policy: fix in Git + re-run to green, or document root cause with upstream reference in `specs/014-ocp501-openshell-upgrade/review-log.md`; revert the 0.1.8 pin on `main` only if the platform is unusable (auth or sandbox lifecycle broken)

**Checkpoint**: All acceptance evidence recorded — US3 independently testable via the quickstart Scenario 3 checks.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final verification and artifact closure.

- [x] T027 Verify review-artifact completeness per `specs/014-ocp501-openshell-upgrade/contracts/operator-review.md`: the `yq`/`grep`/`diff` check shows every `values-prod.yaml` subscription key has exactly one record in `specs/014-ocp501-openshell-upgrade/review-log.md`
- [x] T028 Run the full `specs/014-ocp501-openshell-upgrade/quickstart.md` validation (all three scenarios + completion check); any discrepancy fixed or documented
- [x] T029 Final zero-residual + closure: `openshell sandbox list` empty, no port-forwards, `oc get subscription -A` clean (or holds recorded), zero Argo CD applications OutOfSync (`make argo-healthcheck` / `argocd app diff` clean — the drift criterion of SC-005); update `specs/014-ocp501-openshell-upgrade/spec.md` Status from Draft to Implemented; final commit and push of evidence to `main`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **User Stories (Phase 3–5)**: All depend on Phase 2
  - US1 (operators) and US2 (openshell pins) are Git-independent and could interleave, but **execute US1 first**: the spec makes the operator layer the validation baseline for OpenShell testing, and the RHBK outcome (Keycloak backs openshell auth) must be known before the acceptance run
  - US3 depends on US1 AND US2 (it tests the upgraded platform on the aligned operator layer)
- **Polish (Phase 6)**: Depends on all user stories complete

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2 — no dependencies on other stories
- **US2 (P1)**: Starts after Phase 2 — sequencing after US1 is a decision, not a code dependency (different files except `values-prod.yaml`, which both touch: T005/T008 vs T014 — land as separate commits)
- **US3 (P2)**: Depends on US1 + US2 completion (system under test is their product)

### Within Each User Story

- Pin-value edits before their asserting test edits (or same commit)
- Pre-push gates (T010, T019) before push tasks (T011, T020)
- Acceptance stages run in order; failure handling (T026) after any stage fails

### Parallel Opportunities

- T004–T007 (different files: review-log, values-prod, values-global, tests) can run in parallel; T008 follows T005 (same file)
- T013–T016 (demo dir, values-prod, overrides, tests) can run in parallel — but T014 lands in a separate commit from T005/T008
- T021–T022 (static/convergence stages) can run in parallel; T023–T025 are sequential live stages

---

## Parallel Example: User Story 2

```bash
# Launch pin edits together (different files):
Task: "Update chartVersion in values-prod.yaml"        (T014)
Task: "Update image tags in overrides/values-openshell-gateway.yaml" (T015)
Task: "Update expected version in tests/test-openshell-pins.sh"      (T016)
Task: "Audit demo drivers in deploy/openshell/demo/"   (T013)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (preconditions verified)
2. Complete Phase 2: Foundational (catalog snapshot)
3. Complete Phase 3: US1 — operator layer aligned and reviewed
4. **STOP and VALIDATE**: quickstart Scenario 1 — review completeness, pins, convergence
5. The lab is already safer (storage/operator layer matched to the platform) even before OpenShell moves

### Incremental Delivery

1. Setup + Foundational → evidence baseline ready
2. Add US1 → validate independently → operator layer aligned (MVP!)
3. Add US2 → validate independently → platform at 0.1.8
4. Add US3 → validate independently → behavior verified with recorded evidence
5. Polish → artifacts closed, spec status updated

### Parallel Team Strategy

Single-operator lab: execute sequentially (US1 → US2 → US3), using intra-story parallelism only for file-disjoint edits.

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Every push to `main` becomes operative immediately (Argo CD convergence) — keep commits small and revertible
- Every imperative action (forced sync, CLI install, installplan cleanup, teardown) MUST be recorded in `review-log.md` imperative steps (constitution II)
- Do not weaken or skip any acceptance check (FR-008); the demo target's built-in skip conditions count as FAIL during acceptance
- Stop at any checkpoint to validate the story independently

---

## Phase 7: Convergence

**Purpose**: Close the gaps found by `/speckit.converge` between spec.md/plan.md/tasks.md and the present code+cluster state (appended 2026-11-16; existing tasks unmodified). Ordered by severity.

- [x] T030 Resolve the persistent root-application drift and correct its record: re-apply the four stale child Application CRs (`observability-config`, `openshell-demo`, `openshell-policy`, `vault`) from the root app's 5.0 render with an Argo-driven selective sync of the root's `Application` resources (no `oc apply` of desired state), record the step (command, rationale, result, reconcile-back) in the imperative-steps table, verify `oc get applications -n vp-gitops` reports zero OutOfSync, and replace the review-log's "cosmetic / empty diff / self-resolves on next Git change" narrative with the verified cause — live child specs carry `global.clusterVersion: 4.22` while `minilab-prod` renders 5.0 per FR-010/SC-005 (contradicts)
- [x] T031 Measure and record the OLM no-op copy-status PUT rate for acceptance stage 4 from platform Prometheus (target <1/s against the 010 baseline 0.21/s) alongside the existing `disableCopiedCSVs=true` evidence, or record `fail→documented` with the attempted query and substitute evidence per the stage-4 pass criteria in `specs/014-ocp501-openshell-upgrade/contracts/acceptance-suite.md` (partial)
- [x] T032 Complete the imperative-steps table in `specs/014-ocp501-openshell-upgrade/review-log.md` with the actions currently recorded only in prose: the 0.1.8 CLI install via the GitHub-release fallback, the `openshell gateway login` device flow, the stale duplicate `minilab-prod` Application deletion in `openshift-gitops`, and the orphaned Completed sandbox pod deletion — each with action, rationale, result, and reconcile-back per T018 and constitution II (partial)
- [x] T033 Run and record the consolidated `specs/014-ocp501-openshell-upgrade/quickstart.md` validation — Scenario 1 (review-completeness diff, lvms/coo pins, CSV and subscription states), Scenario 2 (atomic 0.1.8 pin set, CLI version, gateway pod image, `openshell status -g k8s`), Scenario 3 (stage roll-up), and the completion-check block — in a dedicated section of `review-log.md`, fixing or documenting any discrepancy per T028 (partial)
- [x] T034 Record explicit no-op determinations for the two 0.1.8 release deltas still missing from the delta audit: delta 1 (OCSF is 1.8.0-only with `device.container.*`/`resources[]` attribution — confirm no repo script or evidence parser reads OCSF output) and delta 7 (faster Kubernetes sandbox teardown — confirm no teardown procedure in `deploy/openshell/demo/` or the recorded procedures assumes the old ~30s grace delay) per FR-012 and the 0.1.8 behavior-delta table in `contracts/acceptance-suite.md` (partial)
- [x] T035 Extend `tests/test-lvms-ordering.sh` to assert the rendered `charts/lvms-config` readiness Job references `global.lvmsCompatibility.daemonSet` and that `charts/lvms-config/templates/readiness-netpol.yaml` renders the API (TCP 6443) and `openshift-dns` (5353 TCP/UDP) egress rules, so the convergence-era readiness-hook fix is regression-guarded by `make test-static` rather than only surfacing on-cluster per T007 and FR-009 (partial)
- [x] T036 Declare the `daemonSet` (and `channel`) placeholders in `charts/lvms-config/values.yaml` under `global.lvmsCompatibility` alongside `cliImage`/`startingCSV`/`deployment`/`lvmClusterCRD`, so the chart's declared value surface matches the templates' `required` lookups introduced by the readiness-job fix (partial)
- [x] T037 Re-run the validation gates after T030–T036 and record the outcome in `specs/014-ocp501-openshell-upgrade/review-log.md`: `make test-static`, `./pattern.sh make validate-schema`, and the convergence check (`oc get applications -n vp-gitops` zero OutOfSync; `make argo-healthcheck` remaining failure limited to the documented rhbk hold), confirming FR-009/SC-005 in the post-convergence state (partial)

---

## Phase 8: Convergence

**Purpose**: Close the single gap found by the second `/speckit.converge` pass against spec.md/plan.md/tasks.md and the present code+cluster state (appended 2026-11-16; existing tasks unmodified). Documentation-only — no values, chart, or test change.

- [x] T038 Complete T030's "replace the narrative" criterion in the acceptance record: in `specs/014-ocp501-openshell-upgrade/review-log.md` the Stage 4 (`convergence`) entry still carries the superseded pre-T030 root cause — "(b) sync **OutOfSync** display on 4 child Application CRs … `argocd app diff` shows an empty diff … a status artifact of the interrupted sync operations … (b) is cosmetic and self-resolves on the next completed root sync" — while the same file records the verified cause (the four children were pinned at `global.clusterVersion: 4.22` behind the rhbk-stalled sync waves and were fixed by the selective Argo sync of T030). Rewrite that entry so the stage's `fail→documented` outcome rests solely on the documented rhbk upstream hold, citing the T030 finding for the resolved drift; then re-verify the remainder of the acceptance-evidence section against live state (`oc get applications -n vp-gitops` → 18/18 Synced; root `minilab-prod` Synced with health Degraded from `Subscription/rhbk-operator`; `openshell sandbox list` / `openshell forward list` against the recorded zero-residual note) so no other superseded conclusion remains in the FR-007/SC-004 evidence record (partial — T030 replacement applied only in the "Known display artifacts" bullet, not in the acceptance section)
