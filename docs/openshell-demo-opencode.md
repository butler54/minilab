# OpenShell opencode demo (matilda LLM) — operator runbook

Demonstrates a human-air-gapped AI coding agent inside a governed OpenShell sandbox, using the Matilda (Maincode) LLM configured manually — never the agent's OpenAI defaults. Canonical for `008-opencode-sandbox-demo` / quickstart V-DEMO.

## Prerequisites (per gateway rebuild)

- CLI pinned to server: `make check-openshell-cli` (0.1.1 at time of writing).
- OIDC login: `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s`, verify `Status: Connected` + `Authenticated`.
- Matilda profile + provider on cluster gateway:
  - `openshell profile describe matilda` or import `deploy/openshell/profiles/matilda.yaml --global`
  - `openshell provider list | grep matilda` or `MATILDA_API_KEY=$(...) openshell provider create --name matilda --type matilda --global-profile --credential MATILDA_API_KEY` (source the key from `secret/data/hub/openshell-matilda`)
  - Note: gateway DB is ephemeral (no PVC, issue #7). Recreate after gateway restarts.

## One-time setup (per feature demo)

- Binary paths already pinned in `charts/openshell-policy/policies/sample-matilda-demo.yaml` (validated by T005 live probe: `/usr/bin/curl`, `/usr/bin/node`, `/usr/lib/node_modules/opencode-ai/bin/opencode.exe`).
- All other assets in Git: `deploy/openshell/demo/{opencode-matilda.json,inject-config.sh,run-demo.sh}`, profile `deploy/openshell/profiles/matilda.yaml`, policy `charts/openshell-policy/policies/sample-matilda-demo.yaml`.

## Scripted smoke (acceptance path, SC-001)

```bash
DEMO_PROMPT="Reply with exactly: OPENSHELL_VDEMO_OK" deploy/openshell/demo/run-demo.sh --smoke
```

Expected: all PASS lines (~12-60s per run): `preflight`, `create+policy`, `inject`, `agent`, `deny (5/5)`, `no-secrets`, `policy`, `cleanup`. Proven 2026-09-27 3-of-3 runs.

## Interactive demo

```bash
deploy/openshell/demo/run-demo.sh            # sets up and attaches (Ctrl-P Ctrl-Q to detach)
SANDBOX_NAME=<name-printed> deploy/openshell/demo/run-demo.sh --proofs   # proofs + cleanup
```

Inside the attached session: `opencode` TUI on `/sandbox` uses the injected `~/.config/opencode/opencode.json` (model `matilda/matilda-code-1.0`, provider matilda, placeholder apiKey).

## Live proofs worth showing

- Egress deny: `curl https://example.com` → rc=7; watch supervisor OCSF `NET:OPEN DENIED` events (`oc -n openshell logs <os-supervisor-pod>`).
- Credential absence: `env | grep -i matilda` → only `openshell:resolve:env:*` placeholder; `grep mc_live /sandbox -r` → nothing.
- Config-less drift: without injection, `opencode run` fails `Cannot connect to API` (defaults point at api.openai.com, denied by policy) — FR-001 observable.

## Cleanup

Sandbox deletion is idempotent (`openshell sandbox delete <name>`; exit-0 when absent). Everything under `/sandbox` is ephemeral per-sandbox.

## Troubleshooting

- **`Token is not active`** (refresh-token race): re-login. Token lifespan is realm-level `3600s` since 2026-09-27 (values-keycloak.yaml).
- **slow API/API-lag or watcher errors on gateway**: gateway pod restart (`oc -n openshift get pod -o name | grep kube`, then `oc -n openshell delete pod openshell-0`) — API server CPU recovers (watch-loop pattern, restart clears it).
- **`sandbox not found` at policy set**: create RPC slow at first image pull; run-demo retries internally.
- **Image pull latency**: first `ghcr.io/butler54/openshell-sandbox:latest` pull is multi-GB heavyweight (gcloud/Go/torch) — expect minutes on cold node; cached after.
- **OPA still denies after policy update**: rego needs BOTH endpoint yaml AND `binaries` entry matching resolved `/proc/<pid>/exe`; check supervisor log `OCSF CONFIG:PUBLISHED` and `/usr/lib/node_modules/opencode-ai/bin/opencode.exe` entry presence.
- **`ProviderModelNotFoundError`**: opencode models are `provider/id` — template MUST use `matilda/matilda-code-1.0` (fixed in template 2026-09-27).
- **sandbox name >19 chars**: gateway rejects at create (`demo-opencode-<epoch>` was 24 — fixed to `demo-$(date +%s)`).

## Emulating sandboxctl when it is fixed

`sandboxctl` normally orchestrates: image choice → config injection (git identity + agent config) → sandbox create → attach. Direct `openshell` emulation (this repo): `inject-config.sh` (config), `run-demo.sh setup` (create+policy+provider+image `--from`), `sandbox connect` (attach). Bugs observed while attempting it are raised as issues (see FR-005 tracking in the feature spec).

### Tracked sandboxctl gaps blocking this path (as of 1.25.0)

- butler54/sandboxctl#178: custom OpenAI-compatible LLM providers unsupported (matilda flow is the repro). The emulation in this repo stands in until its fix lands.
