# Contracts: Demo Asset Surfaces

## C1. `deploy/openshell/demo/opencode-matilda.json`

opencode provider config. MUST parse as strict JSON (opencode may accept JSONC but the template stays strict-JSON for the Git-checked-in contract). MUST contain no secret material (apiKey always `{env:MATILDA_API_KEY}`). MUST NOT reference any host other than `matilda.maincode.com` (FR-001/SC-003). Lint gate: `python3 -m json.tool` must succeed; drift guard asserts `apiKey == "{env:MATILDA_API_KEY}"`.

## C2. `deploy/openshell/demo/inject-config.sh`

- Input: `<sandbox-name>` (positional), optional `CONFIG_TEMPLATE` (path, default `opencode-matilda.json` beside script).
- Behavior: `openshell sandbox exec -n <sandbox> -- mkdir -p /sandbox/.config/opencode`, then streams the template over exec-stdin to `/sandbox/.config/opencode/opencode.json`, then verifies presence and `grep -q matilda.maincode.com`.
- Exit 0 on success; non-zero any failure. Idempotent (re-running re-writes same content deterministically).
- No secrets handled: it emits only the template contents.

## C3. `deploy/openshell/demo/run-demo.sh`

- Modes: `run-demo.sh` (interactive: exits at the `sandbox connect` attach, then a RESUME entrypoint via `run-demo.sh --proofs` runs the proof set) and `run-demo.sh --smoke` (full automatic: one-shot prompt, proofs, cleanup without TTY).
- Preflight: `openshell status` connected + authenticated OIDC; fail-fast with device-flow hint otherwise.
- Creates sandbox: `--from "${DEMO_SANDBOX_IMAGE:-ghcr.io/butler54/openshell-sandbox:latest}" --provider matilda --detach --name "${SANDBOX_NAME:-demo-opencode-$(date +%s)}"`.
- Always: applies policy via `openshell policy set` from `sample-matilda-demo.yaml` repo path before any agent call.
- Smoke shape: `openshell sandbox exec -n ... -- sh -lc 'opencode run "$DEMO_PROMPT"'` capturing stdout; expected artifact present in output.
- Proofs-blocking cleanup: proofs MUST print PASS for (a) ≥5 varied denied egress probes (sc5003), (b) zero `mc_live` bytes in `env`/`/sandbox` files, (c) policy status `effective`.
- Cleanup: `openshell sandbox delete` unconditionally invoked on exit; non-fatal if absent (`exit 0` when sandbox never created).

## C4. `docs/openshell-demo-opencode.md`

Operator runbook sections, in order: Prerequisites → One-time setup (`provider profile import` + `provider create`, both flagged as conditional when already present) → Smoke path → Interactive demo → Live proofs → Cleanup → Troubleshooting (token rotation, watcher recovery, image pull latency, policy binaries hint when OPA still denies).

## C5. Requirements-to-artifact mapping

| FR | Contract artifact |
|---|---|
| FR-001, FR-002, FR-008 | C1 (config template), C2 (idempotent injection), research D3 |
| FR-003, FR-009 | C3 (two-shape scripted run, deterministic cleanup) |
| FR-004 | quickstart step 2; SC-001 §scripted smoke |
| FR-005 | issues raised on sandboxctl repo during P2 attempt (recorded in runbook) |
| FR-006, FR-007 | C3 proofs (deny probe, zero-key grep); SC-002/003 |
| FR-009 | C3 cleanup contract + SC-005 |

## C6. Egress policy binaries contract (D5)

The matilda policy file's `binaries` list MUST contain every executable resolved by `readlink -f $(which <tool>)` needed by demo probes: `/usr/bin/curl` minimum + the node/opencode entrypoint path(s) discovered in-plan. Test drift guard in `tests/test-openshell-render.sh` asserts list is non-empty and protocol is `rest`.
