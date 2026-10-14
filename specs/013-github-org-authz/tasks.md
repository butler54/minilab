# Tasks: GitHub org-restricted authorization for openshell (Path B)

**Input**: Design documents from `/specs/013-github-org-authz/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md
**Delivery**: direct commits on `main` (Clarifications 2026-10-13). **All imperatives are pre-recorded in quickstart.md G-gates (constitution §II).** User-action tasks are flagged **[USER]**.

Organization: US1 (P1) = org gate live at the gateway · US2 (P2) = per-login freshness · US3 (P3) = declarative+auditable. Final phase = conditional KC decommission (blocked by the C1–C3 decision gate).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: parallelizable (different files, no dependencies)
- **LIVE**: touches cluster/gateway — batch within a session window

---

## Phase 1: Setup

- [X] T001 Create `specs/013-github-org-authz/demo-log.md` (evidence log; tables like 012: run table per Commit-phase A/B/smoke/C/D, timing table, prereq record, close record); commit to `main`
- [X] T002 G0 baseline: `make test-static` + `./pattern.sh make validate-schema`; capture `oc -n vp-gitops get applications` and `oc -n keycloak-system get pods` snapshots into demo-log
- [X] T003 **[USER]** ✍ GitHub-side prereqs (quickstart G1): create teams **openshell-users** and **openshell-admins** in org `tempest-concorde`, add butler54 to both; create org-owned OAuth App **openshell-authz** (homepage `https://dex.tokyo-brunch.com`, callback `https://dex.tokyo-brunch.com/callback`); record Client ID (secret NEVER into git/logs) — done 2026-10-14 incl. Cloudflare `dex` A-record; expiring user tokens ON, device flow OFF
- [X] T004 **[USER]** ✍ vault write (quickstart G2): record `secret/data/hub/openshell-dex` with `github-client-id` + `github-client-secret`; confirm ESO can sync (no new ClusterStore wiring); record completion (not values) in demo-log — mechanism: operator filled `~/values-secret-minilab.yaml` (`openshell-dex` block), seeded via `./pattern.sh make install` 2026-10-14; ESO sync proof lands with T005 ExternalSecret

---

## Phase 2: Foundational — inert dex + direct smoke (Commit A, contract C1)

**CRITICAL gate for everything downstream: dex must be live, discoverable, and proven to gate BEFORE the gateway moves.**

- [X] T005 Write `overrides/values-dex.yaml` (issuer `https://dex.tokyo-brunch.com`; `connectors: [{type: github, id: github, config: {clientID: $GITHUB_CLIENT_ID, clientSecret: $GITHUB_CLIENT_SECRET, redirectURI: https://dex.tokyo-brunch.com/callback, orgs: [{name: tempest-concorde, teams: [openshell-users, openshell-admins}], teamNameField: slug}}]`; `storage: kubernetes`; staticClients: `openshell-cli` (public, redirect TBD at V1) + TEST client `dex-substrate-test` with laptop redirect `http://127.0.0.1:5555/callback`; acme-cert route per house pattern) — secrets via `env:` from an ESO-synced Secret rendered from the same chart pattern as the keycloak `extraSecrets` block — done via house chart `charts/dex-config/` (Certificate dex-external + passthrough Route + ExternalSecret dex-github-oauth; the upstream dex chart renders none of these)
- [X] T006 Add dex app block to `values-prod.yaml` under `clusterGroup.applications` (chart `dex/dex`, version `0.26.0`, repo `https://charts.dexidp.io`, ns `openshell`, overrides `values-dex.yaml`) and dex pin expectations to `tests/test-external-refs.sh`; run `make test-static` + `./pattern.sh make validate-schema`; commit+push (Commit A); record SHA — also `dex-config` path app (wave -3) + `dex` chart app (wave -2); new `tests/test-dex-values.sh` gate; ordering/secrets/lint updates; dial `global.openshell.dex.hostname`; SHA recorded in demo-log at T007 evidence
- [ ] T007 **LIVE** Post-sync verify inert dex: `oc -n openshell get pods | grep dex` Running; `oc -n vp-gitops get applications | grep dex` Synced/Healthy ≤15min (SC-003 sample); `curl -s https://dex.tokyo-brunch.com/.well-known/openid-configuration | head -c 300` recorded; gateway+KC untouched check (existing login still works — record a pre-cutover login sanity line)
- [ ] T008 **LIVE** dex-direct smoke via TEST staticClient from the laptop (gateway untouched): run a local OIDC flow (e.g. `curl`-readable `https://dex.tokyo-brunch.com/.well-known/openid-configuration` + browser auth-code via TEST client redirect `http://127.0.0.1:5555/callback` — allow dev-side helper like `npx dex-test-app` if handy, commands recorded); capture id_token payload showing `groups: ["tempest-concorde:openshell-users","tempest-concorde:openshell-admins"]` AND dex pod allow log-line. Then: commit gate-flip `orgs: [tempest-concorde-x]` → push+sync → login attempt DENIED at dex (record failure UX + `oc -n openshell logs deploy/dex | grep -i deny` line) → revert flip commit (this is the SC-002 synthetic-negative live run)

**Checkpoint: contract C1 proven; if any task fails, unrelated ops stay safe — nothing references dex yet.**

---

## Phase 3: US1 (P1) — gate live at the gateway (Commit B, contracts C2/C3)

**Goal**: openshell sessions only via org/team-approved dex path on the gateway

**Independent Test**: post-B login succeeds for operator via dex, roles derive from GitHub teams, no KC realm contact for authn

