# Hermes Agent on minilab — deployment doc & evidence log

**Status**: deployed on the minilab cluster (S1c + S4c, 2026-11-23); S2 (Slack) awaiting workspace provisioning; S3 (Signal) awaiting account decision · **Started**: 2026-11-16
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

## Topology correction (2026-11-20)

**Every hermes measurement and deployment to date (Gate 0, S1, S4) ran on the
WORKSTATION's local podman gateway — the CLI's active gateway — not the
minilab cluster gateway.** Root cause: deploy-hermes.sh preflighted
`openshell status -g k8s` but every subsequent openshell command omitted
`-g`, so all mutations targeted the active (local) gateway. Corroboration:
the cluster gateway lists zero sandboxes; the cluster node's podman store is
empty; the local gateway listed sandbox `hermes` (created 2026-11-16 10:09).
Fixes: gateway registration renamed k8s → minilab (d5976fe) and
deploy-hermes.sh now pins the gateway on every invocation
(GATEWAY=minilab + OPENSHELL_GATEWAY export).

Evidence status:
- RETRACTED: "Node routing 192.168.5.0/24 → 192.168.4.0/24 and OVN egress
  confirmed working" (GATE0-1) — OVN was never in the measured path; the
  probe ran workstation→LAN.
- INVALID (local-only): GATE0-2 node-level-podman topology, named-volume and
  marker-persistence evidence; S1/S4 deployment, smoke and persistence
  narratives. Cluster-node sandbox topology and /sandbox persistence:
  re-measured below.
- STANDING (cluster-side, unaffected): GATE0-3 platform evidence; GitOps
  surface (imperative row 4); KC redirect-URI fix (row 5).

### Cluster re-measurement (2026-11-23)

Measured on the **minilab** k8s gateway (`GATEWAY=minilab`), not the
workstation podman gateway. Corrections to the local-gateway measurements:

- **Sandbox topology is a k8s pod pair + workspace PVC** (not node-level
  podman containers/named volumes): `os-supervisor-<uuid>` (500m/1Gi request)
  + `default--<name>` workload pod (agent container 500m/2Gi), plus PVC
  `workspace-default--<name>` (`lvms-loopback`, RWO, **10Gi** measured Bound)
  mounted at `/sandbox`. The GATE0-2 dismissal of the reviewer's
  `workspaceDefaultStorageSize` recommendation is **measurably wrong**: a
  pristine seeded home is **2.4G / 108,586 files** vs the chart's 2Gi default
  — the 10Gi workspace PVC is required (now live in `gateway.toml`).
- **The fail-closed bootstrap reaper has a hardcoded ~301s budget** for
  create→Ready. Both PVC provisioning (WFFC) and pod scheduling must fit
  inside it; the gateway kills the sandbox at +301s otherwise. Removing image
  pull time from that budget requires a node-side pre-pull (14.3GB image,
  `crictl pull` on the node — 1076s once, then kubelet does not re-pull).
- **Node CPU headroom gates the deploy**: node `sno` sat at 6316m/7500m (84%)
  requested. A namespace `LimitRange` (`openshell-defaults`) defaults
  **cpu 500m / memory 1Gi** onto any container without requests, so the sandbox
  **pod pair floors at ~1000m** regardless of the create flags. `--cpu`/
  `--memory` only size the **agent container** (the supervisor keeps its
  default). This is why dex was scaled to 0 (`69c7afb`, restore at spec 013 R3)
  → 1184m free, which scheduled immediately; an earlier probe with 684m free
  never scheduled (`FailedScheduling: Insufficient cpu`).
- **qwen reachability from the cluster pod**: `qwen-coder:latest` visible via
  the policy-authorized interpreter from inside the scheduled sandbox —
  measured in the probe and in `deploy-hermes.sh smoke` (PASS). Note `curl` is
  deliberately **absent** from the policy `binaries`, so curl-based probes are
  denied at `connect()` (EPERM); smoke now probes with the same python hermes
  uses.
- **Persistence is PVC-backed**: `stop` → `start` keeps `/sandbox` contents
  (marker + `.seeded` with unchanged inode/mtime → no re-seed) and the gateway
  restarts. Sandbox **deletion drops the PVC** (workspace recreated empty).
