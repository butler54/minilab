---

description: "Task list for 011 zen sandbox demo + server mode"
---

# Tasks: Zen Sandbox Demo and Server Mode

**Input**: Design documents from `/specs/011-zen-sandbox-demo/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/zen-demo-assets.md, quickstart.md

**Tests**: Static validation assets (`tests/test-zen-policy.sh`) and live acceptance gates (quickstart G0–G6) are first-class demo deliverables per spec FR-008/SCs — included below, built alongside the assets they verify.

**Organization**: US1 (P1, CLI deploy) → US2 (P1, zen hi + remediation) → US3 (P2, server mode). US2 builds on US1's sandbox lifecycle; US3 builds on US2's healthy sandbox+model path (expected: same sandbox session).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1/US2/US3 per spec.md; setup/foundational/polish phases unlabeled

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffolding for the demo asset family (mirrors 008 layout)

- [X] T001 Create `deploy/openshell/demo/zen/` directory and `specs/011-zen-sandbox-demo/demo-log.md` with run-table header (timestamps, mode, policy iterations, transcripts, deny proofs, teardown)
- [X] T002 [P] Verify openshell CLI pin (`make check-openshell-cli`) and document result in demo-log; if mismatched, `make install-openshell-cli` then re-verify
- [X] T003 [P] Create `deploy/openshell/profiles/zen.yaml` modeled on `deploy/openshell/profiles/matilda.yaml` (zen provider profile, credential placeholder `ZEN_API_KEY`, `auth_style: bearer`, endpoint TBD-by-T005, `protocol: rest`)

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Research-spike resolutions (G0) that every story's assets depend on

**⚠️ CRITICAL**: No user-story script work begins until T004–T008 are committed

- [X] T004 Zen keyless probe: attempt a zen `*-free` chat completion anonymously (no bearer) from the workstation; record the exact accept/reject signal in demo-log (research D1). If rejected with actionable detail (e.g. session-id requirement, 401-on-bearer), capture the response verbatim
- [X] T005 Resolve zen endpoint + free model identity from `https://models.opencode.ai/api.json` and the zen endpoint probe; finalize `deploy/openshell/demo/zen/opencode-zen.json` (contract Z1: strict JSON, `provider/model-id` form, single host, no secrets) and backfill the T003 profile endpoint
- [X] T006 If T004 shows keyless fails: document the free zen API key path — add `openshell-zen` seed to `values-secret.yaml.template` (contract Z6), note the manual `opencode.ai/auth` step in `docs/openshell-demo-opencode.md`-adjacent runbook notes, and switch `opencode-zen.json` to `{env:ZEN_API_KEY}`
- [X] T007 Gateway transport spike: check openshell 0.1.1 for any sandbox TCP-forward capability (`openshell sandbox connect --help`, `openshell --help`, gateway docs); record verdict in demo-log per contract Z4 (gateway path viable vs `oc port-forward` fallback engaged)
- [ ] T008 Binary-path probe: short-lived probe sandbox from the 008 carrier image; `readlink -f $(which curl node opencode)` inside; confirm `/usr/bin/curl`, `/usr/bin/node`, `/usr/lib/node_modules/opencode-ai/bin/opencode.exe` (update if drifted); delete probe sandbox
- [X] T009 Seed `charts/openshell-policy/policies/zen-demo.yaml` from the 008 openai-only sample shape (`version: 1`, filesystem_policy carried over, empty `network_policies` with a header comment stating deny-all-default + justification-comment convention per contract Z2)
- [X] T010 [P] Write `tests/test-zen-policy.sh` enforcing contract Z1/Z2 statically (strict JSON, zero secret material, `provider/` prefix on model, per-rule `endpoints`+`binaries` non-empty, `protocol: rest` on HTTP endpoints, `# justification:` comment on every rule, no wildcards/duplicate host:port); wire it into the Makefile `test-static` enumeration; verify green on the T009 seed

**Checkpoint**: G0 spike answers committed; asset skeletons in Git; static guard green

---