- [ ] T009 [US1] Cutover `overrides/values-openshell-gateway.yaml` oidc block: `issuer: https://dex.tokyo-brunch.com` · `audience: openshell-cli` (confirm V2 staticClient id at implementation) · `rolesClaim: groups` · `userRole: tempest-concorde:openshell-users` · `adminRole: tempest-concorde:openshell-admins`; push+sync (Commit B); verify `openshell` app Synced+Healthy and gateway pod restart clean
- [ ] T010 [US1] **LIVE V1 checkpoint**: `openshell gateway logout k8s` then `openshell gateway login k8s` (DEFAULT browser flow); **if the flow attempts an un-registered localhost redirect against dex → STOP, revert T009 commit, record, and switch to Path-A residue end-state** (else:) `openshell status -g k8s` Connected/Authenticated; `openshell sandbox list -g k8s`; `openshell gateway info` proves admin role; Web login sanity at `https://openshell.tokyo-brunch.com`; record everything (incl. V4 note: observe CLI token-lifetime behavior vs KC's ~50-min symptom)
- [ ] T011 [US1] **LIVE** decision gate soak: 15 min no drift/restarts on `openshell*`/`dex` apps (`watch oc -n vp-gitops get applications`), collect gateway JWT-validation log lines vs dex keys (`oc -n openshell logs deploy/openshell-gateway | grep -i jwt` or equivalent); write C3 verdict into demo-log (GREEN only if C1+C2+C3 all pass)

---

## Phase 4: US2 (P2) — per-login freshness evidence (SC-005)

**Independent Test**: gate decision reflects config/GitHub truth at login time, not a cached allow

- [ ] T012 [US2] **LIVE** freshness sample: after the T008 revert sync, operator login works AGAIN without any GitHub-side change (decision follows values truth); record two login timestamps ≥30 min apart with dex log lines showing fresh org queries; log structural note (dex queries GitHub per login — research.md R1) as the freshness mechanism; SC-005 recorded in demo-log

---

## Phase 5: US3 (P3) — declarative + auditable (SC-004/FR-006)

**Independent Test**: allow AND deny events with identity attribution are in platform logs; full gate state is reconstructible from Git

- [ ] T013 [US3] **LIVE** observability capture: dex allow-lines (T008/T010 logins) + deny-lines (T008 flip) + keycloak-era IdP error absence post-cutover; paste representative lines (timestamps, identity) into demo-log
- [ ] T014 [US3] Update `docs/openshell-demo-opencode.md`: new login topology diagram line (GitHub→dex→gateway), teams-as-roles mapping, browser flow as primary, device-flow removal note (dex limitation, accepted), dex deny UX description; commit+push

---

## Phase 6: Path-B completion (Commit C + D) + Polish

**PRECONDITION: T011 decision gate GREEN. If RED: replace this phase with revert-of-T009 + Path-A residue task (KC IdP→dex upstream refactor becomes its own follow-up).**

- [ ] T015 ✍ Commit C — KC decommission: remove `rh-keycloak` and `openshell-keycloak-config` app blocks from `values-prod.yaml` (and orphan-prone `overrides/values-keycloak.yaml` KC-realm leftovers per review); push+sync; verify `keycloak-system` workloads (`keycloak-0`, `postgresql-db-0`, `rhbk-operator`) terminate; **immediately re-login via gateway (tripwire: must still work through dex)**; then delete KC postgres PVC `oc -n keycloak-system delete pvc $(oc -n keycloak-system get pvc -o name)` and note `keycloak.tokyo-brunch.com` DNS/ingress disposition (remove vs leave-stale decision) — all recorded in demo-log
- [ ] T016 Commit D — hygiene: retire `secret/data/hub/openshell-github-oauth` references from `overrides` + note vault-record retirement ✍ (record deletion as imperative, foliage not in git); sweep KC-specific pins from `tests/*` if any assert the removed paths; static gates green; commit+push
- [ ] T017 Final sweep + close: zero-residual (`openshell sandbox list` empty, no stray forwards, lvms-only OutOfSync), `make test-static` + schema gate green, apps all Synced+Healthy incl. dex; fill demo-log timing/run tables + SC-001..005 verdicts; mark tasks [X]; commit+push

---

## Dependencies

```text
P1 Setup (T001-T004, user prereqs) → P2 Foundational (T005-T008, C1 gate-proven dex)
  → P3 US1 (T009-T011, Commit B + decision gate) [HARD STOP ON RED]
    → P4 US2 (T012) + P5 US3 (T013-T014)
      → P6 Completion (T015-T017, C4-C6) [only if T011 GREEN]
```

- T003/T004 (user actions) block T005 (values need the OAuth creds in vault)
- T008 is the SC-002 synthetic-negative; it doubles as the US2 freshness substrate
- T010 contains the recorded V1 fallback trigger (wildcard-redirect incompatibility)
- T015 is irreversible-ish; the tripwire re-login happens INSIDE the task

## Parallel

- T003+T004 (user-side, different consoles)
- T012 merges with T013 (same live log pulls)

## MVP

Phases 1–3 (gate live at gateway via Commit B). Phase 6 (decommission) is a separately-reviewer-checkpointed increment — the org gate exists with or without it.

## Validation strategy

- Contracts C1–C6 per `contracts/README.md`; quickstart G0–G8 order preserved by ID numbering
- Evidence: `specs/013-github-org-authz/demo-log.md` tables; static gates before every push
