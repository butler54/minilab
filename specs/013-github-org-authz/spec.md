# Feature Specification: GitHub org-restricted authorization for openshell

**Feature Branch**: `013-github-org-authz`

**Created**: 2026-10-13

**Status**: Draft

**Input**: "Configure authorization to openshell via github to be a specific set of users / groups. By members of tempest-concorde is the target. If not I can create a team under this org."

## Clarifications

### Session 2026-10-13

- Q: How should the DENY path be proven end-to-end given the operator is the org's sole owner and cannot remove himself? → A: **Application/evaluator-level negative only** — prove the deny path via the policy/mapping layer's evaluation against a fabricated identity claim plus its observable deny decision (option C); a live non-member GitHub round-trip is NOT performed; the operator is the sole org owner (`admin`/active — probed 2026-10-13) and cannot self-remove, so SC-002 is verified via the synthetic negative rather than a real non-member login.
- Q: Should feature 013 ship as direct commits to `main` (the 012 delivery model) or use the feature-branch flow with a fold-back? → A: **Direct commits on `main`** — same live-config-on-live-gateway shape as 012; the `013-github-org-authz` branch is folded into `main` and deleted at clarify time (precedent: 012); ArgoCD only converges `main` so live-gate activation is push+sync.
- Q: Keep Keycloak with dex as an upstream gate, or go dex-only and potentially decommission Keycloak? → A: **Path B with caveat** — run dex in **parallel** first, hard-test the gateway against dex (browser-flow login, roles, token validation), and **only then decommission Keycloak if the gate passes**; if dex-side login or role mapping can't be made to work (chief risk: dex has NO device-authorization flow, and dex staticClients can't express the CLI's wildcard localhost redirects), fall back to the Path-A arrangement (Keycloak stays as token/session authority with dex as its org-gated upstream) — the org gate is live in BOTH end-states.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Only org members get in (Priority: P1)

As the openshell operator, I want the openshell authentication path (the same one the CLI and the WebUI use) to accept **only GitHub identities that belong to the GitHub organization `tempest-concorde`**, so that no random GitHub user who discovers the gateway endpoint can obtain a session, create sandboxes, or use the shared lab resources.

