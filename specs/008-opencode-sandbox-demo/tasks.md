# Tasks: Opencode-in-Sandbox Demo (Matilda LLM)

**Input**: Design documents from `/specs/008-opencode-sandbox-demo/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/demo-assets.md

**Organization**: Tasks grouped by user story for independent implementation and testing. No TDD test tasks (spec does not request them); repo drift/live-regression additions land as implementation tasks with their own makes/CI targets.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: demo asset layout per plan.md

- [X] T001 Create demo asset directory `deploy/openshell/demo/` and docs home `docs/openshell-demo-opencode.md` skeleton (mktree + placeholder headings per contracts/demo-assets.md C1–C4)
- [X] T002 [P] Add drift assertions to `tests/test-openshell-render.sh` for demo assets: `deploy/openshell/demo/opencode-matilda.json` exists, parses as JSON, `apiKey == "{env:MATILDA_API_KEY}"`, no non-matilda host appears in it; `charts/openshell-policy/policies/sample-matilda-demo.yaml` has non-empty `binaries` and `protocol: rest`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: live-gateway state the demo needs; all US work is blocked until done

- [X] T003 Verify/refresh cluster OIDC session: `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` then `openshell status -g k8s` shows Connected + Authenticated (device flow per quickstart Phase -1)
- [X] T004 Ensure matilda profile/provider on cluster gateway: `openshell profile describe matilda` → missing? `openshell provider profile import -f deploy/openshell/profiles/matilda.yaml --global`; `openshell provider list | grep matilda` → missing? `MATILDA_API_KEY=... openshell provider create --name matilda --type matilda --global-profile --credential MATILDA_API_KEY`
- [X] T005 Binary-path discovery for the egress policy: `openshell sandbox create --name bin-probe --from ghcr.io/butler54/openshell-sandbox:latest --detach --no-keep`, THEN APPLY FUNDAMENTAL: `openshell policy set bin-probe --policy charts/openshell-policy/policies/sample-matilda-demo.yaml --wait` (a policy-less sandbox never leaves Provisioning — V-EGRESS fact), THEN exec `sh -lc 'which node opencode curl; readlink -f $(which node); readlink -f $(which opencode)'` inside, and record the resolved executables (quickstart Phase 0)
- [X] T006 Update `charts/openshell-policy/policies/sample-matilda-demo.yaml` binaries with T005 results (keep `/usr/bin/curl`), commit as one logical change
- [X] T007 Run `make check-openshell-cli` and `make validate-openshell` fully green after T006 (all suites incl. new T002 drift assertions)

**Checkpoint**: prerequisites live and Git-validated — user story work can start

---

## Phase 3: User Story 1 - Governed opencode demo against matilda (Priority: P1) 🎯 MVP

**Goal**: opencode runs inside a governed cluster sandbox against matilda via manually injected config; placeholder-injection + deny posture proven live

**Independent Test**: quickstart Phase 1 (scripted smoke) — `MODE=smoke DEMO_PROMPT="Reply with exactly: OPENSHELL_VDEMO_OK" deploy/openshell/demo/run-demo.sh --smoke` prints all PASS lines; egress deny proof + zero key bytes proof run in-sandbox.

- [X] T008 [US1] Create config template `deploy/openshell/demo/opencode-matilda.json` per contract C1 (strict JSON, `provider.matilda.options.baseURL = https://matilda.maincode.com/api/v1/code`, `apiKey = "{env:MATILDA_API_KEY}"`, model `matilda-code-1.0`, no secret material)
- [X] T009 [US1] Create idempotent injector `deploy/openshell/demo/inject-config.sh` per contract C2 (exec-based copy to `/sandbox/.config/opencode/opencode.json`, verification via grep, non-zero on failure)
- [X] T010 [US1] Create `deploy/openshell/demo/run-demo.sh` per contract C3: preflight → create `--from "$DEMO_SANDBOX_IMAGE" --provider matilda --detach` → inject → `openshell policy set` matilda policy → mode split (interactive attaches via `openshell sandbox connect` / `--smoke` runs one-shot `opencode run`) → proofs (deny probe (rc=7 refused), zero-`mc_live` grep on env+sandbox mount, policy effective) → unconditional `openshell sandbox delete` cleanup with non-fatal absent state
- [X] T011 [US1] Add `--proofs` mode to `deploy/openshell/demo/run-demo.sh` (separates attach from proofs so interactive sessions resume into proofs per quickstart Phase 2)
- [X] T012 [US1] Live smoke run: T003 authn confirmed first, then full `--smoke` sequence against cluster gateway; run the smoke sequence 3 consecutive times, capturing timing each (SC-001 3-of-3); confirm SC-002 (zero key bytes) and SC-003 (≥5 varied deny probes refused rc=7)
- [X] T013 [US1] Author runbook `docs/openshell-demo-opencode.md` per contract C4 (Prerequisites → one-time setup → smoke → interactive → live proofs → cleanup → troubleshooting: token rotation, watcher restart, image pull latency, OPA deny binaries hint)