## Phase 3: User Story 1 - Deploy a governed sandbox from the workstation CLI (Priority: P1) 🎯 MVP

**Goal**: One scripted path authenticates, creates, and verifies a surviving Ready sandbox

**Independent Test**: Run the driver from a clean terminal; sandbox reaches Ready, lives past the fence window, and `openshell sandbox list` shows it healthy (quickstart G2)

- [ ] T011 [US1] Write `deploy/openshell/demo/zen/run-zen-demo.sh` adapted from `deploy/openshell/demo/run-demo.sh`: preflight (CLI pin + `openshell status -g k8s` authenticated with device-flow re-login hint printed on failure, per FR-005), zen provider/profile existence check + idempotent create, sandbox create (name `zen-$(date +%s)`, `--from` 008 carrier image, `--provider zen`), policy set with retry loop, config inject, Ready-wait
- [ ] T012 [US1] Add inject step using `deploy/openshell/demo/zen/opencode-zen.json` (reuse 008 `inject-config.sh` mechanics: exec mkdir + tee + verify-string grep adapted to the zen host) with PASS output per contract Z3
- [ ] T013 [US1] Add fence-window verification to `deploy/openshell/demo/zen/run-zen-demo.sh`: after create, confirm the sandbox still exists at +5.5 min before declaring G2 success; on fence-death, auto-recreate once and log the event (spec edge case; 008 mitigation)
- [ ] T014 [US1] Run G2 acceptance: execute the driver end-to-end; record preflight PASS, create time, Ready time, alive-past-fence proof in demo-log (SC-001 timer segment starts)
- [ ] T015 [US1] Verify unconditional cleanup + residual check (`trap`-based; `openshell sandbox delete` idempotent; post-run `openshell sandbox list` empty) by re-running the driver (US1 AC3); log both runs in demo-log

**Checkpoint**: US1 independently demonstrable — "CLI-deployed governed sandbox" with evidence committed

---

## Phase 4: User Story 2 - Answer a basic query through a free hosted model from inside the sandbox (Priority: P1)

**Goal**: "hi" answered by a zen free-tier model behind a least-privilege egress policy built by recorded remediation

**Independent Test**: Exec-query returns a real model response while ≥5 non-allowlisted egress attempts all show denial (quickstart G3)

- [ ] T016 [US2] Run the first `hi` attempt under the T009 deny-all policy; capture the failing classification (policy-deny vs provider-error vs auth) and the supervisor `OCSF NET:OPEN DENIED` excerpt into demo-log (FR-003 iteration 0)
- [ ] T017 [US2] Remediation loop on `charts/openshell-policy/policies/zen-demo.yaml`: for each observed denied destination add exactly one justified rule (host/port/`protocol: rest`/binaries + `# justification: <probe>` comment), commit, keep `tests/test-zen-policy.sh` green, `openshell policy set --wait`, retry — repeat until `hi` returns a genuine model response (≤2 min per query, SC-002)
- [ ] T018 [US2] Record the terminal iteration: full prompt/response transcript and provider-success classification in demo-log (contract Z3)
- [ ] T019 [US2] Deny proofs: attempt ≥5 distinct non-allowlisted hosts from inside the sandbox (e.g. example.com, github.com, pypi.org, api.openai.com, registry-1.docker.io); assert all denied; log results (SC-003)
- [ ] T020 [US2] No-secrets proof (only if T006 key mode engaged): grep sandbox env and `/sandbox` for real key bytes; assert only `openshell:resolve:env:*` placeholders; log result (008 proof pattern, contract Z6)

**Checkpoint**: SC-001 (≤15 min login→hi) measured and logged; US2 complete with the remediation trail in Git (FR-003, FR-004)

---

## Phase 5: User Story 3 - Expose the agent in server mode and drive it from the local client (Priority: P2)

**Goal**: `opencode serve` inside the sandbox, local client attach, server-driven "hi"

**Independent Test**: From sandbox-Ready, local `opencode attach` submits "hi" through the forward and receives the free-tier response within 5 min (quickstart G4)

