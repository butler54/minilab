# Implementation Plan: GitHub org-restricted authorization for openshell

**Branch**: (direct-to-main per Clarifications) | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/013-github-org-authz/spec.md`

## Summary

Gate openshell logins to GitHub org `tempest-concorde` members by inserting a **dex** (dexidp) OIDC-authorization hop in front of GitHub: `GitHub → dex (org-gated) → Keycloak (existing, generic OIDC IdP) → openshell gateway`. Keycloak's GitHub IdP cannot evaluate org membership natively (GitHub emits no org claims; KC's github provider never calls the orgs API; no declarative realm option exists at RHBK 26), and a custom Keycloak SPI would break the house's declarative/no-custom-code constraint. Dex's GitHub connector natively enforces `orgs[].name` (+ optional `teams`) at every login with auditable deny events — the canonical solution for exactly this shape. Everything ships as Git-only changes on `main`.

## Technical Context

**Language/Version**: YAML/Helm (GitOps), no application code. **Primary Dependencies**: `dex/dex` helm chart 0.26.0 (dex 2.46.0) via OCI/helm repo `https://charts.dexidp.io`; existing `rhbk` Keycloak chart (values shape already in use); ExternalSecrets (vault-backed) per house pattern. **Storage**: dex storage = Kubernetes CRDs-backed (`config.storage.type: kubernetes`) — stateless to us. **Testing**: `make test-static` suites + `./pattern.sh make validate-schema` + live login/gate proofs (device flow). **Target Platform**: existing SNO OCP 4.22 GitOps cluster (Argo CD in `vp-gitops`). **Project Type**: GitOps config change (values + one new app).

**Constraints**: house GitOps-first (everything via Git; imperative steps recorded); minimal changes (replace one IdP, add one app); no behavior change for openshell clients (they still talk OIDC to KC realm only). GitHub-side prerequisites (OAuth App creation/consent, vault writes) are the only imperative steps, recorded with commands/outputs.

## Constitution Check

| Principle | Gate | Rationale |
|---|---|---|
| I. GitOps-first | **PASS** | All cluster-facing changes are values/values-prod edits converged by ArgoCD. GitHub OAuth App consent + vault writes are unavoidable non-cluster prerequisites; recorded (commands+outputs) in the feature evidence log. |
| II. Record imperative steps | **PASS** | Every imperative action (GitHub App setup, vault writes, KC admin role re-grant if relink needed, hard-sync annotations) is pre-recorded in quickstart G-gates with exact commands. |
| III. Helm-only, minimal | **PASS** | dex is upstream's official chart; KC unchanged except one IdP block + placeholders; no custom images/SPI/plugins. |

Post-phase-1 re-evaluation: all gates remain PASS (design adds no new imperative surface beyond the recorded GitHub/vault prereqs).

## Project Structure

### Documentation (this feature)

```text
specs/013-github-org-authz/
├── plan.md            # this file
├── research.md        # mechanism decision, probes, alternatives
├── data-model.md      # authz entities
├── contracts/README.md# C1-C4 behavioral contracts + proofs
└── quickstart.md      # G0-G6 validation gates
```

### Source changes (repo-relative)

```text
values-prod.yaml                       # + dex app block (chart dex/dex 0.26.0, ns openshell)
overrides/values-dex.yaml              # NEW: dex issuer/config (connectors.github orgs, staticClient for KC, ESO env)
overrides/values-dex-secrets?          # NOT USED — dex secrets sync via its values' enves (see notes)
overrides/values-keycloak.yaml         # IdP github(providerId:github) -> generic oidc 'github' pointed at dex; placeholder map for KC->dex client creds
tests/test-external-refs.sh            # + dex chart pin expectation
docs/openshell-demo-opencode.md        # login-flow note (extra redirect hop; unchanged commands)
```

Existing ESO/vault patterns reused: `extraSecrets` + `realmPlaceholders` (values-keycloak.yaml), dex chart `env:` from Secret (same path/key). Vault record path prefix (house): `secret/data/hub/...`.

## Data Flow / Decision Chain

```text
user (openshell WebUI or CLI device flow)
  → Keycloak login page (realm openshell)
    → IdP 'github' (generic OIDC) → https://dex.tokyo-brunch.com
      → dex GitHub connector (orgs: [{name: tempest-concorde}])
        → GitHub OAuth consent (+ org membership + user-orgs API)
        ← MEMBER? → dex issues id_token; logs allow (or DENY + error page)
    ← KC completes login, IdP mapper → openshell-user role
  ← gateway session (existing token lifetimes; minilab#9 untouched)
```

Deny UX: dex shows its error page ("user is not in the required org"), KC surfaces upstream-failure; neither KC session nor gateway token is issued (FR-003). Fail-closed by construction: if dex is down or GitHub back-channel errors, login cannot complete (Edge Case #1 satisfied structurally).

## Sequencing (high level)

1. **G-prereqs (imperative, recorded)**: create org-owned GitHub OAuth App `openshell-authz` (callback https://dex.tokyo-brunch.com/callback); org-level OAuth approval; vault writes (`secret/data/hub/openshell-dex`).
2. **Git commit A (inert)**: dex app + values + external-refs pin (deploys dex; nobody is routed through it yet).
3. **Git commit B (cutover)**: KC IdP swap github→oidc(dex). Sync verified; live login proof (member path).
4. **Git commit C (live gate proof)**: temporary `orgs: [tempest-concorde-x]` (nonexistent org) commit → operator login must be DENIED (full-chain synthetic negative per clarified SC-002) → revert commit C.
5. Observability evidence + zero-residual sweep; docs note.

Rollback at any point: `git revert` the relevant commit (C trivial; B restores old IdP immediately; A leaves an idle dex which can be deleted by removing its app block).

## Research

See [research.md](research.md). Headline decision: **dex-in-front** (rather than KC SPI, KC-native Impossible options, or allow-list realm approaches) — only mechanism meeting FR-002/FR-004 declaratively without custom code.

## Watch-items / Risks

- **Federated-identity relink**: dex `sub` = GitHub numeric user ID by default, matching what KC's github provider linked; expected zero-arg relink to existing KC user butler54, but if KC fails to match (email-collision prompt or new user), the recorded contingency is: complete login as new federated user, then KC admin console re-grant `openshell-admin` (recorded imperative step, ~2 min).
- **`openshell-admin` role**: currently manual KC admin-console grant (011/012); if the mapping survives relink, nothing to do; contingency listed above.
- **Realm IdP update applies live**: KeycloakRealm diff-apply happens without KC restart in RHBK operator flows; watch `rh-keycloak`/openshell apps Synced+Healthy through cutover (FR-007).
- **Dex availability becomes login prerequisite**: acceptable — fail-closed requirement means an auth-gate outage SHOULD block logins; dex is tiny (single replica, kubernetes storage), and this is a lab single-user platform.

## Follow-ups deferred (not this feature)

- minilab#9 OIDC session-life fix (`ssoSessionIdleTimeout`) — independent line fix.
- Vault-centered team-based tightening (`teams: [openshell-access]`) — one-line dex values change if org granularities ever shift.
- OCSF deny-evidence channel — pending upstream chart wiring (#3264/#3876).
