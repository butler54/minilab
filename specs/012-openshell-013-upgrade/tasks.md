# Tasks: Upgrade OpenShell Stack to 0.1.3

**Input**: Design documents from `/specs/012-openshell-013-upgrade/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Organization**: Tasks grouped by user story (US1 platform upgrade P1; US2 CLI parity P1; US3 policy-at-create P2). All commits land DIRECTLY on `main` (Clarifications 2026-10-13). All live phases batch tightly around gateway token lifetime (minilab#9).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1/US2/US3)
- Live tasks marked **\[LIVE\]** touch the cluster/gateway (need fresh auth); batch them

---

## Phase 1: Setup

**Purpose**: Tracking artifact and environment readiness

- [X] T001 Create the feature evidence log at `specs/012-openshell-013-upgrade/demo-log.md` with tables mirroring the 011 format (run table: run/mode/sandbox/create→ready/fence/query/deny-proofs/teardown/notes; timing table; merge/close record) and header referencing issue butler54/minilab#8; commit to `main`
- [X] T002 Environment readiness check: `oc whoami` = kube:admin, `oc -n vp-gitops get applications | grep openshell` shows current state, `helm version` present; record baseline (`openshell-0` pod image tag `0.1.1`, apps Synced/Healthy pre-change) in `specs/012-openshell-013-upgrade/demo-log.md`
- [X] T003 Pre-edit static baseline: run `make test-static` and capture PASS in demo-log (existing state is green from T027 of 011); run `openshell gateway list` and note current gateway `k8s`

---

## Phase 2: Foundational

**Purpose**: Atomic pin bump committed and pushed — the ONLY shared dependency of every later phase

**⚠️ CRITICAL**: US1's sync, US2's CLI, and US3's validation all require this on `main` first

- [X] T004 Edit the 5-version pin surface atomically: `values-prod.yaml` (`clusterGroup.applications.openshell.chartVersion` 0.1.1→0.1.3, line ~190), `overrides/values-openshell-gateway.yaml` (three image tags lines 13/16/19 → "0.1.3"), `tests/test-external-refs.sh` (expected openshell chartVersion → "0.1.3", line ~53), `tests/test-openshell-pins.sh` (`OSC_VER = "0.1.3"`, line ~42), `tests/test-openshell-render.sh` (`OSC_VER = "0.1.3"`, line ~50). DO NOT touch `values-ztwim.yaml`, `rh-keycloak` 0.1.0, or historical attribution comments in policy files
- [X] T005 Run pre-push gates: `make test-static` (all suites green incl. updated pin assertions) AND `./pattern.sh make validate-schema` (`All assertions passed`); fix any render incompatibility against chart 0.1.3 values before proceeding — the values diff is additive (research.md R2) so failures indicate our override problem, not upstream
- [X] T006 Commit all 5 files as ONE commit on `main` with message documenting the five-value atomicity, and `git push origin main`; record commit SHA in `specs/012-openshell-013-upgrade/demo-log.md`

**Checkpoint**: pin commit is on `main`; no live change yet

---

## Phase 3: User Story 1 - Platform stack converged at 0.1.3 (Priority: P1)

**Goal**: Argo CD drives the cluster to 0.1.3; gateway healthy at new version

**Independent Test**: `oc -n vp-gitops get applications | grep openshell` all Synced+Healthy; gateway pod image tag == 0.1.3 (contracts/README U1)

- [X] T007 [US1] **\[LIVE\]** Record-and-run the imperatively-triggered sync (already documented in `quickstart.md` G2 — constitution II pre-recording satisfied): `oc -n vp-gitops annotate application/openshell argocd.argoproj.io/refresh=hard` then `oc -n vp-gitops patch application/openshell --type=merge -p '{"operation":{"sync":{"prune":false}}}'`; record the commands and timestamp in demo-log
- [X] T008 [US1] **\[LIVE\]** Watch convergence: poll `oc -n vp-gitops get applications | grep openshell` every ~30s for ≤15 min; capture terminal state (all Synced+Healthy); record convergence wall-time for SC-001 in demo-log (FAIL-safe: if unhealthy >15 min, execute spec rollback — `git revert` T006 commit on `main`, re-sync, record, and stop the feature here)
- [ ] T009 [US1] **\[LIVE\]** Verify the running gateway: `oc -n openshell get pod openshell-0 -o jsonpath='{.spec.containers[0].image}'` shows `ghcr.io/nvidia/openshell/gateway:0.1.3`; `openshell status -g k8s` = Connected+Authenticated (fresh login: `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` if lapsed); record SC-002 evidence in demo-log
- [X] T010 [US1] **\[LIVE\]** Health spot-check: `oc -n openshell get pods`, ensure supervisor/sandbox-runtime workloads clean with no new CrashLoops; `oc -n vp-gitops get applications | grep -vE 'Synced.*Healthy'` shows ONLY the pre-existing `lvms-config` OutOfSync (010 deferred incident — do NOT touch); record in demo-log

**Checkpoint**: US1 complete — platform at 0.1.3 serving normally (SC-001, SC-002)

---

## Phase 4: User Story 2 - Workstation CLI parity (Priority: P1)

**Goal**: Workstation CLI at 0.1.3 with repo tie-check green (contract U1 cli portion)

**Independent Test**: `openshell --version` prints 0.1.3; `make check-openshell-cli` PASS (SC-003)

- [X] T011 [US2] `brew unlink openshell` (recorded, reversible via `brew link`; reason: brew formula lags at 0.1.1 and `/opt/homebrew/bin` shadows `~/.local/bin` per research.md R3) — record in demo-log
- [X] T012 [US2] Run `make install-openshell-cli` (Makefile upstream-installer fallback: `OPENSHELL_VERSION=v0.1.3` into `~/.local/bin`; auto-verifies via `tests/check-openshell-cli.sh`); assert `openshell --version` = 0.1.3 and `make check-openshell-cli` green; record SC-003 in demo-log (FAIL-safe: if the installer payload mismatches the expectation, restore `brew link openshell`, record hold, escalate issue #8)

---

## Phase 5: User Story 3 - Policy-at-create validated + adopted (Priority: P2)

**Goal**: Contract U2 proven live (policy active from birth); demo scripts adopt it; U3 regression guard passed

**Independent Test**: quickstart G4 assertions (admission accepted + policy_version ≥1 at birth WITHOUT any `policy set` call) and G5 smoke PASS (SC-004, SC-005)

- [ ] T013 [US3] **\[LIVE\]** Fresh gateway login, then execute contract U2 core: `SB=fix013-$(date +%s); openshell sandbox create --name "$SB" --policy charts/openshell-policy/policies/zen-demo.yaml --from ghcr.io/butler54/openshell-sandbox:latest --detach`; **before any other command touching the sandbox**, run `openshell sandbox get "$SB" -o json` and record `admission` and `policy_version`; assertion 1: `accepted` + `policy_version >= 1`. Save full sandbox JSON to demo-log (SC-004)
- [ ] T014 [US3] **\[LIVE\]** First-op policy proof on the SAME sandbox (still zero `policy set` calls): `openshell sandbox exec -n "$SB" -- curl -m 8 https://github.com` → expect deny via sinkhole `Immediate connect fail for 198.18.0.x: Permission denied` (deny-all policy active from birth); record assertion 2 evidence in demo-log; also record Ready-from-create wall time (target ≤5 min) and confirm zero `ConfigurationInvalid` in sandbox conditions JSON
- [ ] T015 [US3] **\[LIVE\]** Iterative-loop retention check on the same sandbox: `openshell policy set "$SB" --policy charts/openshell-policy/policies/zen-demo.yaml -w` → policy version increments and command succeeds (remediation-loop path intact for 011 US2 narratives); then delete sandbox and verify `openshell sandbox list -g k8s` returns empty; record U2 verdict (PASS or fail-classification) and the exact `openshell` version (0.1.3 vs 0.1.1-behavior parity note) in demo-log
- [ ] T016 [US3] If T013–T014 PASS: edit `deploy/openshell/demo/zen/run-zen-demo.sh` — remove the concurrent create+policy-set fast loop from setup; create with `openshell sandbox create --name "$SANDBOX" --from "$IMAGE" --policy "$POLICY" --detach` (fall back to legacy loop on a CLI create-rejection of `--policy` for backward safety); keep every post-create iterative `policy set` invocation in query/proof flows untouched; `bash -n` check, `make test-static` green
- [ ] T017 [US3] If T013–T014 PASS: same adoption in the 008 smoke driver `deploy/openshell/demo/run-demo.sh` (policy-at-create for its initial policy, iterative sets preserved); `bash -n` + static gates green. If T013–T014 FAIL instead: skip T016/T017, and instead write the failure root-cause + upstream reference into `specs/012-openshell-013-upgrade/demo-log.md` and `docs/openshell-demo-opencode.md` (contract U2 failure-response path)
- [ ] T018 [US3] Commit T016+T017 changes to `main` (or the FAILURE documentation from T017-alt) and `git push origin main`
- [ ] T019 [US3] **\[LIVE\]** Full zen smoke regression: `SKIP_FENCE_WAIT=1 ./deploy/openshell/demo/zen/run-zen-demo.sh --smoke` — expect create→Ready, inject PASS, query produces `ZEN_HI_OK` (re-probe model lineup if DR2 rotated; fix `deploy/openshell/demo/zen/opencode-zen.json` model if needed, commit separately with evidence), 5/5 deny proofs, teardown+empty list (SC-005); if FIRST smoke run uses policy-at-create path, note behavior parity vs 011 R4 in demo-log
- [ ] T020 [US3] Optional (only if free, else comment-deferred): enable `gateway.ocsfLog.enabled: true` in `overrides/values-openshell-gateway.yaml` to restore the OCSF deny-evidence channel (research.md R2), commit+push, resync openshell app, and confirm `oc logs openshell-0 -n openshell` shows OCSF JSONL writes; if ANY friction, revert immediately and note for follow-up