- **Cluster-specific seeding blocker — FIXED (image PR #69, 2026-11-23)**:
  `/opt/hermes-pristine` used to carry build-owned **0600 files (uid 998)**.
  The sandbox runtime runs the agent as **uid 1000870000**, so `hermes-seed`
  (`cp -a`, `set -eu`) hit `Permission denied`, exited non-zero, and
  `hermes-gateway-start` (`set -euo pipefail`) killed the main process →
  sandbox phase `Error` ~2 min after Ready (not the reaper). Local podman runs
  masked this. **Resolution**: containers PR #69 (merged 460192c) adds
  `chmod -R a+rX /opt/hermes-pristine` at build time — digest
  `sha256:0ee630ffb4e3a7e42cad662ea9047d716f277d3c46be38cce86b0e4863201e9c`
  (published 2026-11-23T04:16:55Z), validated in CI by a new arbitrary-uid
  seed audit. Verified by a fresh-PVC teardown+redeploy 2026-11-23: seeding
  ran as the sandbox uid (no root helper), `.seeded` owned by 1000870000, and
  the phase stayed `Ready` well past the old ~2 min failure point (row 10).
  The root-helper workaround (row 8) is retired.


## Gate 0 — preconditions (measured 2026-11-16)

**GATE0-1 — qwen endpoint reachability + policy shape (the plan's #1 risk)**:
(measured on the LOCAL gateway — see topology correction above; re-measured on cluster 2026-11-20)
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
(measured on the LOCAL gateway — see topology correction above; re-measured on cluster 2026-11-20)
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
| 6 | Capacity changes in Git for the cluster deploy: `workspaceDefaultStorageSize` 4Gi → **10Gi** (operator stability decision), sandbox create flags `--cpu 500m --memory 2Gi` in deploy-hermes.sh, node image pre-pull (14.3GB, 1076s), dex scale-to-0 (`69c7afb`, restore note at spec 013 R3) | Probe measured `FailedScheduling: Insufficient cpu` at 684m free, a pristine home of 2.4G vs the 2Gi default, and the hardcoded ~301s reaper window — each change removes one failure mode inside that window | 10Gi PVC Bound on every create; pods scheduled at +51s with 1184m free; create→Ready ~53s (probe) and 63.9s end-to-end (gateway stage) — well inside 301s | Argo Synced after each Git change; gateway restarted where needed; measurements recorded in the 2026-11-23 cluster re-measurement above |
| 7 | Cluster deployment (2026-11-23): probe `hermes-gate0c` → `deploy-hermes.sh gateway` → six-point verification | Replace the retracted local-gateway S1/S4 evidence with cluster-measured evidence (constitution I/II) | Probe: pod pair Running + PVC Bound(10Gi) at +51s, Ready ~53s, qwen OK. Deploy: PASS inject/gateway in 63.9s; main process then exited on the seed permission blocker (above) → one-time root helper seed (95s, 108,586 files/2.4G) → `stop`/`start` Ready in 12s. smoke PASS (binary paths `/usr/local/bin/hermes`, `/usr/bin/java`, `/opt/signal-cli-0.14.10/bin/signal-cli`; `qwen-coder:latest`; Hermes v0.23.1). Catalog fetch: hermes-agent.nousresearch.com 200 (617KB), raw.githubusercontent.com 200 (17.5KB) from the cluster pod; zero DENIED for those hosts (api.github.com DENIED as designed). Persistence: `cluster-S5` marker + `.seeded` (same inode) survive stop→start, fresh agent.log boot at 02:44. | Evidence in this doc; deploy-hermes.sh smoke fixed to probe via the policy-authorized python (commit with this row); image-side seed fix: **follow-up: containers repo, branch `007-hermes-sandbox-layer` — fix pristine-home ownership/permissions (chmod a+rX or chown) or make hermes-seed tolerant; gates S2 and any fresh-PVC deploy; interim: `deploy/openshell/hermes/seed-fixup-job.yaml`**. **Disposition (2026-11-23): fixed in the image — containers PR #69 (merged 460192c) ships the `a+rX` pristine home; fresh-PVC redeploy re-verified with no root helper (row 10).** |
| 8 | Out-of-band root seed executed on the PVC during row 7 (2026-11-23: root helper pod on `workspace-default--hermes`, `cp -a /opt/hermes-pristine/. /sandbox/.hermes`, `chown -R 1000870000`, `.seeded`) now codified in Git as `deploy/openshell/hermes/seed-fixup-job.yaml` | Constitution II: the imperative workaround must be reproducible from Git, not tribal memory — it gates every fresh-PVC deploy until the image fix lands | Committed Job manifest (same image digest, same PVC, same seed semantics incl. `.seeded` skip); deploy-hermes.sh gateway stage now prints the run-this-Job NOTE | No live change; the manifest reproduces the executed seed. Remove/re-run per deploy as needed; superseded when the containers-repo image fix ships. **Disposition (2026-11-23): retired — `deploy/openshell/hermes/seed-fixup-job.yaml` deleted from Git (history preserves it); superseded by the image fix (PR #69, row 10).** |
| 9 | Released-PV cleanup (2026-11-23): `oc delete pv pvc-263a6556-f45d-4415-b137-4170b3ae2e60 pvc-ade09096-7648-4429-bd3b-6783647447d5` — the two `Released`/`Retain` PVs whose claim was `openshell/workspace-default--hermes-gate0c` | Retain-policy Released PVs accumulate on the loopback-LVM SNO: the claim is gone but the LV and its 10Gi/4Gi allocate stay — dead weight on a capacity-constrained single node | Both deleted (`persistentvolume ... deleted`); `oc get pv` now shows only the Bound `workspace-default--hermes` (10Gi) plus the pre-existing Released PVs (matilda-smoke, egress-test, ux-c1 — intentionally untouched, they predate this work) | No Git reconcile needed; disk reclaimed. Ongoing hygiene: delete `Released` PVs from retired sandbox probes as they appear |
| 10 | Seed-permission image fix landed (2026-11-23): containers PR #69 merged 460192c → digest pin `ba3908eb` → `0ee630ff` in `charts/hermes-agent/values.yaml`; `deploy/openshell/hermes/seed-fixup-job.yaml` retired (deleted); current sandbox torn down (PVC dropped) and redeployed on a **fresh PVC** with no root helper | Close the seed-blocker follow-up (above) — it gated S2 and every fresh-PVC deploy; prove the fix end-to-end rather than inheriting the root-seeded workspace | Argo hard refresh → Synced/Healthy in 17s (04:18:50→04:19:05), ConfigMap `hermes-agent-sandbox` carries `0ee630ff`. Node pre-pull 420s (layers shared with `ba3908eb`; tag `<none>`, repoDigest `0ee630ff` on `a0efccc2`). Teardown clean: no sandboxes, `workspace-default--hermes` released (platform PVC untouched), no fixup Job anywhere. Fresh deploy: `deploy-hermes.sh gateway` PASS in 82s (04:27:55); pod `default--hermes` Running on `0ee630ff`. **Seeding without the root helper**: phase stayed `Ready` for 5m44s after Ready (created 04:26:38, still Ready 04:32:22 — 3× the old ~2 min Error threshold); `/sandbox/.hermes/.seeded` owned **1000870000:1000870000**, whole `.hermes` tree sandbox-uid, gateway running as `/sandbox/.hermes/tools/python-3.14.9+20261021-linux-x64/bin/python3`. smoke PASS (9s; Qwen `qwen-coder:latest`, Hermes v0.23.1). Catalog: `raw.githubusercontent.com` 200/12,435B and `nousresearch` root 200/617,315B via the policy-authorized venv python; no literal DENIED lines (failures are INFO-level, non-fatal). Persistence: `FINAL_MARKER` + `.seeded` (inode 10795242 unchanged) survive `stop`(6s)/`start`(8s → Ready); fresh gateway boot at 04:34. **Separate finding**: the gateway's real interpreter `/sandbox/.hermes/tools/python-*` is matched by **no** policy glob (`/opt/hermes/tools/python-*` does not exist in the seeded image), so the gateway's own qwen/Slack/catalog egress is denied at connect() — follow-up: add the seeded-home glob to `charts/openshell-policy/policies/hermes.yaml` binaries lists, then re-run the catalog check | Argo synced (Synced/Healthy), ConfigMap carries the new digest, image pin committed in Git; evidence recorded here; fixup Job removed from Git. Policy globs → follow-up row |

## S1 — sandbox deployed + qwen smoke (2026-11-16)
(measured on the LOCAL gateway — see topology correction above; superseded by the cluster re-measurement below)

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
(measured on the LOCAL gateway — see topology correction above; superseded by the cluster re-measurement below)

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
  2026-11-20: these hosts are now allowed (allow_hermes_catalog policy rule) per operator decision — see cluster redeploy evidence.