**Why this priority**: Today any GitHub account that can reach Keycloak can complete the org-broker login (011/012 sessions all used the operator's own account; nothing gates *who* GitHub says "hi" for). The gateway is internet-reachable (`https://openshell.tokyo-brunch.com`), so identity-only authn is an open door. Restricting to a named org/team is the minimum viable control.

**Independent Test**: With the feature live, log in with the operator's GitHub account (org member) → session issues. Attempt the same flow with a GitHub identity that is NOT an org member → immediate denial with no usable session. (Per Clarifications 2026-10-13: the deny-path acceptance proof is executed at the evaluator/policy layer with a synthetic non-member claim — the live non-member GitHub round-trip is out of scope.)

**Acceptance Scenarios**:

1. **Given** the gateway is configured, **When** a GitHub user who IS a member of org `tempest-concorde` completes the login flow, **Then** a working session is issued and they can use the gateway normally.
2. **Given** the gate is configured, **When** the policy/mapping layer evaluates an identity claim for a user not in the org (synthetic/negative case), **Then** the evaluation produces an explicit DENY decision and the platform refuses to issue session material for that flow.
3. **Given** a denied attempt, **When** the user retries immediately, **Then** the denial is consistent (no race or replay produces a session).

---

### User Story 2 - Membership evaluated at login time (Priority: P2)

As the operator, I want org/team membership to be checked **at each login** rather than provisioned once, so that a user removed from `tempest-concorde` cannot mint new sessions afterward.

**Why this priority**: Repo-org churn is the whole point of group-based authz — removing someone from the GitHub org must end their ability to get new sessions without touching openshell config. (Revoking *existing* sessions is covered by the existing short token lifetime and is out of scope.)

**Independent Test**: Remove a test member from the org (or move them out of the team) → their next login attempt is denied; re-add them → login succeeds again. All without restarting or reconfiguring openshell.

**Acceptance Scenarios**:

1. **Given** a GitHub user was removed from the org by the org owner, **When** they attempt a new login, **Then** they are denied despite having logged in successfully before.

---

### User Story 3 - Declarative, auditable enforcement (Priority: P3)

As the operator, I want the restriction configured declaratively (GitOps, reviewed changes) and every allow/deny decision observable, so that a mis-login to the endpoint can be seen and the gate change can be rolled back by reverting a commit.

**Why this priority**: House constitution (GitOps-first) + audit value for a gateway whose blast radius is cluster-adjacent.

**Independent Test**: `git` history shows the enforcement config on `main`; gateway/IdP logs show allow AND deny events corresponding to live login attempts.

**Acceptance Scenarios**:

1. **Given** the feature is enabled, **When** at least one allow and one deny event occur, **Then** both are visible in platform logs with the GitHub identity and decision.
2. **Given** the config lives in Git, **When** the commit is reverted and the platform re-syncs, **Then** un-gated behavior returns without manual platform surgery.

---

### Edge Cases

- **GitHub API/back-channel unavailable at login time**: fail CLOSED (deny with service-unavailable-style feedback), never fail open.
- **Concealed/private org membership**: GitHub orgs can mark members "private". The verification method must be able to see them (the granted OAuth scope typically covers this), or the affected member falls into the team fallback — either way, a member must not be locked out because of visibility settings; the plan MUST verify this for the operator's own account first.
- **Team fallback**: user has pre-authorized creating a dedicated GitHub Team under `tempest-concorde` (proposed name `openshell-access`) **if** org-wide membership checking turns out infeasible with the chosen mechanism. The spec treats org and team mechanisms as interchangeable targets with identical behavior.
- **Break-glass**: cluster-admin (`kube:admin` / `oc`) and Argo CD access are unchanged; the restriction applies only to GitHub-federated logins into openshell (gateway session issuance), never to cluster-level admin paths.
- **Multiple concurrent restrictions**: if a future feature restricts further (per-repo, per-role), the group gate MUST compose (AND semantics), not be replaced silently.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every openshell session-issuing login path (interactive/WebUI and the CLI device-code flow — they share the same identity realm) MUST require a GitHub-authenticated identity.
- **FR-002**: Before issuing a session, the platform MUST verify the GitHub user's membership in org `tempest-concorde` (primary) — or, exclusively as the documented fallback, membership in a designated GitHub Team under that org — and deny identity issuance to anyone not matching.
- **FR-003**: Denied users MUST receive an immediate, human-readable denial (clear page or terminal-visible error text) and MUST NOT obtain a session, token, or sandbox capability at any point in the denied flow.
- **FR-004**: Membership MUST be evaluated fresh at each login (no one-time allow-listing of previously approved users that survives org removal). Existing-session refresh behavior is unchanged (governed by existing token lifetimes).
- **FR-005**: The enforcement configuration MUST be declarative and GitOps-managed (changes ship as commits to `main` and converge through the platform's standard sync path; no imperative console actions that leave no Git trace, except the one-time GitHub-side prerequisites like consenting OAuth scopes or creating the fallback team).
- **FR-006**: Allow AND deny decisions MUST be exportably observable (platform logs or events), attributing the GitHub identity and the decision.
- **FR-007**: Applying the restriction MUST NOT break: the operator's own login (butler54), existing sandbox operation for live sessions, or any platform/ArgoCD health (openshell apps remain synced/healthy through and after the change).
- **FR-008**: If the org-membership mechanism cannot see the operator's own (or any member's) membership due to GitHub privacy/scope constraints, the feature MUST fall back to the team mechanism rather than ship a lockout; the choice MUST be recorded in the plan.

### Key Entities *(include if relevant)*

- **GitHub Identity**: a GitHub account (login/username); carries org/team memberships of interest. Source of truth: GitHub.
- **Access Decision**: allow/deny + timestamp + identity + (on deny) reason class (non-member / verification-unavailable / other).
- **Gateway Session**: issued only after an allow decision; carries the same existing lifetimes (documented under minilab#9 follow-up).

## Success Criteria *(mandatory)*

- **SC-001**: The operator can log in and use openshell normally with the gate enabled (member path live-proven end-to-end).
- **SC-002**: The negative path is proven at the policy/evaluator level: a synthetic non-member identity claim produces an explicit DENY with no session material (live non-member GitHub round-trip explicitly out of scope per Clarifications 2026-10-13).
- **SC-003**: The full gate is expressed as GitOps config on `main`; converged to live state via the normal platform sync within 15 minutes of the enabling commit.
- **SC-004**: Both an allow and a deny decision are visible in platform observability (logs/events) with identity attribution.
- **SC-005**: Removing/re-adding the test identity's org membership flips login ability without any openshell-side change (freshness criterion).

## Assumptions

- **Primary target is org membership in `tempest-concorde`**; the dedicated-team variant is a scoped fallback only (the user would create the team on GitHub-side if they tell us to trigger it); behavior identical.
- GitHub is and remains the sole external identity source for openshell users (already the case via Keycloak broker) — no new IdP is introduced.
- Verification happens at login, not per-request; session lifetimes stay as-is (scheduled separately under minilab#9).
- Denial UX bar is "clear, actionable, human-readable" — not a compliance-grade error page overhaul.
- Any one-time GitHub-side prerequisites (OAuth scope consent, team creation) are small-and-recorded exceptions to "everything via Git" (GitHub-side objects are not cluster resources).
- The operator is currently the org `tempest-concorde`'s ONLY member and owner (probed 2026-10-13); the deny-path proof is bounded to a synthetic negative evaluation (no live non-member round-trip) unless a second GitHub test identity is added later.
- The openshell apps staying synced/healthy through the change is part of FR-007's no-regression scope and is verifiable via the same live checks used in features 011/012.
