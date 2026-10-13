# Contracts: GitHub org-restricted authorization (013)

Behavioral contracts the implementation must satisfy. Each is independently testable and maps to spec SCs.

---

## C1 — Member path (SC-001)

**Given** dex deployed, KC IdP repointed, all apps healthy
**When** the operator (`butler54`, known org member) performs `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` and completes the flow
**Then** the full chain GitHub→dex→KC→gateway completes, `openshell status -g k8s` shows `Connected` + `Authenticated`, and an existing capability check succeeds (e.g., `openshell sandbox list -g k8s` returns without auth error).

Evidence: session output lines in the feature evidence log.

## C2 — Gate config declarative + inert-until-cutover (SC-003, FR-005)

**Given** commit A (dex app + values + pin-assert) on `main` BEFORE any KC change
**Then** `openshell` app(s) show the dex workload Synced+Healthy within the platform's normal sync window (≤15 min cluster-wide), AND existing logins via the old KC GitHub IdP still work (inert intermediate: zero risk window).

Evidence: app table + pre-cutover login sanity note.

## C3 — Gate deny (synthetic negative, clarified SC-002)

**Given** the gated state (commit B live)
**When** the temporary commit C sets `orgs: [{name: "tempest-concorde-x"}]` (nonexistent org) and the platform syncs
**Then** an operator login attempt is DENIED — dex denies (org membership check fails), the browser/device flow shows the failure, and zero session material is issued (a subsequent `openshell status`/`sandbox list` against the new attempt fails). Reverting commit C returns normal operation.

Evidence: timeline (commit SHA, sync time, failed-login timestamp + error text) and dex pod log lines recording the deny decision (FR-006 observability of the deny branch uses this live run — it IS the deny event).

Note on mapping (Clarifications 2026-10-13): this is the full real deny chain evaluated against the real operator identity — the strongest available proof path since no second GitHub account exists; a classical "non-member GitHub account" round-trip remains a backlog nicety.

## C4 — Observability (SC-004, FR-006) + freshness (SC-005)

**Given** the C1 allow and C3 deny executions
**Then** the dex pod logs contain decision lines for BOTH (allowable token issued; deny with org reason), and KC logs correlate the upstream error for the deny run.

**Freshness form (SC-005)**: the gate decision follows configuration + GitHub truth at login time rather than any cached allow-list — demonstrated by the C3 flip in ≤ sync-window time (config-side freshness); GitHub-membership-side freshness is dex's per-login GitHub query (structural; real-removal test listed as deferred in plan).

## C5 — No regression (FR-007)

**Given** the entire sequence
**Then** at the end: `openshell*` ArgoCD apps + `rh-keycloak` Synced+Healthy; gateway image/CLI status normal; no openshell sandboxes or sessions harmed (pre-existing sessions untouched); static gates (`make test-static`, `./pattern.sh make validate-schema`) green.

---

## Non-contracts (explicitly out of scope)

- Gateway token/session lifetimes (minilab#9).
- Gateway-side authorization detail INSIDE openshell (providers/sandboxes untouched).
- Team-based granular gating (one-line values change if ever triggered; spec Assumptions).
- Removal of legacy `openshell-github-oauth` vault record (follow-up hygiene).
