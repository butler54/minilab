---
description: "Task list for Reduce Minilab CPU Usage"
---

# Tasks: Reduce Minilab CPU Usage

**Input**: Design documents from `/specs/010-reduce-cpu-usage/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included — this repo has an established shell-based regression harness (`tests/`, `make test-static`).

**Organization**: Tasks are grouped by user story; each story lands as an independently verifiable increment per `quickstart.md` gates G0–G6.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1–US4)
- All file paths are repository-relative

## Path Conventions

- Scripts: `scripts/`
- Pattern values: `values-global.yaml`, `values-prod.yaml`
- Charts: `charts/<name>/`
- Tests: `tests/`
- Docs: `README.md`, `specs/010-reduce-cpu-usage/`

---

## Phase 1: Setup

**Purpose**: Safety snapshot and baseline so every change is reversible and measurable.

- [X] T001 Capture pre-change cluster snapshot for rollback reference: record current `ArgoCD/openshift-gitops` `resourceCustomizations` (expect absent), `ConfigMap/cluster-monitoring-config` (expect absent), and confirm the leaked `Application/agent-sandbox` + 4 tracked resources as an appendix to `specs/010-reduce-cpu-usage/ANALYSIS.md`
- [X] T002 [P] Verify repair preconditions per `specs/010-reduce-cpu-usage/contracts/repair-runbook-contract.md`: zero Sandbox CRs cluster-wide, CSV update-history empty, leaked app `syncPolicy: automated` — record pass/fail in ANALYSIS.md
- [X] T003 [P] Run baseline static gates and record results: `make lint-yaml`, `make test-static`, `make generate`, `make validate-schema`, `make validate-origin` — store output at `$TMPDIR/minilab-metrics/baseline-gates.log`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Deterministic test wiring — every subsequent story depends on the gates being trustworthy.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Unify Makefile test wiring so `make test-static` and `make validate-schema` execute the identical suite list (per plan.md Project Structure note); fix drift so `tests/test-external-refs.sh` and `tests/test-openshell-render.sh` are reachable from both targets in `Makefile`

**Checkpoint**: Gates run deterministically — story implementation can begin.

---

## Phase 3: User Story 1 — Stop the Reconciliation War (Priority: P1) 🎯 MVP

**Goal**: Delete the leaked ArgoCD `agent-sandbox` Application via a Git-recorded repair; CSV recovers to Succeeded with a clean 1-hour soak; one functional sandbox smoke test passes; a permanent owner-collision regression check guards against recurrence (FR-001).

**Independent Test**: Apply per `contracts/repair-runbook-contract.md`; pass gates G1 (CSV Succeeded, PUT/s < 0.02, zero immutable-selector events over 1h soak) plus `tests/test-owner-collision.sh` green and one successful sandbox instantiation.

### Tests for User Story 1

- [X] T005 [US1] Create `tests/test-owner-collision.sh` (FR-001 regression check): for each OLM CSV on the cluster, extract owned Deployment names and fail if any is also tracked by an ArgoCD Application (`tracking-id` annotation / app inventory); wire into `tests/test-static.sh` per existing precedence-based pattern (live-cluster probe, non-destructive). Run it now — it MUST fail, detecting the live `agent-sandbox-controller` collision
- [X] T006 [P] [US1] Create `tests/test-argocd-cadence.sh`: assert `values-global.yaml` sets `main.gitops.customArgoYaml` containing `timeout.reconciliation: 600s`; wire into `tests/test-static.sh`. Run — MUST fail until Phase 4
- [X] T007 [P] [US1] Create `tests/test-monitoring-config.sh`: assert `values-prod.yaml` has `clusterGroup.applications` entry `openshift-monitoring-config`, `charts/openshift-monitoring-config/templates/cluster-monitoring-config.yaml` exists with `collectionProfile: minimal` and all FR-013 retention/scrape fields, and `values-global.yaml` sets `global.observability.scrapeInterval: "60s"`; wire into `tests/test-static.sh`. Run — MUST fail until Phase 5

### Implementation for User Story 1

- [X] T008 [US1] Create `scripts/repair-agent-sandbox-leak.sh` per `contracts/repair-runbook-contract.md`: preconditions (zero Sandbox CRs, CSV update-history empty, automated sync policy), then `oc delete application agent-sandbox -n openshift-gitops`, postconditions (CSV recovers Succeeded, PUT rate drops, no finalizer orphans), idempotent re-run safe, explicit break-glass procedure ([Heuristic] if preconditions fail: stop and report)
- [X] T009 [US1] Execute `scripts/repair-agent-sandbox-leak.sh` against the live cluster; watch `csv/agent-sandbox-operator.v0.9.0` recover to `Succeeded` and olm-operator CPU subside ([Heuristic] if CSV does not reach Succeeded within 10m: halt, capture CSV status/events, escalate)
- [X] T010 [US1] Run G1 acceptance measurement 30m post-fix per quickstart.md: verify CSV `Succeeded` sustained, zero new immutable-selector events, CSV PUT rate < 0.02/s (`sum(rate(apiserver_request_total{group="operators.coreos.com",resource="clusterserviceversions",verb="PUT"}[5m]))`), `tests/test-owner-collision.sh` now green; append measurements to `specs/010-reduce-cpu-usage/ANALYSIS.md`
- [X] T011 [US1] Run the functional sandbox smoke test (FR-002/clarified): execute `deploy/openshell/demo/run-demo.sh --smoke` (Makefile `demo` target) against the repaired controller; verify one sandbox instantiates and the demo reports `OPENSHELL_VDEMO_OK`; record outcome in ANALYSIS.md ([Heuristic] if smoke fails but soak is clean: capture sandbox CR + controller events, do not roll back the repair)
- [X] T012 [US1] Commit repair script, owner-collision test, and ANALYSIS.md post-state on branch `010-reduce-cpu-usage`

**Checkpoint**: OLM hot loop eliminated (largest CPU win banked); US1 acceptance criteria AC1–AC5 met; plan checkpoint "smoke: N/A" is superseded (smoke test required per FR-002 clarification).

---

## Phase 4: User Story 2 — Slow Down the GitOps Driver (Priority: P2)

**Goal**: Set ArgoCD `timeout.reconciliation: 600s` via `main.gitops.customArgoYaml` in `values-global.yaml`, applied through the patterns-operator (`make operator-deploy`); manual sync remains immediate.

**Independent Test**: Wait >600s after apply; observe `.status.reconciledAt` refresh ages reach ≥600s, `argocd-application-controller` CPU steps down (G2), T006 green.

- [X] T013 [US2] Add `main.gitops.customArgoYaml` block to `values-global.yaml` (pattern-install chart 0.0.18 seam, research.md D3): set `timeout.reconciliation: 600s` plus optional app-controller `statusProcessors`/`operationProcessors` reduction with rationale comments; run `make generate` to confirm `pattern-install` renders the `patterns-operator-config` ConfigMap update
- [X] T014 [US2] Apply via `make operator-deploy` and restart/roll `argocd-application-controller` if the ConfigMap change is not picked up; hard-refresh `minilab-prod` and confirm `openshift-operators` Subscription transitions to Manual (FR-016 waits on US4 T024: keep approval Manual at apply time)
- [X] T015 [US2] Run G2 acceptance per quickstart.md: record restart time; verify observed refresh ages reach ≥600s; after 30m, record app-controller CPU (`sum(rate(container_cpu_usage_seconds_total{namespace="openshift-gitops",pod=~"argocd-application-controller.*",container="application-controller"}[10m])) by (pod) * 1000`) and manual-sync demo (touch a values comment, `make argo-sync`) in ANALYSIS.md; confirm T006 green
- [X] T016 [US2] Commit `values-global.yaml` and cadence test on branch `010-reduce-cpu-usage`

**Checkpoint**: GitOps baseline churn reduced at 600s (user-approved default 2026-10-09); `junit_operator_deploy.xml` artifact refreshed.

---

## Phase 5: User Story 3 — Reduce Monitoring Load (Priority: P3)

**Goal**: Ship `charts/openshift-monitoring-config` (cluster-monitoring-config with `collectionProfile: minimal` + homelab scrape/retention) and `global.observability.scrapeInterval: 60s` for pattern-owned scrape configs (SO5); platform Prometheus CPU drops ≥30% vs ~280m baseline.

**Independent Test**: After `make deploy`, wait 30m; verify `prometheus-k8s-0` CPU ≈200m or lower sustained (≥30% drop, G4) and all pre-existing dashboard panels still render (FR-007).

- [X] T017 [P] [US3] Create `charts/openshift-monitoring-config/` chart: `Chart.yaml` (version 0.1.0, kubeVersion >=1.29.0-0), `values.yaml` documenting every FR-013 tunable, `templates/cluster-monitoring-config.yaml` calling `common.capabilities…` shared helpers with blocks for `prometheusK8s` (collectionProfile minimal, retention 7d/10Gi, scrapeInterval 60s, evaluationInterval 60s, WAL compression, tolerations), `alertmanagerMain` retention 120h, `metricsServer` 5m, `telemeterClient` enabled per FR-013 default, node-exporter 1m/30s, kube-state-metrics 2m/2m, and `prometheusOperator` admission webhook disabled-by-default values block (FR-014 wizard note); render must match `contracts/monitoring-values-contract.md` invariants and FR-012 (stored `data/config.yaml`, no metadata merging)
- [X] T018 [P] [US3] Set `global.observability.scrapeInterval: "60s"` in `values-global.yaml` and update `charts/observability-config/templates/scrape-configs.yaml` so all generated scrapeInterval/evaluationInterval fields reference `.Values.global.observability.scrapeInterval` (G0 static gate); update node-exporter ServiceMonitor interval to `{{ .Values.global.observability.scrapeInterval }}`
- [X] T019 [US3] Register `openshift-monitoring-config` in `values-prod.yaml` `clusterGroup.applications` (path `charts/openshift-monitoring-config`), run `make generate` and inspect each generated `<app>-proj.json` for the appSources/placements additions per FR-018, then pass G3 static gates: `make lint-yaml`, `make test-static` (T007 green), `make generate`, `make validate-schema`
- [ ] T020 [US3] Apply via `make deploy` (git push + ArgoCD reconcile; manual sync acceptable during bring-up); run G4 acceptance 30m later per quickstart.md: `prometheus-k8s-0` CPU ≥30% below the 280m baseline (≈200m or lower sustained), dropped-coverage table matches live config, all pre-existing dashboard panels checked; record in ANALYSIS.md
- [ ] T021 [US3] Commit monitoring chart, values changes, and scrape-config updates on branch `010-reduce-cpu-usage`

**Checkpoint**: CMO-owned heavy metrics dropped with zero dashboard regressions; OCP console observe-stack untouched (FR-014).

---

## Phase 6: User Story 4 — Measure, Validate, Adjust (Priority: P1)

**Goal**: Confirm end-to-end observability still protects the cluster after all tuning, decide the once-per-cycle cadence adjustment, and record the superseding-cadence evidence (Goal 6 bump).

**Independent Test**: G5 (saturation alert channels green, node-exporter fresh, dashboards render) and G6 (30m post-G5 stability + recorded adjust decision).

- [ ] T022 [US4] Run G5 alert-channel validation per quickstart.md: confirm Alertmanager fires and notifies (Telegram path from analytics-mcp pattern, FR-008) for a heartbeat/test alert, `node-exporter` target freshness is one scrape interval, all `values-prod.yaml` dashboard URLs render; if a decided alert shows no value, apply the fallback to 30s and record the drop (FR-008 edge case)
- [ ] T023 [US4] Run G6 final observation window (30m after G5 acceptance): no new CrashLoopBackOff/Error across `openshift-operators`, `openshift-monitoring`, `external-secrets`, `openshift-gitops`, `node-exporter`; if node CPU still > 85% sustained 10m, open the incremental-adjust loop table (quickstart.md) and raise exactly one tier per cycle (600s → 900s/1800s → 3600s, 60s → 90s → 120s) recording decision + user approval; else record "no further reduction needed"
- [ ] T024 [US4] Ancillary review per FR-009: verify unseal cron 0/168h and OLM catalogs polling; record findings in ANALYSIS.md (explicitly noting "reviewed, no change" if true); execute the FR-016 decision — bump `openshift-pipelines` and `observability-operator` Subscriptions in `values-prod.yaml` to `installPlanApproval: Manual` (record as one-shot Goal 6 bump now that a full GitOps cycle is 10m); then confirm the next `make deploy` does not introduce new CSV churn via 15m `csv-*` events recheck

**Checkpoint**: All success criteria SC-001…SC-008 measured and recorded; cadence finalized or adjust loop opened.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T025 [P] Update `values-global.yaml` comment for `main.gitops.customArgoYaml` documenting the concurrency·interval tradeoff (research.md D3 math)
- [X] T026 [P] Document dropped/scaled monitoring coverage and rationale (FR-007, FR-013 decisions) as a "Dropped monitoring coverage" section in `README.md`, mirroring the table required by `contracts/monitoring-values-contract.md`
- [X] T027 [P] Update `tests/README.md` with the new test entries, including `tests/test-owner-collision.sh` (live-cluster probe semantics), and the Makefile target notes
- [ ] T028 [P] Append final post-state metrics appendix to `specs/010-reduce-cpu-usage/ANALYSIS.md` (before/after table for SC-001…SC-008)
- [X] T029 [P] Residual doc fixes from analyze: `data-model.md` E3 "scarfed"→"surfaced"; dedupe `ANALYSIS.md` row in `plan.md` Project Structure tree
- [ ] T030 Run full remaining static gates (`make lint`, `make kustomize` if harness reachable, `make super-linter` when network allows) and re-run every quickstart.md gate command end-to-end to confirm SC-001…SC-008, including the manual-sync confirmation that a trivial Git change lands within minutes (FR-005)
- [ ] T031 Run `make argo-healthcheck` final pass
- [ ] T032 Final commit and PR summary on branch `010-reduce-cpu-usage`: evidence table of SC outcomes + links to ANALYSIS.md appendix

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: After T001 (needs baseline reference)
- **US1 (Phase 3)**: After Foundational — **highest priority, unlocks everything** (other stories' CPU deltas are only separable after the fire is out, per plan.md dependency ladder)
- **US2 (Phase 4)**: After US1 measurement (T010) — strictly ordered per dependency ladder
- **US3 (Phase 5)**: After US2 measurement (T015) — strictly ordered
- **US4 (Phase 6)**: After US2+US3 applied (needs ≥1 full GitOps cycle known); G5/G6 consume their outputs
- **Polish (Phase 7)**: After all stories complete

### Within Each User Story

- Tests (T005–T007) written and confirmed failing (or failing-state verified) before implementation tasks
- Measurement/acceptance tasks (T010, T011, T015, T020, T022–T024) strictly after their apply tasks
- Commit task closes each story phase

### User Story Dependencies

- **US1 (P1)**: None — can start after Phase 1+2
- **US2 (P2)**: Depends on US1 G1 (CPU deltas must be attributable)
- **US3 (P3)**: Depends on US2 G2
- **US4 (P1)**: Depends on US1–US3 being applied; runs measurement-only plus the FR-016 bump

### Parallel Opportunities

- T002, T003 in parallel (different concerns, read-only)
- T006, T007 in parallel (different test files)
- T017, T018 in parallel (different charts/files)
- T025–T029 in parallel (different doc files)

---

## Parallel Example: User Story 1

```bash
# Write all three regression tests together (different files):
Task: T005 tests/test-owner-collision.sh
Task: T006 tests/test-argocd-cadence.sh
Task: T007 tests/test-monitoring-config.sh
# Then sequentially: T008 → T009 → T010 → T011 → T012 (live-cluster, strict order)
```

## Parallel Example: User Story 3

```bash
# Chart and observability-config edits in parallel (different files):
Task: T017 charts/openshift-monitoring-config/
Task: T018 charts/observability-config/templates/scrape-configs.yaml + values-global.yaml
# Then sequentially: T019 → T020 → T021
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (snapshot, preconditions, baseline)
2. Complete Phase 2: Foundational (test wiring determinism)
3. Complete Phase 3: US1 — repair + measure + smoke test + owner-collision check
4. **STOP and VALIDATE**: G1 green + smoke OK for a full 1-hour soak before touching cadence (per spec clarification, 24h tail excluded)
5. This MVP already recovers the largest CPU share (kube-apiserver 2706m + olm-operator 1458m targets)

### Incremental Delivery

1. Setup + Foundational → deterministic gates
2. US1 → fire out (checkpoint: CSV Succeeded, soak, smoke test) ← **MVP**
3. US2 → cadence 600s live (checkpoint: G2)
4. US3 → monitoring tuned (checkpoint: G4, ≥30% drop)
5. US4 → protection verified + adjusted (checkpoints: G5, G6)
6. Polish → docs + full gates + PR

### Notes

- Every phase ships committable Git state; cadence moves only one tier per observation cycle (FR-015, SC-008)
- Live-cluster mutation tasks (T009, T014, T020) are never parallelizable and require the snapshot from T001
- [P] tasks never share a file with another task in the same batch
