# Hermes Agent on minilab — deployment doc & evidence log

**Status**: S1 + S4 complete (always-on gateway with persistent state); S2 (Slack) awaiting workspace provisioning; S3 (Signal) awaiting account decision · **Started**: 2026-11-16
**Plan**: Option A — Hermes in an OpenShell sandbox on the minilab cluster via the
existing `minilab` gateway, GitOps-configured. NemoClaw dropped: its platform-support
matrix marks native Kubernetes/OpenShift deployments **Unsupported** (sandboxes are
host-local Docker containers; the lifecycle-authority contract is loopback-only;
source-level guard rejects gateway-endpoint overrides). NVIDIA's ecosystem guidance
directs platform-style deployments to "OpenShell (and your orchestration)" — exactly
this pattern.

**Image**: `ghcr.io/butler54/openshell-sandbox-hermes` — thin layer in the
[containers](https://github.com/butler54/containers) repo (branch
`007-hermes-sandbox-layer`): hermes v0.23.1 (commit-pinned), signal-cli v0.14.10
(sha256-verified), Temurin 25 JRE (manifest-digest-pinned), `hermes-gateway-start`
entry script (binds `HERMES_HOME=/sandbox/.hermes`, supervises the signal-cli
loopback daemon, execs `hermes gateway`).

**In-scope channels**: qwen inference (donnager-linux, direct IP), Slack
(socket mode, fresh workspace, wide-open initially), Signal (interactive QR
spike; allowlist +61408390624). **Out of scope (subsequent phase)**:
workstation `sandbox connect`/forward access.

## Gate 0 — preconditions (measured 2026-11-16)

