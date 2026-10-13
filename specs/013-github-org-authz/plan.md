# Implementation Plan: GitHub org-restricted authorization for openshell (Path B — dex-first, Keycloak decommission conditional)

**Branch**: (direct-to-main per Clarifications) | **Date**: 2026-10-13 (rev B) | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/013-github-org-authz/spec.md` + Clarifications 2026-10-13 (Path B chosen by user)

## Summary

Gate openshell logins to GitHub org `tempest-concorde` members using **dex** as the direct OIDC issuer for the openshell gateway — with Keycloak retained only until the dex path is **proven in production**, then **decommissioned by commit** (Keycloak+postgres+RHBK operator, ~3 workloads and the whole realm/secret layer removed). If the dex-primary path fails any hard gate (chief risks verified below), the feature falls back to the Path-A arrangement (Keycloak stays, dex becomes its org-gated upstream); either final state delivers the org restriction.

KeyClarifications’ driver: gateway OIDC is a **generic JWT resource-server config** (`issuer`/`audience`/`rolesClaim`/`adminRole`/`userRole` — verified against helm-chart 0.1.3 values) — nothing Keycloak-specific. The daily `openshell gateway login` opens "the **edge proxy's** login flow" (fixed, gateway-hosted redirect — no wildcard problem), so dex's exact-match redirectURIs are satisfiable (verify at implementation — V-flag below).

## Technical Context

**Language/Version**: YAML/Helm only. **New components**: `dex/dex` chart 0.26.0 (dex 2.46.0) in `openshell` ns, `dex.tokyo-brunch.com` (acme issuer), GitHub connector `orgs: [{name: tempest-concorde, teams: [...]}]` and staticClients for the CLI/console. **Removed (conditional Phase D)**: `rh-keycloak` operator, `keycloak-0`, its postgres, `openshell-keycloak-config` app, KC realm GitHub IdP, legacy `openshell-github-oauth` vault record. **Roles model**: KC realm roles REPLACED by GitHub **team** membership — emitted via dex `groups` claim (`org:team-slug`), gateway `rolesClaim: groups`.

## Constitution Check

| Principle | Gate | Rationale |
|---|---|---|
| I. GitOps-first | **PASS** | All cluster changes via commits; imperative-only actions (GitHub team creation, OAuth App, vault writes, possible KC console cleanup) pre-recorded in quickstart. |
| II. Record imperative steps | **PASS** | Every imperative action — GitHub-side + vault + (potential) KC-admin concessions — spelled out in quickstart G-gates. |
| III. Helm-only, minimal | **PASS-with-tension flagged** | Decommissioning is a bigger diff than "add a gate", but the USER explicitly chose it with the parallel-first caveat; the decommit only ships after live proof. No custom images/code at any point. |

## Data Flow / Decision Chain

```text
(END STATE)
browser/CLI login → https://dex.tokyo-brunch.com (issuer)
  → GitHub OAuth (org consent, read:org) → dex orgs/teams check (deny = error page + log)
  → dex id_token: aud=openshell-cli, groups=[tempest-concorde:openshell-users(, openshell-admins)]
  → gateway validates Bearer (issuer=dex, rolesClaim=groups, userRole=tempest-concorde:openshell-users, adminRole=tempest-concorde:openshell-admins)
  → session/token handled by gateway side as today (lifetimes: dex defaults — watch item, may retire minilab#9)
```

## Phasing (commit plan — all on main, each revertable)

- **Commit A — inert dex**: values-prod dex app + `overrides/values-dex.yaml` + ESO secret + GitHub side prereqs done; dex live but unreferenced.
- **Dex-direct smoke (live, no cluster change)**: discovery doc, and a browser-flow login test via a TEST staticClient from laptop → verifies org gate + groups claims **before** pointing anything production at dex.
- **Commit B — gateway cutover**: `gateway.oidc.issuer → dex`, `audience` → dex staticClient id (verify value mapping), `rolesClaim: groups`, `userRole/adminRole` → team-claim strings. Sync; verify login+CLI+status+sandbox ops.
- **Decision gate (HARD)**: C1–C3 contracts pass ⇒ **Commit C — KC decommission** (remove keycloak-keyring apps: `rh-keycloak` subscription/operator apps, `openshell-keycloak-config`, keycloak ns); else **revert B**, keep dual stack (dex reachable, KC IdP rewired THROUGH dex in a follow-up feature if desired — Path A residue).
- Commit D (hygiene): remove legacy vault record references, docs updates, zero-residual sweep.

## Watch-items / Verification flags

- **V1 (must verify, Commit B implementation)**: gateway login flow's actual redirect URI — currently KC client carries `http://localhost:*/callback` wildcards (dex can't), but the CLI opens the **gateway edge proxy's** login flow (fixed URIs). If the edge flow still resolves to wildcard localhost for the CLI leg, dex staticClients can't satisfy it → learn the CLI's actual redirect via a Commit-B test login and decide Path-A fallback before further decommit.
- **V2 (token modeling)**: dex id_token `aud` is the dex client id; ensure `audience` matches `openshell-cli` staticClient id; confirm gateway `scopesClaim` semantics don't depend on KC-specific claims (`realm_access` gone → set `rolesClaim: groups`).
- **V3 (roles coverage)**: GitHub teams `openshell-users` + `openshell-admins` (create at G1, org `tempest-concorde`); dex connector teams list must include both; user must be in `openshell-users` to get ANY gateway access (userRole), `openshell-admins` for admin elevation. TODAY every GitHub user logged in as user — gate change intentionally shrinks access to org+team members.
- **V4 (#9 fallout)**: dex-issued id tokens/refresh lifetimes differ (`tokenExpiry` defaults in dex config) — note CLI session-lifetime behavior post-cutover against the ~50 min KC symptom; do NOT claim minilab#9 fixed, only observe.
- **V5 (KC removal severity)**: KC removal invalidates all KC-issued sessions (irrelevant post-cutover) and the KC admin UI paths referenced in older docs; docs updated in the same commit family. The vault `openshell-github-oauth` record + `keycloak-admin-user` secret become orphaned — removal follow-through is part of Commit C/D.

## Research

[research.md](research.md) — R1–R6 (dex mechanism, alternatives, deny-proof) + **R7 (why not Keycloak-only)** + **R8 (Path-B viability probes)**: gateway OIDC surface generic; CLI browser flow documented in CLI help ("edge proxy login flow"); KC openshell-cli wildcard-redirect constraint discovered and rerouted; device flow not implemented in dex (accepted trade-off, browser flow on laptop is the daily path).

## Follow-ups deferred

- minilab#9 (KC token idle) — superseded if B succeeds (KC is gone), else still open.
- OCSF deny-evidence (#3264/#3876 upstream).
- Real non-member GitHub-account round-trip (needs second identity).
