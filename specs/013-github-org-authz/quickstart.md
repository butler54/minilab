# Quickstart: 013 (Path B) validation gates

Sequential. ✍ marks recorded imperative actions (constitution §II). Evidence goes to `specs/013-github-org-authz/demo-log.md` (created at G0; one row per Commit phase).

**Batching:** LIVE steps after Commit B share the token-lifetime hazard (minilab#9 symptom is KC-side; post-cutover observe V4) — run within one login window where possible.

---

## G0 — baseline (static + live inventory)

`make test-static`; `./pattern.sh make validate-schema`; snapshot app table (`oc -n vp-gitops get applications`) and KC workloads into evidence log.

## G1 — GitHub-side prerequisites ✍ (user actions)

1. Org `tempest-concorde` teams (imperative; spec-assumption authorized): create **openshell-users** and **openshell-admins**; add butler54 to both.
2. GitHub OAuth App **`openshell-authz`** (org-owned): homepage `https://dex.tokyo-brunch.com`, callback `https://dex.tokyo-brunch.com/callback`; capture Client ID + new Client Secret.

## G2 — vault writes ✍ (recorded commands)

New record `secret/data/hub/openshell-dex`: `github-client-id`, `github-client-secret` (G1). (No KC-client secrets needed — dex staticClients' secret for the CLI public client is `null`/public; verify static client secret needs at implementation.)

## G3 — Commit A (inert dex)

Edits: `values-prod.yaml` (dex app), NEW `overrides/values-dex.yaml` (issuer, github connector orgs:[tempest-concorde + teams], staticClients incl. a throwaway TEST client), `tests/test-external-refs.sh` dex pin. Push; confirm app Synced+Healthy, pod Running, discovery doc 200. Record C1-able discovery evidence.

## G4 — dex-direct smoke (LIVE, no cluster commits)

Browser login via TEST staticClient from laptop (gateway untouched): confirm GitHub consent incl. **org authorization prompt** (one-time callback consent — record occurrence), dex token with groups claim `tempest-concorde:openshell-users` (+ admins), dex log allow-line. Then gate-flip proof ✍C1: commit orgs:`tempest-concorde-x` → login DENIED (record dex deny log + failure UX) → revert commit. (This flip is the primary deny-proof, same as plan A design.)

## G5 — Commit B (gateway cutover)

`overrides/values-openshell-gateway.yaml`: issuer→dex, rolesClaim→groups, userRole/adminRole→team claims, audience→`openshell-cli` (confirm V2 audience mapping). Push; sync; verify charts healthy.

## G6 — LIVE cutover proof (LIVE, ≤1 token-window cohort)

`openshell gateway logout k8s` (clear KC session) then:
1. `openshell gateway login k8s` (DEFAULT browser flow — **V1 checkpoint**: redirect must resolve via dex; wildcard-localhost-detect failure = STOP → revert G5, fall back to Path A residue per plan).
2. `openshell status -g k8s` Connected/Authenticated; `openshell sandbox list`; `openshell gateway info` (admin role path).
3. 15-min soak: no app drift/restarts; capture gateway JWT-validation logs.
Record everything → contracts C2/C3.

## G7 — decision gate + Commit C (KC decommission)

Only if C1–C3 all green: commit removal of `rh-keycloak`/`openshell-keycloak-config` app blocks (and any KC realm leftovers), push, sync; verify `keycloak-system` workloads terminate; delete postgres PVC ✍ (recorded); post-removal RE-LOGIN via gateway (this is the irreversibility tripwire — run immediately); note `keycloak.tokyo-brunch.com` DNS/ingress disposition ✍ (remove or leave-stale note). If anything fails: **stop; do not force**; record; recover via history (operator reinstall) before retrying.

## G8 — Commit D (hygiene+close)

Retire vault record `secret/data/hub/openshell-github-oauth` references (and record itself once nothing reads it ✍); update `docs/openshell-demo-opencode.md` (new login topology, dex gates, teams-as-roles, browser flow primary; device flow gone); zero-residual sweep (C6); evidence log closure table; close spec.
