# V-DEMO acceptance log — 2026-09-27

Feature: 008-opencode-sandbox-demo. Gateway: k8s (openshell.tokyo-brunch.com, chart+CLI 0.1.1). Carrier: `ghcr.io/butler54/openshell-sandbox:latest` (FROM nvidia/openshell-community/sandboxes/base @aee...1fc, same digest as cluster default).

## Timed smoke sequence (scripted, run-demo.sh --smoke)

| # | Duration | preflight | create+policy | inject | agent | deny 5/5 | no-secrets | policy | cleanup |
|---|----------|-----------|---------------|--------|-------|----------|------------|--------|---------|
| 1 | 12.0s | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| 2 | 55.5s | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| 3 | 11.9s | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| 4 | ~40s* | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

*4th run via `make validate-openshell-demo` (wrapper target), all PASS.

SC-001 (<10min, 3-of-3) — PASS. SC-002 (zero key bytes) — PASS. SC-003 (≥5 deny probes) — PASS. SC-005 (`openshell sandbox list` empty after each run) — PASS.

## Evidence highlights

- `opencode run` inside sandbox prints `> build · matilda-code-1.0` then `OPENSHELL_VDEMO_OK` (exact match).
- Without injected config, the same sandbox fails `Cannot connect to API` (drift default → api.openai.com, policy-denied) — FR-001 observable.
- Sandbox env: `MATILDA_API_KEY=openshell:resolve:env:*` placeholder only; curl through placeholder returns HTTP 200 from matilda (placeholder rewritten at egress proxy).
- Denied egress shows supervisor `OCSF NET:OPEN DENIED` events.

## Implementation discoveries logged as defects/lessons

- sandboxctl 1.25.0 cannot express custom OpenAI-compatible LLM providers → butler54/sandboxctl#178
- openshell 0.1.1 gateway k8s-watcher resourceVersion-expired loop can saturate the API (reboots clear; API CPU dropped from ~3 cores to ~0.3 cores after gateway restart) — watch for upstream fix
- Sandbox names are length-capped (19 chars max) — template names stay short (`demo-<epoch>`)
- Keycloak realm default token lifespan 300s drove the recurring `Token is not active` friction — bumped to 3600s live + declaratively (values-keycloak.yaml)
- Gateway SQLite is ephemeral (pod restart resets) → re-register matilda profile+provider post-restart; vault credential driver (#7) is the durable fix
