# 012 Zen-free openshell-0.1.3-upgrade — Evidence Log

Feature: `012-openshell-013-upgrade` · Tracking: butler54/minilab#8 · Author: opencode(matilda) 2026-10-13

Delivery: direct commits on `main` (no feature branch, per Clarifications 2026-10-13).

## Run Table

| Run | Mode | Sandbox | Create→Ready | Fence (5min) | Query | Deny proofs | Teardown | Notes |
|---|---|---|---|---|---|---|---|---|
| _pending_ | | | | | | | | |

## Timing Table

| Gate | Budget | Actual | Verdict |
|---|---|---|---|
| SC-001 argo converge ≤15min | 15 min | _pending_ | |
| SC-002 gateway 0.1.3 | n/a | _pending_ | |
| SC-003 CLI 0.1.3 + tie-check | n/a | _pending_ | |
| SC-004 policy-at-create proof ≤5min | 5 min | _pending_ | |
| SC-005 zen smoke green | ~15 min | _pending_ | |
| SC-006 zero residual at close | n/a | _pending_ | |

## Baseline (pre-change, T002/T003)

- 2026-10-13 ~16:10 JST. `oc whoami` = kube:admin. openshell apps all `Synced/Healthy` (openshell, -demo, -keycloak-config, -platform, -policy).
- Gateway pod image: `ghcr.io/nvidia/openshell/gateway:0.1.1`. CLI: `openshell 0.1.1` (brew). helm v3.22.0.
- Gateways: `k8s` (https://openshell.tokyo-brunch.com, oidc) active; `openshell` local stale entry present (cosmetic).
- `make test-static` PASS (all suites incl. zen policy + pattern config).

## Version-Bump Commit

`655f432` on `main` (pushed) — 5-value atomic pin set 0.1.1→0.1.3. Gates: `make test-static` PASS, `./pattern.sh make validate-schema` "All assertions passed".

## Forced-Sync Record (constitution II — imperative step pre-recorded in quickstart G2)

- Trigger: 2026-10-13T07:41:31Z
  - `oc -n vp-gitops annotate application/openshell argocd.argoproj.io/refresh=hard`
  - `oc -n vp-gitops patch application/openshell --type=merge -p '{"operation":{"sync":{"prune":false}}}'`
- Convergence: `openshell` app Synced+Healthy at 07:42:30Z (**~59s**, SC-001 ✅ ≤15min). Chart-only bump; other openshell apps never left Synced/Healthy.
- 07:43:33Z gateway pod recreated: `ghcr.io/nvidia/openshell/gateway:0.1.3` Running 1/1 (SC-002 pod side ✅).
- Health spot-check (T010): all openshell pods clean, no CrashLoops. Non-Healthy list contains ONLY pre-existing `lvms-config` OutOfSync (010 incident, out of scope).

## Close Record

_pending_
