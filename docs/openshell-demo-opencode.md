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
- **Sandbox disappears at ~4.5–5 min of age** (`rolled back stale fail-closed sandbox-runtime bootstrap` + `DeleteSandbox` in gateway log, preceded by `client error (SendRequest)`): NOT a sandbox/app problem. Root-caused 2026-09-27: transient apiserver→etcd gRPC stalls (30s-grid dial cancels, etcd watch compacted revisions) stall `GET sandboxes.agents.x-k8s.io` past the gateway's 30s read_timeout; the driver's fence reaper (`reap_stale_sandbox_runtime_bootstrap`, `SANDBOX_RUNTIME_BOOTSTRAP_GRACE=5m` const, no transient-failure tolerance) then deletes the bootstrapping sandbox. Only the 5-minute bootstrap window is lethal — sandboxes that complete bootstrap tolerate later flaps (Unknown → warn+retry). Mitigation for demos: create sandboxes ahead of the window; if a create dies, re-create and expect success in a calm minute. Full investigation record: `docs/openshell-fence-delete-investigation.md`. Upstream filing on hold pending user go-ahead (evidence-ready draft: `specs/009-opencode-ux-scenarios/upstream-issue-draft.md`; NVIDIA/OpenShell#3758 was filed then closed as premature).

## Emulating sandboxctl when it is fixed

`sandboxctl` normally orchestrates: image choice → config injection (git identity + agent config) → sandbox create → attach. Direct `openshell` emulation (this repo): `inject-config.sh` (config), `run-demo.sh setup` (create+policy+provider+image `--from`), `sandbox connect` (attach). Bugs observed while attempting it are raised as issues (see FR-005 tracking in the feature spec).

### Tracked sandboxctl gaps blocking this path (as of 1.25.0)

- butler54/sandboxctl#178: custom OpenAI-compatible LLM providers unsupported (matilda flow is the repro). The emulation in this repo stands in until its fix lands.

## Zen free-tier demo (feature 011)

Keyless OpenCode Zen `*-free` models inside a governed sandbox — no vendor
key, no vault seed. Driver: `deploy/openshell/demo/zen/run-zen-demo.sh`
(modes: default interactive | `--setup` | `--query` | `--proofs` | `--smoke`;
`SKIP_FENCE_WAIT=1` skips the +5.5 min fence proof for re-runs). Server mode:
`deploy/openshell/demo/zen/run-zen-server.sh` (serve :4096 in-sandbox +
`openshell forward service` + local attach hint + teardown). Assets:
`deploy/openshell/profiles/zen.yaml` (keyless provider profile),
`deploy/openshell/demo/zen/opencode-zen.json` (model pin),
`charts/openshell-policy/policies/zen-demo.yaml` (deny-all seed + justified
rules). Evidence: `specs/011-zen-sandbox-demo/demo-log.md`.

### Gotchas unique to the zen flow (all proven live 2026-10-13)

- **Custom-image creates are BORN admission-rejected** (FI1): with `--from
  <custom-image>` and no policy yet, gateway admission shows
  `ConfigurationInvalid: Effective configuration could not be activated`.
  Run `openshell policy set` within ~20 s of create (script does a
  concurrent retry loop). Default-image sandboxes auto-attach the platform
  default policy; custom ones do not.
- **Free-tier requires a genuine opencode client** but NOT any key: the
  relay answers direct curl with `403 FreeTierError`; the in-sandbox
  client session is accepted (even 1.18.30 — the DR1 auth fear was moot).
- **opencode's model registry is live-hydrated from models.dev**: under
  deny-all the client uses its BUILT-IN catalog (models.dev unreachable);
  once `models.opencode.ai:443` is allowed, the registry matches the live
  catalog. A model can be: valid-name-but-not-in-bundle (deny-all era),
  valid-everywhere, or relay-`Model is unavailable` — classify before
  touching the policy (`run-zen-demo.sh --query` does this).
- **Free-tier lineup rots within days**: on 2026-10-13 the relay listed but
  refused `ling-3.0-flash-fin-free`, `glm-5-free`, `qwen3.6-plus-free`
  (`Model is unavailable`) and deprecated `mimo-v2.5-free` same-day; the
  models that DO serve can differ daily (relay probe matrix in demo-log).
  If `hi` fails with `ProviderModelNotFoundError` or `Model is
  unavailable`, re-probe `https://models.opencode.ai/api.json` and the
  relay per-model with curl; fix is a `opencode-zen.json` model change,
  not a policy change.
- **Deny evidence is the supervisor sinkhole**, no supervisor pods in the
  current runtime: denied connects return
  `Immediate connect fail for 198.18.0.x: Permission denied` (per-host
  synthetic IP); `oc -n openshell logs <os-supervisor-pod>` from the 008
  era no longer applies.
- **Gateway-native forward for server mode** (FR-007 confirmed):
  `openshell forward service <sb> --target-port 4096 --local 4096` runs
  FOREGROUND — background it; `oc port-forward` fallback unnecessary.
  Client/version skew: opencode 2.x `run --server` against the 1.18.30
  in-sandbox server dies with `UnsupportedContentType: text/html`; use the
  version-matched 1.18 client (`npx opencode-ai@1.18.30 run --attach`)
  or the plain HTTP API (`POST /session`, `POST /session/<id>/message`).
- **exec syntax**: `openshell sandbox exec -n <name> -- <cmd>` (positional
  name is mis-parsed as the command).
- **Trust-but-verify deny proofs**: curl failures against a DEAD sandbox
  also count as "denied" — proofs require an exec-liveness probe
  (`exec true`) first; gateway records briefly outlive dead workloads.
