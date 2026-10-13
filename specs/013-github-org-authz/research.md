# Research: GitHub org-restricted authorization for openshell

## R1 — Root mechanism decision: **dex as org-gated IdP hop**

- **Decision**: GitHub → **dex** (`dex/dex` chart, github connector with `orgs:` gate) → Keycloak (generic OIDC IdP) → openshell gateway.
- **Rationale**: Dex is the canonical, upstream-maintained implementation of "GitHub login restricted to org/team": its `github` connector natively enforces `orgs[].name`/`teams` membership **at every login** (fresh evaluation → FR-004), denies non-members before any token issuance (FR-003), and emits auditable deny events (FR-006). Keycloak stays exactly as-is on the client side (openshell talks ONLY to KC — zero gateway/client changes); KC's GitHub IdP block swaps providerId `github` → generic `oidc` pointed at dex's issuer.
- **Alternatives considered**:
  - **KC-only declarative**: ✗ impossible — GitHub OAuth emits NO org claims and RHBK 26's GitHub provider never calls the orgs API; IdP mappers only map *received* claims. Verified against realms + connector docs/probes.
  - **Custom Keycloak SPI (Java jar)**: ✗ custom code + image layering for one gate — violates house minimal-changes spirit; ongoing maintenance.
  - **Keycloak 26 "Organizations" feature**: ✗ that's KC-managed orgs/email-domain matching, not GitHub org membership.
  - **Org-owned GitHub OAuth App**: ✗ org-owned OAuth Apps do NOT restrict who may log in; third-party app restrictions gate org *data access*, still doesn't deny non-members a session (plus we need `read:org` scope consent anyway).
  - **Static KC allow-list (remove auto-openshell-user, hand-pick users)**: ✗ violates FR-004 freshness (no org-removal sync) and adds manual admin burden.

## R2 — Dex shape (verified current docs + chart)

- Latest chart `dex/dex` 0.26.0 (app 2.46.0) via `https://charts.dexidp.io`.
- Connector config (docs, current): `connectors: [{type: github, id: github, config: {clientID: $GITHUB_CLIENT_ID, clientSecret: $GITHUB_CLIENT_SECRET, redirectURI: https://dex.tokyo-brunch.com/callback, orgs: [{name: tempest-concorde}]}}]`.
- `orgs` and `teams` semantics confirmed from upstream docs (org-only gate + optional team scoping; `kan` switch to team with zero mechanism change — satisfies the spec's team-fallback story with one line).
- KC side: `staticClients` gives KC a client_id/secret (id `openshell-kc`); KC reads the same vault-secret keys via the existing `realmPlaceholders` pattern.
- dex storage: `kubernetes` type (CRS-backed) — no PVC/configmaps to manage.
- Deny UX: dex error page + KC upstream-failure surface — meets FR-003 "human-readable denial, no session material".
- Caveat noted (dex docs): "A user must explicitly request an organization give dex resource access." → ONE imperative GitHub-side step (OAuth App creation + first-consent org approval) — recorded in quickstart G1.

## R3 — House integration points (probed live/git 2026-10-13)

- **Secret pattern (existing, reusable)**: `overrides/values-keycloak.yaml` shows `extraSecrets` (ESO from vault path `secret/data/hub/openshell-github-oauth`) + `realmPlaceholders` for realm substitution. Dex gets its GitHub OAuth creds the same way (sync Secret into `openshell` ns, `env:` from the dex chart values), KC gets its dex-RP client credentials via a mirrored Secret.
- **Vault plan**: one new record `secret/data/hub/openshell-dex` with properties: `github-client-id`, `github-client-secret` (org-owned OAuth App), `kc-client-secret` (dex staticClient). Existing `openshell-github-oauth` keeps serving until cutover proves, then retirement is decided (leave until follow-up; low risk).
- **Hostname**: `dex.tokyo-brunch.com`, cert via house `acme` ClusterIssuer (same pattern as keycloak/openshell hosts).
- **Namespace**: `openshell` (co-located with gateway; auth chain of openshell, not of KC platform).
- **GitHub-side facts probed 2026-10-13**: org `tempest-concorde` exists, `butler54` is `admin`/`active` member and sole member; membership publicly visible (so OAuth `read:org` ∩ consent path is unblocked for the operator's own account — closed-membership edge case verified against the primary user).
- **Federated identity continuity**: dex github connector default subject = GitHub numeric user ID, matching KC github provider's linked userID format → expected seamless relink of existing KC user butler54; contingency recorded in plan (KC admin-console role re-grant if collision dialog appears).
- **Realm IdP structural change in Git**: replace `identityProviders[].providerId: github` block with generic `oidc` provider (alias STAYS `github` so the hardcoded-role IdP mapper `github-to-openshell-user` is untouched), adding `authorizationUrl/tokenUrl/userInfoUrl/jwksUrl` or discoveryUrl to dex. All declarative in the same file.

## R4 — Deny-proof strategy against the clarified SC-002

- **Live full-chain synthetic negative**: commit temporarily setting `orgs: [{name: tempest-concorde-x}]` (nonexistent org) → operator's own GitHub identity is by construction NOT a member → gateway login (device flow) MUST be denied → revert. Exercises: GitHub org API call, dex evaluation, deny page, no session issuance — real deny chain, real operator identity, zero need for a second GitHub account. Mapped to SC-002's clarified synthetic-negative semantics; fully revertable-by-commit (FR-005).
- **Evaluator-level log evidence**: dex logs record the failed-org decision; KC logs the IdP error; both collected into the feature evidence log (FR-006).

## R5 — Alternatives explicitly rejected at design time (record for auditors)

- dex `org:` legacy field vs `orgs:` — use `orgs:` (supports teams later, `org` and `orgs` are mutually exclusive).
- `loadAllGroups` — NOT needed (org-gate only); skipped keeps dex→github API surface minimal.
- Leaving KC's github→dex switch as a NEW IdP while keeping old one — ✗ preserves the open door; the old IdP block is *replaced* (FR-002 requires the gate on the sole path).

## R6 — Success-criteria mapping

- SC-001 member-login → dex member path, device-flow live test.
- SC-002 deny → R4 commit-flip proof + logs.
- SC-003 GitOps-on-main ≤15min → normal sync budget from 012 precedent (57s typical).
- SC-004 allow+deny events in logs → dex pod logs + KC pod logs captured in evidence log.
- SC-005 freshness-under-membership-change → same commit-flip mechanism validates; a real org-removal run only if user ever has a second member identity (documented deferred edge).