**Checkpoint**: US1 gate complete — interactive + scripted smoke demo green, artifacts committed

---

## Phase 4: User Story 2 - sandboxctl compat attempt + bug reports (Priority: P2)

**Goal**: sandboxctl attempted first on local gateway; blockers become tracked issues; emulation path documented

**Independent Test**: quickstart Phase 3 — `sandboxctl` reproduces a failure (or succeeds); ≥1 issue raised per distinct blocker with repro+expect/actual; runbook references the recorded issues; emulation documented in `docs/openshell-demo-opencode.md`.

- [X] T014 [US2] Attempt equivalent demo flow via `sandboxctl` on local podman gateway (fresh 0.1.1 baseline): record command, version (`sandboxctl doctor --all`), error/partial-state outcomes
- [X] T015 [US2] Raise GitHub issues for each distinct sandboxctl defect per FR-005 (version+env, repro, expected vs actual)
- [X] T016 [US2] Document the direct `openshell` emulation of the sandboxctl lifecycle in `docs/openshell-demo-opencode.md` with links to raised issues

**Checkpoint**: sandboxctl defects tracked upstream; operator-preferred path has a tracked fix-trajectory; emulation documented

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T017 [P] Wire `MODE=smoke deploy/openshell/demo/run-demo.sh --smoke` as opt-in target `make validate-openshell-demo` in `Makefile` (guarded: skip syscall if cluster unreachable, documented)
- [X] T018 [P] Verify `make validate-openshell` still green after all feature changes and `pre-commit run --all-files` passes
- [X] T019 Run full quickstart V-DEMO acceptance sequence (`specs/008-opencode-sandbox-demo/quickstart.md`) end-to-end capturing outputs into `specs/008-opencode-sandbox-demo/demo-log.md`
- [X] T020 Commit/push feature branch `008-opencode-sandbox-demo`, then merge to `main` (repo convention: direct-to-main flow, pre-commit hooks on)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no deps, start immediately
- **Phase 2 (Foundational)**: depends on T002; blocks all story phases (gateway auth/provider state)
- **Phase 3 (US1)**: depends on Phase 2; T008–T011 can largely parallelize after T008 exists
- **Phase 4 (US2)**: independent of Phase 3 (local gateway path); can run parallel with US1 or after
- **Phase 5 (Polish)**: depends on Phase 3 (+4 for linkage)

### Parallel Opportunities

- T001, T002 (different files)
- T008, T009, T010, T011 (script files, different files — T011 depends only on run-demo.sh scaffolding from T010)
- US2 chain (T014–T016) parallel with US1 chain (T008–T013)
- T017, T018 in Polish

## Parallel Example: User Story 1

```bash
Task: "Create config template deploy/openshell/demo/opencode-matilda.json"
Task: "Create injector deploy/openshell/demo/inject-config.sh"
Task: "Create deploy/openshell/demo/run-demo.sh preflight+create+inject+attach+proofs+cleanup"
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational
3. Complete Phase 3: User Story 1 (T008–T013)
4. Validate via `run-demo.sh --smoke` green → demoable MVP

### Incremental Delivery

1. Setup + Foundational → prerequisites live
2. US1 → demo MVP (both session shapes)
3. US2 → sandboxctl compat story + issue tracking
4. Polish → CI wiring, acceptance log, merge

## Notes

- All live gRPC/HTTP operations stay CLI-driven (recorded imperative per Constitution II); nothing bespoke hits the gateway API.
- All file paths above are repo-relative (valid from repo root).

---

## Phase 6: Convergence

- [X] T021 Make run-demo.sh cleanup unconditional on proof failures — currently a FAIL proofs path exits before cleanup runs (leaked sandboxes during 008 testing); wrap with EXIT trap or cleanup-on-fail so FR-009/SC-005 holds in all exit paths per FR-009 (partial)
