# Hermes Agent on minilab — deployment doc & evidence log

**Status**: in progress (Gate 0 complete; image PR pending) · **Started**: 2026-11-16
**Plan**: Option A — Hermes in an OpenShell sandbox on the minilab cluster via the
existing `k8s` gateway, GitOps-configured. NemoClaw dropped: its platform-support
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
