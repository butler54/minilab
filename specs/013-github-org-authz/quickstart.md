# Quickstart: 013 github-org-authz validation gates

Run top-to-bottom. Every imperative (non-Git) action is pre-recorded here with exact commands (constitution §II) and must be echoed into the evidence log (`specs/013-github-org-authz/demo-log.md` — create at G1).

**Timing caution (minilab#9):** gateway sessions die ~50 min after login for the gateway CLI. The LIVE blocks (G4–G6) should be batched within one fresh-login window.

---

## G0 — static gates (before any live work)

- `make test-static` green; `./pattern.sh make validate-schema` → `All assertions passed`.

## G1 — GitHub-side prerequisites (IMPERATIVE — user actions, record: create GitHub OAuth App `openshell-authz` under org `tempest-concorde`)

- App type: **OAuth App**, org-owned (Settings → Developer settings → OAuth Apps, owned by tempest-concorde).
- Homepage URL: `https://dex.tokyo-brunch.com` · Authorization callback URL: `https://dex.tokyo-brunch.com/callback`.
- Record `Client ID`; generate a `Client Secret`.
- Dex's org check needs user's consent incl. org access: on first login, approve the org authorization for the app (GitHub "Authorize tempest-concorde" button) — one-consent-per-user GitHub behavior, recorded when observed.

## G2 — vault writes (IMPERATIVE — recorded commands)

Record a new vault record `secret/data/hub/openshell-dex` with properties:
`github-client-id` (G1), `github-client-secret` (G1), `kc-client-secret` (random ≥32-char).
(Same tooling used in 011/012 vault pushes; do NOT commit secrets to git.)

## G3 — Commit A (inert dex deploy): `values-prod.yaml` dex app + `overrides/values-dex.yaml` + `tests/test-external-refs.sh` dex pin

- Push; watch `openshell` context converge; `dex` pod Running in `openshell` ns; route `https://dex.tokyo-brunch.com/.well-known/openid-configuration` returns JSON (record first lines).
- Sanity: old login still works (short device-flow round; record output). If any of this fails: revert commit A, investigate, redo.

## G4 — Commit B (KC IdP cutover): `overrides/values-keycloak.yaml`

- IdP alias keeps `github`; providerId `github` → `oidc`; `authorizationUrl/tokenUrl/userInfoUrl` (or discoveryUrl) → dex issuer; KC client creds for dex RP injected via existing `realmPlaceholders` pattern (`KC_CLIENT_SECRET` → vault `openshell-dex.kc-client-secret`).
- Push → `rh-keycloak`/`openshell-keycloak-config`/`openshell` reconciled Synced+Healthy (≤15 min).
- LIVE member proof (contract C1): fresh `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` → expect full chain (GitHub → dex org check → KC) → `openshell status`/`sandbox list` success. Record timestamps + output.
- Note: if KC presents an "account already exists / link" prompt for butler54 (federated-id mismatch contingency), complete it once, then — only if the KC user lost role mapping — KC admin console re-grant `openshell-admin` (recorded).

## G5 — Commit C (LIVE gate-deny proof, contract C3) then revert

- Commit: `orgs: [{name: "tempest-concorde-x"}]` in dex values → push → sync.
- LIVE: new login attempt MUST be denied: device flow fails, no session, `openshell status` unauthenticated; capture dex deny log lines (`oc -n openshell logs deploy/dex ... | grep -i org`) + KC IdP error lines.
- Revert commit C (OR set back to tempest-concorde), push, sync, login works again (contract C1 re-shown; also SC-003 timing sample).

## G6 — observability + residual + close

- Capture (FR-006/SC-004): from dex logs the allow-line for the G4 login and deny-line for G5; KC-side upstream-error line for the deny.
- Assert (C5): `openshell*` + `rh-keycloak` apps all Synced+Healthy; gateway CLI works; no stale dex config drift; `make test-static` + schema gate green.
- Evidence log: fill run/timing tables; update `docs/openshell-demo-opencode.md` (login gets one extra redirect hop; commands unchanged); commit + push; close out.
- Deferred check (only if user adds a second GitHub identity later): true non-member round-trip (removes the last C3 caveat).