- [ ] T021 [US3] Write `deploy/openshell/demo/zen/run-zen-server.sh`: preflight (as T011), sandbox create, zen config inject, start `opencode serve --hostname 0.0.0.0 --port 4096` detached inside the sandbox, in-sandbox health probe on port 4096
- [ ] T022 [US3] Establish transport per the T007 verdict (contract Z4): gateway path if viable, else `oc port-forward` to the sandbox pod + print the exact local `opencode attach http://localhost:4096` command; optional `OPENCODE_SERVER_PASSWORD` conveyed one-time via console output, never committed
- [ ] T023 [US3] Verify from the local client: attach, submit `hi`, confirm free-tier response; capture both-side evidence (local transcript + in-sandbox server log line) in demo-log
- [ ] T024 [US3] Teardown: kill forward, delete sandbox, verify zero residual (sandbox list empty, no strayed port-forward processes); record in demo-log (G5 partial)

**Checkpoint**: US3 demonstrable end-to-end in ≤5 min from sandbox-Ready (SC-004)

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Evidence finalization, full gates, GitOps landing

- [ ] T025 [P] Finalize `specs/011-zen-sandbox-demo/demo-log.md`: complete run table, G0 spike answers, G2–G4 evidence, timing budget table vs SC-001/002/004 with actuals
- [ ] T026 [P] Add a zen-demo section to `docs/openshell-demo-opencode.md` (prereqs, commands, gotchas discovered) keeping the matilda runbook intact
- [ ] T027 Run full gates: `make test-static` + `make validate-schema` green; G5 zero-residual check (`openshell sandbox list` empty, no demo pods, vault template diff clean); record results in demo-log
- [ ] T028 Merge all work to `main` per repo flow (feature branch → merge → push; 010 pattern), confirm ArgoCD reconciles cleanly, record merge SHA in demo-log + tasks.md (G6)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (T001–T003)**: no dependencies; T002 + T003 parallel after T001
- **Phase 2 (T004–T010)**: T003→T005 (profile backfill); T004→T006 conditional chain; T007, T008 independent; T009 after T008 (binaries); T010 after T009 — **BLOCKS all stories**
- **Phase 3 (US1, T011–T015)**: after T005/T007/T008/T010
- **Phase 4 (US2, T016–T020)**: after US1 sandbox lifecycle proven (T014/T015)
- **Phase 5 (US3, T021–T024)**: after US2 model path healthy (T017/T018)
- **Phase 6 (T025–T028)**: after all stories

### User Story Dependencies

- **US1**: foundation only — independently testable via G2
- **US2**: needs US1's proven sandbox lifecycle; independently testable via G3 (own sandbox run)
- **US3**: needs US2's working model+policy state; independently testable via G4 (own sandbox run)

### Parallel Opportunities

- T002 + T003 (setup) after T001
- T007 + T008 (spike probes) parallel to the T004→T006 chain
- T025 + T026 in polish
- Live-cluster mutation tasks (T011–T024) strictly sequential — one sandbox lifecycle at a time

---

## Implementation Strategy

### MVP First (US1 Only)

1. T001–T010 setup + spike resolution
2. T011–T015 US1 (G2 evidence committed)
3. **STOP and VALIDATE**: CLI-deployed sandbox demonstrated (feature deliverable #1)

### Incremental Delivery

1. Setup + Foundational → spike answers committed
2. US1 → G2 → evidence #1 (sandbox via CLI)
3. US2 → G3 → evidence #2+#3 (zen free-model hi + remediated rules in Git)
4. US3 → G4 → evidence #4 (server mode from local client)
5. Polish → G5/G6 → all merged to main

---

## Notes

- FR-003 trail discipline: every zen-demo.yaml rule is committed **with or after** its motivating deny evidence (T017)
- SC-001 excludes one-time cold image pull (spec assumption); log separately if it occurs
- If T004's keyless probe succeeds, T006 resolves with no vault changes and `opencode-zen.json` carries no `apiKey`
- `make test-static` must stay green after every policy/script commit (T010 guard active from Phase 2)