**Checkpoint**: SC-004 + SC-005 recorded; issue #8's core question (policy-at-create works) has a live-verified answer

---

## Phase 6: Polish & Cross-Cutting

**Purpose**: Evidence, docs, issue closure, residual checks

- [ ] T021 Update `docs/openshell-demo-opencode.md`: refresh "0.1.1" version references to 0.1.3 where they describe current state, note policy-at-create adoption (+ minilab#8 resolution), add the sync/force-refresh procedure pointer; commit + push `main`
- [ ] T022 [P] Append a forward-reference one-liner to `specs/011-zen-sandbox-demo/demo-log.md` FI1 note pointing at 012's live resolution (011 history stays immutable otherwise); commit + push
- [ ] T023 [P] Comment on butler54/minilab#8 with the outcome: U2 verdict (policy-at-create live-verified with evidence lines from demo-log), 0.1.3 convergence date/times, and residual follow-up if T020 was deferred; CLOSE issue #8 if U2/U3 PASS, else keep open with findings
- [ ] T024 Final residual + gates sweep: `openshell sandbox list -g k8s` empty, `openshell forward list` empty, `openshell sandbox list` guard for no stray fwd procs (`pgrep -fl "forward service" || true`), `oc -n vp-gitops get applications | grep -vE 'Synced.*Healthy'` only `lvms-config` OutOfSync, `make test-static` and `./pattern.sh make validate-schema` green; fill all demo-log timing tables and SC-001..SC-006 verdicts; commit + push
- [ ] T025 Update `specs/012-openshell-013-upgrade/tasks.md` to mark every task `[X]` as completed, and record final close status in demo-log; commit + push (SC-006)

**Checkpoint**: feature 012 complete on `main` with zero residual; issue #8 dispositioned

---

## Dependencies

```text
Phase 1 (Setup) → Phase 2 (atomic pin commit, GATE)
  → Phase 3 (US1 sync, LIVE) → Phase 4 (US2 CLI)
    → Phase 5 (US3 policy-at-create validation + adoption + smoke, LIVE)
      → Phase 6 (polish)
```

- T004–T006 (one atomic commit on `main`) blocks everything downstream — Argo CD only converges `main`
- T013 must precede T016/T017 (scripts only adopt a proven mechanism)
- T011/T012 (US2) must precede T013 (CLI 0.1.3 does the create-policy validation, matching server/chart 0.1.3)
- T019 depends on T016/T017 (smoke exercises the modified scripts)

## Parallel Execution

- T002 and T003 (Phase 1) are independent of each other
- T021, T022, T023 (Phase 6 docs) are independent of each other → [P] marked
- All LIVE phases run sequentially on one terminal: single cluster + one auth session; batch per minilab#9 token lifetime

## Suggested MVP Scope

**MVP = Phases 1–4** (US1+US2): platform and CLI at 0.1.3 with convergence proof. US3 is the contract-validation layer that can land as its own increment immediately after (same session if token lifetime permits).

## Validation Strategy

- Contract U1/U2/U3 assertions per `contracts/README.md`
- Live evidence in `specs/012-openshell-013-upgrade/demo-log.md` (mirrors 011 format)
- Quickstart G0–G6 gates; SC-001..SC-006 outcomes recorded in demo-log
- Regression guard: `make test-static` + `./pattern.sh make validate-schema` before ANY push
