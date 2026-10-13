# Data Model: GitHub org-restricted authorization (013)

## Entities

### GitHubIdentity
- **`id`** (numeric, GitHub user ID) — the federated key; flows as dex `sub` and KC federated userID. Invariants: the SAME GitHub account keeps the same id across the dex insert (identity continuity, enables relink of existing KC user `butler54`).
- `login` (GitHub handle), `email`.
- **`orgs[]`** — memberships as reported by GitHub (`GET /user/orgs` under the OAuth grant); authoritative at login time.
- **Membership in target**: `tempest-concorde ∈ orgs` (primary) ∪ team-membership of designated team under that org (fallback mechanism, same dex knob).

### AccessDecision
- `when` (timestamp), `identity_id` (GitHub uid), `decision` ∈ {allow, deny}, `reason_class` ∈ {member, not-in-org, verification-unavailable}.
- Produced by dex at every login attempt; observable in dex logs (and KC IdP-error logs for the deny class).
- Rule evaluation: **allow ⇔ `tempest-concorde ∈ identity.orgs`** (org mode) — nothing else matters (roles beyond `openshell-user` remain KC-side, unchanged).

### OIDCRelayChain (config invariants)
- **Keycloak client** openshell-cli/`k8s` gateway realm — unchanged (sessions/lifetimes as-is; #9 separate).
- **KC IdP alias `github`** — providerId swaps `github → oidc`, alias preserved; IdP mapper `github-to-openshell-user` untouched.
- **dex staticClient** `openshell-kc` — KC↔dex client credentials (single static client).
- **dex issuer** `https://dex.tokyo-brunch.com`; GitHub OAuth App callback `https://dex.tokyo-brunch.com/callback`.

### SecretRecord (vault, imperative-write, Git-referenced)
- `secret/data/hub/openshell-dex`:
  - `github-client-id`, `github-client-secret` — org-owned GitHub OAuth App (`openshell-authz`).
  - `kc-client-secret` — dex staticClient secret for the KC RP link.
- Legacy `secret/data/hub/openshell-github-oauth` — retained during transition; candidates for retirement in a follow-up (nothing reads it after cutover revert-window).

## State transitions (feature-level)

```
[before] direct KC↔GitHub IdP (no gate)
  --commit A (inert dex deploy)--> [dex live, no traffic] (safe intermediate: full rollback = commit revert)
  --commit B (IdP cutover)-------> [GATED: all GitHub logins pass dex org check]
  --commit C (gate-flip test)----> [deny-everyone, incl. operator] --revert--> [GATED] (proof retained in evidence log)
[rollback any point] = revert commits in reverse (C, B, A)
```

## Validation rules (from FRs)

- FR-002: gate precondition = dex `orgs[].name == "tempest-concorde"` (org mode) — assertion encoded in the values diff and checked by house static tests.
- FR-003: deny ⇒ zero session material downstream (structurally: KC never receives an id_token).
- FR-004: membership is fetched per-login by dex (no KC-side caching of the decision; KC session behavior unchanged).
- FR-007: through every transition, `openshell`/`-demo`/`-policy`/`openshell-keycloak-config`/`-platform` apps stay Synced+Healthy, and `rh-keycloak` reconciles its realm change live.
