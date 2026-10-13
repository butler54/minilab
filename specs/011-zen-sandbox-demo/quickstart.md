# Quickstart: Zen Sandbox Demo Validation

**Feature**: `011-zen-sandbox-demo` | **Date**: 2026-10-09

Runnable acceptance sequence. Gates G0–G6 map to spec Success Criteria; each
gate names its evidence sink (demo-log section). Runs on the operator
workstation against the `sno` cluster gateway.

## Prerequisites

- `make check-openshell-cli` (CLI == gateway chart 0.1.1)
- `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` (device flow; TTL 3600s —
  re-run on `invalid_grant`)
- `openshell status -g k8s` shows Connected + Authenticated
- Cluster reachable (`oc get nodes`), `openshell` ns healthy
- Repo state: this branch's assets present (`deploy/openshell/demo/zen/`,
  `policies/zen-demo.yaml`)

## G0 — Research spike capture (pre-demo, one time)

Resolve research D1/D2/D4 open items and commit results:
1. Keyless probe: attempt a zen `*-free` completion anonymously (no bearer);
   record outcome (accept / 401 / session-id requirement).
2. Model identity: resolve concrete free model id + base URL from
   `https://models.opencode.ai/api.json` + zen endpoint probe; write into
   `opencode-zen.json`.
3. Gateway transport: `openshell sandbox connect --help` / feature check for any
   TCP forwarding; record whether FR-007 default is viable or fallback engages.
4. Binary paths: short-lived probe sandbox, `readlink -f $(which curl node opencode)`
   — confirm 008 paths still resolve in the carrier image.

**Gate**: all four answers committed (demo-log "spike" section); `make test-static` green.

*(Repeated whenever the demo is re-run after >2 weeks — zen lineup rotates.)*

## G1 — Static gates

`make test-static` passes including `tests/test-zen-policy.sh` (contract Z1/Z2).
**Evidence**: command output in demo-log. Maps FR-008, SC-007.

## G2 — US1: CLI sandbox deploy

`deploy/openshell/demo/zen/run-zen-demo.sh` (interactive default) or `--smoke`:
- preflight PASS (auth pre-verified before mutation — FR-005)
- sandbox `Ready`; verified alive ≥5.5 min (fence window)
- policy applied via `openshell policy set --wait`

**Gate**: PASS lines + alive-past-fence proof in demo-log. Maps US1, SC-001 timer starts.

## G3 — US2: zen free-model 'hi' (remediation loop)

- First `hi` attempt with minimal policy; each deny captured
  (`OCSF NET:OPEN DENIED` excerpt), one justified rule added per iteration,
  each iteration committed (FR-003 trail).
- Terminal: model response returned, classified as provider-success
  (not policy-deny).
- Deny proofs: ≥5 non-allowlisted hosts attempted → all denied (rc=7 / NET:OPEN DENIED).

**Gate**: response transcript + iteration list + deny-proof count in demo-log.
Maps US2, SC-001 (≤15 min to first hi), SC-002 (≤2 min/query), SC-003 (100% denied).

## G4 — US3: server mode from local client

`deploy/openshell/demo/zen/run-zen-server.sh`:
- `opencode serve` running in sandbox (health probe from inside)
- forward established per contract Z4 (gateway path or recorded fallback)
- local `opencode attach` → submit `hi` → free-tier response
- interaction visible from both ends (local transcript + in-sandbox server log line)

**Gate**: ≤5 min sandbox-ready→server-hi (timer evidence); transcripts in demo-log.
Maps US3, SC-004.

## G5 — Teardown zero-residual (FR-009)

- `openshell sandbox list` empty; forwarding processes gone
- namespace check: no demo sandboxes/pods; vault seeds unchanged
- evidence-log committed

**Gate**: residual checks all PASS in demo-log. Maps SC-005, SC-006.

## G6 — GitOps landing

- All assets + evidence merged to `main` per repo flow (010 pattern:
  feature branch → merge → push; ArgoCD reconciles)
- `make test-static` + `make validate-schema` green on the merge commit

**Gate**: merge commit SHA recorded in demo-log + `tasks.md`. Maps FR-008, SC-007.

## Timing budget (SC-001 composite)

| Segment | Budget |
|---|---|
| login → sandbox Ready (G2) | ≤8 min (cold image pull excluded, one-time) |
| remediation → first hi (G3) | ≤7 min |
| **G2+G3 total** | **≤15 min** |
| G4 server hi | ≤5 min |
| per-query latency | ≤2 min |

## Rollback / bailout

- Stale token mid-run: re-login per Prerequisites, re-run (scripts idempotent).
- Fence-death during create: recreate in a calm minute (008 mitigation); if
  recurring, snapshot `openshell-0` logs per fence investigation doc.
- Zen lineup rotated / free model gone: re-run G0 spike, update template, proceed.
- Gateway-DB wiped (restart): preflight recreates provider/profile idempotently.
