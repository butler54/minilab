# Demo Log: 013 — GitHub org-restricted authorization (Path B: dex-first, conditional KC decommission)

Evidence log for contract gates C1–C6. One row per phase/run; rows appended as tasks complete.
Static gates re-run before each push. All imperative actions recorded (constitution §II).

## Preconditions (G0, 2026-10-13)

- `make test-static` → all suites passed (openshell-values, openshell-ztwim, pattern-wrapper,
  vault-storage-override, zen-policy, validate-pattern-config)
- `./pattern.sh make validate-schema` → All assertions passed
- App table snapshot (`oc -n vp-gitops get applications`): all **Synced/Healthy** except
  pre-existing `lvms-config` OutOfSync (feature 010, out of scope):
  `cert-manager cert-manager-config lvms-config minilab-prod observability-config olm-config
  openshell openshell-demo openshell-keycloak-config openshell-platform openshell-policy
  openshift-external-secrets openshift-monitoring-config rh-keycloak vault ztwim`
- KC workload snapshot (`oc -n keycloak-system get pods`):
  `keycloak-0 1/1 Running` · `openshell-realm-import-5tp8n 0/1 Completed` ·
  `postgresql-db-0 1/1 Running` · `rhbk-operator-649697b459-x98t2 1/1 Running`

## Prereq record (imperative, recorded per quickstart G1/G2)

| Item | Action | Recorded value (non-secret) | Status |
|---|---|---|---|
| GitHub teams | Create `openshell-users` + `openshell-admins` in org `tempest-concorde`; add butler54 to both | team slugs | done 2026-10-14 (operator confirm) |
| GitHub OAuth App | Create org-owned `openshell-authz`, callback `https://dex.tokyo-brunch.com/callback` | Client ID (secret never logged) | done 2026-10-14 — Client ID collected by operator; expiring user tokens ON, device flow OFF |
| Vault | `secret/data/hub/openshell-dex` ← `github-client-id`, `github-client-secret` | write confirmation | done 2026-10-14 — seeded via `~/values-secret-minilab.yaml` + `./pattern.sh make install` (operator confirm; ESO sync proof with T005) |
| Cloudflare DNS | `dex` A-record → cluster ingress `192.168.5.162` (DNS-only) | record added | done 2026-10-14 (operator confirm; same target as keycloak/openshell records) |

## Run table

| Run | Phase / commit | Result | Timing (converge) |
|---|---|---|---|
| R1 | Foundational — Commit A (inert dex) | pending | — |
| R2 | Foundational — dex-direct smoke + deny gate-flip (C1) | pending | — |
| R3 | US1 — Commit B (gateway cutover, C2) | pending | — |
| R4 | US1 — decision-gate soak (C3) | pending | — |
| R5 | Completion — Commit C (KC decommission, C4) | pending | — |
| R6 | Completion — Commit D (hygiene) + final sweep (C6) | pending | — |

## Contract verdicts

| Contract | Evidence | Verdict |
|---|---|---|
| C1 inert dex + smoke | discovery doc, groups claim, deny flip log lines | pending |
| C2 gateway cutover | login/status/sandbox/admin log lines | pending |
| C3 decision gate | soak table, JWT validation lines | pending |
| C4 decommission | post-removal re-login, workload termination list | pending |
| C5 observability | allow + deny lines with identity attribution | pending |
| C6 zero residual | final sweep table | pending |

## Spec criteria tracker (SC-001..005)

| Criterion | Evidence anchor | Verdict |
|---|---|---|
| SC-001 member login < 2 min | R3 login run | pending |
| SC-002 synthetic non-member denied (evaluator-level) | R2 gate-flip run | pending |
| SC-003 enable ≤15 min single push | R1..R4 converge timings | pending |
| SC-004 allow+deny in platform logs | C5 rows | pending |
| SC-005 per-login freshness | US2 freshness samples | pending |

## Field notes

- 2026-10-14 (T003): OAuth App configured with **expiring user authorization tokens ON**
  (8h upstream GitHub→dex token + 6m refresh token; dex 2.46 connector is refresh-capable —
  gateway token lifetimes unaffected, V4 observes those separately) and **device flow OFF**
  (dex does not implement RFC 8628; accepted trade per spec clarification 2026-10-13).
- 2026-10-14 (T004 mechanism): vault seeding switched from manual `vault kv put` to the house
  values-secret flow — `openshell-dex` block added to `values-secret.yaml.template` (+7th-entry
  pin bump in `tests/test-openshell-secrets.sh`) and to operator-local `~/values-secret-minilab.yaml`
  (values filled by operator, file never in git). Seeding runs via `./pattern.sh make install`.
- (appended per run)
