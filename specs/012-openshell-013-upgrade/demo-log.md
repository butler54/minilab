# 012 Zen-free openshell-0.1.3-upgrade — Evidence Log

Feature: `012-openshell-013-upgrade` · Tracking: butler54/minilab#8 · Author: opencode(matilda) 2026-10-13

Delivery: direct commits on `main` (no feature branch, per Clarifications 2026-10-13).

## Run Table

| Run | Mode | Sandbox | Create→Ready | Fence (5min) | Query | Deny proofs | Teardown | Notes |
|---|---|---|---|---|---|---|---|---|
| T013/T014 | manual `--policy` birth | fix013-1791879341 | ≤60s (config 08:15:42Z, Ready at first get) | n/a (not zen agent) | n/a | github.com sinkhole-refused(birth); /usr DENY + /tmp OK | deleted, list empty | **U2 core PASS**: admission accepted, policy_version 1, policy_source "sandbox", our zen-demo hash 790c8e02… at birth, zero `policy set` calls |
| T015 | manual iterative-set | fix013b-1791879401 | ≤60s | n/a | n/a | n/a | deleted, list empty | same-content set = **no-op** (0.1.3 dedupe), changed content → version 2 loaded; retention intact |
| T019 r1 | smoke (racing model) | zen-1791879491 | 2s | SKIP | FAIL catalog (ling-3.1 rotated out at 08:17Z) | 5/5 | clean | DR2 rotation — registry+relay churned mid-session |
| T019 r2 | smoke (mimo-v2.6 pin) | zen-1791879851 | 2s | SKIP | FAIL catalog (mimo-v2.6 rotated out again at ~08:27Z) | 5/5 | clean | hydration-settle retry added; did NOT repair (registry rotation, not startup race) |
| T019 r3 | smoke (multi-candidate fallback) | zen-1791880154 | 2s | SKIP | **PASS ZEN_HI_OK via muse-spark-1.3-contributor-free** | 5/5 | clean | **SC-005 ✅** — config model +5-candidate fallback; live-verified serving set 08:22Z: cat-jam, mimo-v2.6-flash, muse-spark-1.3, big-pickle (mimo-v2 also listed) |

### DR2 addendum (012-evidence): free-tier catalog rotates at MINUTE granularity

Probe matrix in zp13-1791879602 @08:20–08:23Z served 4 models; zp15 @08:27Z showed mimo-v2.6 absent again; registry suggestions rotate per-run. Static single-model pins are unworkable on the free tier; the script's candidate-chain (commit `7c480b4`) is the durable design. `policy set` same-content dedupe + absent `-w` shorthand verified as 0.1.3 CLI surface changes.

### T020 OCSF toggle — ESCAPE HATCH TAKEN

`gateway.ocsfLog.enabled: true` (key path structurally verified against chart 0.1.3 values, analyze I1) converged but **renders zero ocsf wiring** in `helm template` output — dead value in helm-chart 0.1.3; gateway binary never writes `/tmp/gateway-ocsf.jsonl` (verified via distroless-safe debug). Reverted (`65917cf`), reconverged Synced/Healthy. Follow-up: track upstream #3264/#3876 for chart wiring, then re-enable with a values bump.

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

## CLI Parity (US2, T011/T012)

- `brew unlink openshell` (reversible: `brew link openshell`): brew formula lags at 0.1.1 and `/opt/homebrew/bin` would shadow `~/.local/bin`.
- **Findings (R3 corrected live)**: the Makefile's upstream fallback URLed a nonexistent `install.sh` release asset — latent defect, never exercised while brew carried the pin. Fixed in-repo to download the arch-appropriate release tarball, verify `openshell-checksums-sha256.txt` (`2eda3676…` for `openshell-aarch64-apple-darwin.tar.gz`, OK), extract `openshell` into `~/.local/bin`.
- `openshell --version` = `openshell 0.1.3`; `make check-openshell-cli` PASS (SC-003 ✅). Note: `~/.local/bin` must be on PATH (brew now unlinked).
- Gateway auth note: token expired pre-US3 (`invalid_grant: Token is not active`, minilab#9 symptom); fresh `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` required before T013. `openshell status` evidence for T009 collected post-login.

## Forced-Sync Record (constitution II — imperative step pre-recorded in quickstart G2)

- Trigger: 2026-10-13T07:41:31Z
  - `oc -n vp-gitops annotate application/openshell argocd.argoproj.io/refresh=hard`
  - `oc -n vp-gitops patch application/openshell --type=merge -p '{"operation":{"sync":{"prune":false}}}'`
- Convergence: `openshell` app Synced+Healthy at 07:42:30Z (**~59s**, SC-001 ✅ ≤15min). Chart-only bump; other openshell apps never left Synced/Healthy.
- 07:43:33Z gateway pod recreated: `ghcr.io/nvidia/openshell/gateway:0.1.3` Running 1/1 (SC-002 pod side ✅).
- Health spot-check (T010): all openshell pods clean, no CrashLoops. Non-Healthy list contains ONLY pre-existing `lvms-config` OutOfSync (010 incident, out of scope).

## Close Record

_pending_

## Close Record

- 2026-10-13 ~08:4xZ. **Feature complete on `main`.** All 25 tasks [X]. SC-001..SC-006: ✅ PASS (SC-001 ~59s; SC-002 pod+CLI status 0.1.3; SC-003 CLI 0.1.3 ~/.local/bin + tie-check; SC-004 ≤60s birth-with-policy; SC-005 smoke green incl. DR2 remediation within budget; SC-006 zero residual).
- Final sweep evidence: `No sandboxes found` / `No active forwards` / no stray forward procs; unhealthy apps list = `lvms-config` OutOfSync only (pre-existing 010 incident, out of scope); `openshell-0` Running `ghcr.io/nvidia/openshell/gateway:0.1.3`; `make test-static` PASS; `./pattern.sh make validate-schema` All assertions passed.
- Issue butler54/minilab#8 comment+CLOSED with evidence summary. Issue minilab#9 (OIDC ~50min token death) remains open for root-cause follow-up.
- Residual follow-ups for the backlog: (a) re-enable OCSF evidence channel once helm-chart wires `gateway.ocsfLog` (upstream #3264/#3876); (b) zen free-tier model-watch: candidate chain lives in run-zen-demo.sh query; serving set may need periodic refresh; (c) `brew` formula 0.1.3 catch-up → can `brew link openshell` again after update (unlinked state documented above).
