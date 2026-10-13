# Contracts: Zen Sandbox Demo Assets

**Date**: 2026-10-09 | **Feature**: `011-zen-sandbox-demo`

Contracts for the demo asset surfaces. Modeled on 008's `contracts/demo-assets.md`;
any conflict with an 008 contract resolves in favor of the stricter rule.

## Z1 — Agent config template (`deploy/openshell/demo/zen/opencode-zen.json`)

- Strict JSON (passes `python3 -m json.tool`); no comments; no trailing commas.
- Contains **zero** secret material: either no `apiKey` at all (keyless mode) or
  exactly the placeholder `{env:ZEN_API_KEY}`.
- References exactly one logical model host (the spike-resolved zen endpoint).
- Model id uses `provider/model-id` form (008 `ProviderModelNotFoundError` lesson).
- Static gate: `tests/test-zen-policy.sh` validates all of the above.

## Z2 — Egress policy (`charts/openshell-policy/policies/zen-demo.yaml`)

- openshell policy `version: 1`; deny-all default; allows enumerated only.
- Every `network_policies` rule: non-empty `endpoints` AND non-empty `binaries`
  (kernel-resolved paths); HTTP(S) endpoints use `protocol: rest`,
  `enforcement: enforce`.
- Every rule carries an inline `# justification: <probe/observation>` comment
  (FR-002/003 traceability); no wildcards; no duplicate `host:port` pairs.
- Rendered verbatim into the `openshell-policy` ConfigMap by the existing chart;
  applied imperatively by demo scripts (recorded, idempotent `-wait` set).
- Static gates: inherited `test-openshell-render.sh` glob + new
  `tests/test-zen-policy.sh` (lint rules above).

## Z3 — Demo driver scripts (`deploy/openshell/demo/zen/run-*.sh`)

- Modes: `run-zen-demo.sh` (`--smoke` one-shot US1+US2 with proofs+cleanup;
  default interactive), `run-zen-server.sh` (US3: serve → forward → attach
  instructions → teardown).
- Preflight fails fast, before any mutation, on: CLI version pin
  (`make check-openshell-cli`), unauthenticated gateway (prints device-flow
  re-login), missing zen provider/profile (recreates idempotently).
- Sandbox names ≤19 chars; create → verify-alive-past-fence-window before
  acceptance timers; unconditional cleanup on exit (idempotent delete);
  post-run assertion: `openshell sandbox list` shows no residuals.
- Every zen-query failure classifies the cause (policy-deny vs provider-error
  vs auth) so remediation never "fixes" the wrong layer (spec edge case).

## Z4 — Server-mode transport (US3)

- Default attempt: openshell gateway-mediated connectivity (FR-007). If the
  spike shows no such capability in 0.1.1, the recorded fallback is
  `oc port-forward` + local `opencode attach` (research D4).
- In all cases: no public Route/ingress; server binds inside the sandbox only;
  optional `OPENCODE_SERVER_PASSWORD` handed to the operator via the demo log's
  one-time instruction, never committed.
- The script prints the exact local commands and verifies the local attach with
  a probe query before declaring PASS.

## Z5 — Evidence log (`specs/011-zen-sandbox-demo/demo-log.md`)

- Each run appends: timestamps, mode, policy-rule iterations with their
  motivating deny events, query transcripts (prompt→response), deny-proof
  summary (count ≥5 non-allowlisted hosts), teardown residual check result.
- The log is committed with the run evidence per run, not retro-written.

## Z6 — Zen credential (only if D1 keyless probe fails)

- New vault seed `secret/data/hub/openshell-zen` documented in
  `values-secret.yaml.template`; ExternalSecret mirrors chart conventions of
  `openshell-matilda`; key never enters Git, the sandbox filesystem, or demo
  logs (placeholder-rewrite contract inherited from 008).
