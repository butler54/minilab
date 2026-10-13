# Data Model: GitHub org-restricted authorization (013, Path B)

## Entities

### GitHubIdentity
- **`id`** (GitHub numeric user ID) — dex `sub` (connector default `useLoginAsID: false` → numeric id). Survives KC removal without migration because gateway consumers never aliased KC subject ids for durable records (verify gate: no workspace/label relies on KC sub).
- `login`, `email`.
- **`orgs[]` / `teams[]`** — GitHub API truths at login time; authoritative.

### GitHubTeam (new — created in tempest-concorde at G1)
- `openshell-users` — base gateway access (member ⇒ dex groups claim contains `tempest-concorde:openshell-users` ⇒ maps to gateway userRole).
- `openshell-admins` — elevated gateway admin (⇒ adminRole). butler54 initial member of both.

### GatewayOIDCContract (values invariants)
- `oidc.issuer = https://dex.tokyo-brunch.com`
- `oidc.audience` = dex staticClient id for gateway/api consumption (`openshell-cli` unless V2 discovers a gateway-web client is needed)
- `oidc.rolesClaim = groups` · `userRole = tempest-concorde:openshell-users` · `adminRole = tempest-concorde:openshell-admins`
- Both roles set together (gateway rule: both or neither).

### DexStaticClients
- `openshell-cli` (public) — CLI/browser login through gateway edge proxy; redirect URIs captured at V1 (expected gateway-hosted `https://openshell.tokyo-brunch.com/...` — exact-match list).
- optional debug/test staticClient used in the inert phase to probe dex directly from the laptop.

### AccessDecision
- dex logs at every login: allow(reason=org+team membership), deny(not-in-org / not-in-team / backchannel error). FR-006 observable.

### VancouverRecords (Post-cutover removal inventory)
- workloads `keycloak-0`, `postgresql-db-0`, `rhbk-operator`; app `openshell-keycloak-config`; vault record `secret/data/hub/openshell-github-oauth`; KC postgres PVC (manual-delete candidate, recorded imperative); `keycloak.tokyo-brunch.com` DNS/ingress (recorded imperative cleanup or deliberate no-op).

## SecretRecord updates (vault)
- `secret/data/hub/openshell-dex` — NEW: `github-client-id`, `github-client-secret` (org-owned GitHub OAuth App `openshell-authz`, callback `https://dex.tokyo-brunch.com/callback`).
- `secret/data/hub/openshell-github-oauth` — RETIRE at Commit D (orphaned after B).

## State machine

```
[before] KC realm+github IdP; any GitHub user → openshell-user role
 A: dex live (inert)                 ;gate config in git; smoke-tested inert
 B: gateway issuer → dex             ;LIVE GATE ACTIVE (org+teams enforced)
 C: KC decommission (only if B gates pass)
 D: vault/docs/orphan hygiene
rollback: revert B (and C if already applied?) — C is heavy: restore requires operator reinstall + vault record re-add + realm rebuild (documented disaster-recovery, not a first-class rollback). The DECISION GATE exists precisely to never need it.
```