**GATE0-1 — qwen endpoint reachability + policy shape (the plan's #1 risk)**:
probe sandbox `hermes-gate0` (standard image, throwaway) with exactly the
policy rule now in `charts/openshell-policy/policies/hermes.yaml`:

- `GET http://192.168.4.190:11434/v1/models` → `qwen-coder:latest` ✓
- `POST /v1/chat/completions` → `content: "GATE0_OK"` (reasoning arrives in
  the separate `reasoning` field — a thinking model; earlier empty content
  with max_tokens=10 was reasoning consuming the budget, not a failure) ✓

**Conclusion**: a plain IP-literal endpoint rule (`host: 192.168.4.190`, no
`allowed_ips`) is sufficient — OpenShell's SSRF private-destination block
admits exact-host endpoints. Node routing 192.168.5.0/24 → 192.168.4.0/24 and
OVN egress confirmed working. Read-write `protocol: rest` verified.

**GATE0-2 — state persistence (topology discovery)**: sandboxes on this
cluster are **node-level podman containers** (not k8s pods — verified: no
sandbox pods exist cluster-wide; sandbox root is an overlay under
`/var/home/core/.local/share/containers/storage`, user `core`), with
`/sandbox` a **podman named volume**
(`openshell-sandbox-<uuid>-workspace`) on the node disk:

- Marker file survived sandbox **stop → start** (verified live) ✓
- Therefore: hermes state (config, sessions, memory, signal-cli trust store)
  on `/sandbox` is durable across restarts. Only sandbox **deletion** clears
  the volume (documented lifecycle; rebuild = re-pair Signal, lose memory —
  acceptable v1 tradeoff).
- The reviewer's `workspaceDefaultStorageSize` PVC recommendation does not
  apply to this topology (no PVCs involved; the chart value is unused here).
  No gateway values change required.

**GATE0-3 — already-proven platform evidence**: OCP 5.0.1 (≥4.19 requirement),
agent-sandbox-operator v0.9.0, OpenShell 0.1.8 gateway healthy, sandboxes
working (feature 014 acceptance, 2026-11-16).

## Imperative steps (constitution II)

| # | Action | Rationale | Result | Reconcile-back |
|---|---|---|---|---|
| 1 | Gate 0 probe: `openshell sandbox create hermes-gate0 --from ghcr.io/butler54/openshell-sandbox:latest --policy /tmp/hermes-gate0-policy.yaml` + curl probes | Measure the SSRF/private-IP policy question and node routing before building anything (plan Gate 0.1) | GET + POST verified; policy shape proven (now in Git) | Probe sandbox deleted; policy promoted to `charts/openshell-policy/policies/hermes.yaml` |
| 2 | Gate 0 stop/start marker test | Verify /sandbox persistence semantics (plan Gate 0.2) | Marker survived; podman named volume identified | No state change; semantics documented above |
| 3 | containers PR #64 opened (branch 007-hermes-sandbox-layer) | Image build must follow the containers project process (GH Actions, PR-reviewed) | hermes-validate CI green on both arches after one fix (BASE_IMAGE ARG moved to global scope — stage-scoped ARGs are invisible to later FROM lines) | Awaiting operator merge; merge publishes ghcr.io/butler54/openshell-sandbox-hermes |
| 4 | minilab GitOps surface: charts/hermes-agent + policy + deploy driver (commits cb2ef8e, 2d56d0b); root-app selective sync of the new child Application (T030 playbook — the rhbk-stall pattern again) | All hermes config in Git per constitution I | hermes-agent app Synced+Healthy; hermes-agent-sandbox ConfigMap + hermes policy key live on cluster; ExternalSecret inert until hermes.slack.enabled | Desired state Git-declared; Argo-converged |
| 5 | S4 re-verify (2026-11-20): gateway re-login blocked by `invalid_redirect_uri` — KC `openshell-cli` client carried mid-URI port wildcards (`http://127.0.0.1:*/callback`), which RHBK 26.6 does not match; live fix via KC admin API PUT (redirectUris → trailing `:*` form), then Git reconcile (values-keycloak.yaml + test flips: auth-smoke XFAIL→PASS, realm-shape guard added) | Restore the browser login path needed to verify the always-on gateway posture (and unblock all k8s-gateway CLI work) | authorize endpoint 400→200 for loopback redirect_uris; CLI browser login completes; root cause of the "RHBK 26.6 bug" (observed 2026-09-27) recorded | Live PUT reconciled to Git in the same change (CR/Secret-level convergence only — KeycloakRealmImport is one-shot: import Job never recreated, kc.sh --override=false; future realm edits require an admin-API PUT, the established pattern since 2026-09-27) |

## S1 — sandbox deployed + qwen smoke (2026-11-16)

**Deployed**: sandbox `hermes` from `ghcr.io/butler54/openshell-sandbox-hermes@sha256:a8c6f65e…`
(PR #64 first publish; amd64/arm64 manifest, node is arm64). Config + .env
injected (Signal disabled — account blank; Slack absent — tokens unseeded).

**Measure-loop findings (each fixed in Git and re-measured)**:

1. **`/opt` filesystem access**: the hermes layout lives under `/opt`
   (checkout, tools, signal-cli, JRE); the default-deny filesystem policy
   blocked it. Fix: `/opt` added to `read_only`. NOTE: the **filesystem
   policy is fixed at sandbox creation** — network rules hot-reload, but an
   `openshell policy set` after creation does NOT re-open filesystem paths;
   the sandbox was recreated with the corrected policy.
2. **Policy L7 fields**: `protocol: tcp` endpoints reject `access`/`enforcement`
   (gateway validation, fail-closed at create). Fix: Signal endpoints carry
   only host/port/protocol/tls:skip.
3. **`sandbox create` trailing command** needs the `--` separator.
4. **The socket-opening binary is hermes' bundled tools python**: the
   `/usr/local/bin/hermes` launcher (`#!/usr/bin/env python3`) re-execs
   itself under `/opt/hermes/tools/python-3.14.9+…/bin/python3.14` — verified
   via a live traceback. The policy binaries now glob BOTH
   `/opt/hermes/tools/python-*/bin/python3*` and the runtime-injected
   `/sandbox/.uv/python/*/bin/python3*` (the sandbox runtime overrides PATH
   with its own venv). Symptom when wrong: hermes reports
   "Transient APIConnectionError" and retries — fail-closed egress, not a
   model problem.
5. **Hermes home is monolithic and records absolute paths**: install.sh with
   `HERMES_HOME=/opt/hermes` bakes /opt-absolute paths into the install
   state; a copied home at `/sandbox/.hermes` fails its environment check.
   Validated the fix shape live: path-rewritten copy at `/sandbox/.hermes`
   runs correctly (after clearing stale `__pycache__` from the build-python —
   "bad marshal data"). **Image fix required** (PR pending): build with
   `HERMES_HOME=/sandbox/.hermes`, keep a pristine copy at
   `/opt/hermes-pristine`, seed-on-first-boot in `hermes-gateway-start`.

**S1 result**: `hermes chat -q "Reply with exactly: HERMES_S1_OK" --oneshot
--provider custom -m qwen-coder:latest` → `☤ Hermes: HERMES_S1_OK` (2s,
e2e through policy v3). Raw-path verification: python urllib GET/POST +
SSE streaming to the qwen endpoint all 200/OK.

## S4 — always-on gateway + persistence (2026-11-16)

**Image**: seed-layout publish (PR #67) digest-pinned:
`ghcr.io/butler54/openshell-sandbox-hermes@sha256:ba3908eb…`.

**Deployed** (`deploy-hermes.sh gateway`): main process =
`hermes-gateway-start` → hermes-seed (first boot: pristine →
`/sandbox/.hermes`, `.seeded` marker, stale bytecode cleared) → signal-cli
daemon skipped (account blank) → `hermes gateway` exec'd under the seeded
home's tools python (PID tree verified: openshell-sandbox → hermes gateway).

**Measured**:
- Gateway boots cleanly (agent.log: checkout detection, home maintenance,
  plugin registration, kanban dispatcher embedded).
- **Persistence**: sandbox stop → start → `/sandbox/S4_MARKER` intact,
  `.seeded` intact (no re-seed), gateway auto-restarted (fresh agent.log
  boot entries). State on the podman named volume; only sandbox deletion
  resets (documented lifecycle).
- **Least-privilege note**: hermes' live model-catalog fetch
  (hermes-agent.nousresearch.com, raw.githubusercontent.com) is DENIED by
  policy — INFO-level, non-fatal, falls back to the shipped catalog.
  Deliberate: not required for the custom-pinned qwen model; add the hosts
  to the policy if live catalog/plugin listing is wanted later.
