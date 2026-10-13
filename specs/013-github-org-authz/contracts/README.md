# Contracts: 013 GitHub org-gated auth (Path B — dex-first, conditional KC decommission)

Behavioral contracts / hard gates. The Commit-C decommission is BLOCKED until all B-gates pass.

---

## C1 — Inert dex + direct smoke (pre-cutover, Commit A)

Dex deployment is healthy: discovery `/.well-known/openid-configuration` serves; a laptop browser-flow login via a TEST staticClient completes the GitHub→dex round trip with `groups` claim containing `tempest-concorde:openshell-users` for the operator account; the dex pod's logs record the allow. **Live gate must also prove the DENY branch**: temporarily set orgs to a nonexistent org in the dex values (commit), login fails with dex error page, revert.

## C2 — Gateway cutover (Commit B)

With `gateway.oidc.issuer=https://dex.tokyo-brunch.com` + `rolesClaim=groups` + team-mapped roles: `openshell gateway login` (default browser flow) completes (this is contract **V1 in action** — if the CLI still tries wildcard-localhost redirects against dex, this fails CLOSED and Path-B stops here); `openshell status -g k8s` = Connected/Authenticated; `openshell sandbox list` succeeds (user role); a privileged gateway op used by our runs (e.g. `openshell gateway info`) proves the admin role carried through. Web login path sanity via `https://openshell.tokyo-brunch.com` in browser.

## C3 — Decision gate (blocks Commit C)

ALL of: C1 ✔ C2 ✔, no `openshell`/`openshell-*` app OutOfSync/restart storms post-cutover (15 min soak), the gateway logs show JWT validation against dex keys (roles from groups), device-flow loss explicitly re-acknowledged by operator (spec clarification), zero openshell CLI regressions vs quickstart topology. **Only then Commit C may ship.**

## C4 — KC decommission (Commit C) + hygiene (D)

After Commit C sync: `keycloak-system` workloads gone (`keycloak-0`, postgres, operator), `openshell-keycloak-config`/`rh-keycloak` apps removed or pruned-true'd, **gateway still logs in via dex** (post-removal live login re-run), KC postgres PVC removed (recorded imperative), legacy vault record retired. Cluster has zero kc keycloak residuals except history.

## C5 — Observability (FR-006/SC-004)

Allow evidence (C1/C2 logins) and deny evidence (C1 nonexistent-org flip) present in dex logs and captured into the evidence log; post-commit-B gateway JWT-validation lines captured.

## C6 — Zero residual + static gates (SC-006 equivalent)

Empty openshell sandbox/forward lists, apps table healthy, `make test-static` + `./pattern.sh make validate-schema` green, vault manifests clean of orphaned references (`make test-static` external-refs coverage updated for dex pins).

---

## Non-contracts (explicitly out of scope)

- Claiming minilab#9 resolved (observe V4 only).
- True non-member GitHub-account round-trip (needs second identity).
- Team-based gateway role granularity beyond users/admins.
- KC rollback automation (C is one-way by design; recovery = manual re-provision per ops docs, documented).
