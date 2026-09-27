# Data Model: Opencode-in-Sandbox Demo

## Artifacts (Git-owned surfaces)

### `deploy/openshell/demo/opencode-matilda.json` — opencode config template

| Field | Value | Notes |
|---|---|---|
| `model` | `matilda-code-1.0` (default), others out of scope | Must never point at OpenAI/openai default |
| `provider.matilda.options.baseURL` | `https://matilda.maincode.com/api/v1/code` | `/code` path; per-message-size constraint learned earlier |
| `provider.matilda.options.apiKey` | `{env:MATILDA_API_KEY}` | Placeholder at runtime inside sandbox |
| `provider.matilda.name` | `Matilda (Maincode)` | cosmetic |
| `provider.matilda.models` | map containing `matilda-code-1.0` | operator's agent UI model name |
| injected path inside sandbox | `/sandbox/.config/opencode/opencode.json` | HOME-level discovery layout |

### `charts/openshell-policy/policies/sample-matilda-demo.yaml` — egress policy (existing file)

| Field | Value | Needed for |
|---|---|---|
| `network_policies.allow_matilda_maincode_com_443.endpoints[0].host` | `matilda.maincode.com` | egress allow |
| `.protocol` | `rest` | gateway rejects L4-only credentialed endpoints |
| `.access` | `full` | allow+deny primitives |
| `binaries` | `/usr/bin/curl`, plus resolved `node`/`opencode` binary path(s) from D5 | supervisor `require_binary_identity` verdict |

### `deploy/openshell/demo/inject-config.sh` — injection script

Idempotent: takes `<sandbox-name>`, copies the template to `/sandbox/.config/opencode/opencode.json` inside the sandbox; verifies `grep matilda` on the landed file; exits non-zero on failure. Source of truth: Git.

### `deploy/openshell/demo/run-demo.sh` — demo entrypoint

Runs the scripted V-DEMO sequence in order: gateway health preflight → create-from-custom-image → inject config → apply policy → attach→interactive (or `--smoke` one-shot) → live deny probe → key-absence probe → cleanup. Env overrides: `SANDBOX_NAME`, `DEMO_SANDBOX_IMAGE`, `GATEWAY`, `MODE=interactive|smoke`.

### `docs/openshell-demo-opencode.md` — operator runbook

Prerequisites (vault seeds, provider registered, gateway reachable), setup, interactive demo, smoke, live proofs (egress deny, cred absence), cleanup, troubleshooting (token rotation, watcher recovery, image pull time).

## Live gateway state (not Git-owned, reconciled by imperative steps)

- Provider `matilda` with credential `MATILDA_API_KEY` (`openshell provider create` — one-time per gateway rebuild).
- Imported profile `matilda` (platform scope, from `deploy/openshell/profiles/matilda.yaml`).
- Active sandbox `demo-opencode-<ts>` (created/destroyed by run-demo.sh).

## Relationships

```
matilda provider (gateway, KEK-encrypted credential)
   └── referenced by provider profile "matilda" (platform scope)
        └── attached via --provider at sandbox create
             └── env MATILDA_API_KEY=openshell:resolve:env:* inside sandbox
                  └── read by opencode at runtime ({env:...} in injected config)
                       └── rewritten by egress proxy to the real key (L7)

opencode-matilda.json (Git) --inject-config.sh--> /sandbox/.config/opencode/opencode.json
sample-matilda-demo.yaml (Git) --policy set--> gateway policy engine --OPA--> allow/deny per exec
run-demo.sh (Git) orchestrates: preflight → create → inject → attach → proofs → cleanup
```
