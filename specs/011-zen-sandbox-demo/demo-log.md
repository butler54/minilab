# Demo Log: Zen Sandbox Demo and Server Mode (011)

**Feature**: `011-zen-sandbox-demo` | **Started**: 2026-10-09

Evidence record per contract Z5. Each run appends; nothing is retro-written.

## G0 — Research Spike Answers

| Item | Result | Evidence |
|---|---|---|
| T002 CLI pin | **PASS** (0.1.1 == chart) | `make check-openshell-cli`; *but* gateway auth stale: `invalid_grant` + missing mTLS CA → re-login required (user action) |
| T004 zen keyless probe | **Conditional success** | curl keyless: `exo-free`→410 deprecated; `kimi/glm/trinity-*-free`→401 "not supported"; `ling-3.1-flash-free`→403 `FreeTierError: free tier only from within OpenCode` (UA/session-header spoofing also 403 — relay validates genuine client session). **Genuine opencode v2.0.20 workstation client: keyless `hi` → `ZEN_HI_OK` ✓.** Verdict: keyless works ONLY via a modern opencode client; no API key needed |
| T005 zen endpoint + model identity | **Resolved** | catalog `https://models.opencode.ai/api.json`: provider id `opencode`, base `https://opencode.ai/zen/v1`, 15+ `*-free` models; chosen `opencode/ling-3.1-flash-free` (deprecated: exo-free; unsupported: kimi-k2.5/glm-4.7/trinity free) |
| T006 key-mode fallback | **Not needed** | keyless confirmed; no vault seed, no `apiKey` in assets (FR-004 cleanest form) |
| T007 gateway TCP-forward capability | **Resolved: gateway-native path exists** | openshell 0.1.1 ships `openshell forward` (`start/stop/list` + `forward service`: local TCP port → sandbox loopback over gRPC). FR-007 default path viable; `oc port-forward` stays recorded fallback |
| T008 binary paths | **PASS** | probe `zp-1791865835` (2026-10-13 ~04:35Z): `curl`→`/usr/bin/curl`; `node`→`/usr/bin/node` v22.22.1; `opencode`→`/usr/lib/node_modules/opencode-ai/bin/opencode.exe` v1.18.30 (DR1 floor confirmed live). Probe deleted; `openshell sandbox list` empty |

### Infrastructure findings 2026-10-13 (live-phase enablers)

- **FI1 — custom-image creates need an immediate policy** (root cause of this date's repeated `ConfigurationInvalid: Effective configuration could not be activated` failures, incl. two fence-style vanishings): a sandbox created with `--from <custom-image>` and NO policy is born with admission `rejected` (policy null/v0); the platform default policy auto-attaches only to the default image (verified: default-image `zpd-1791865721` → `accepted v1` → Ready with zero action). Fix: `openshell policy set` within ~20 s of create → admission flips `rejected`→`accepted v1` → Ready (verified `zp-1791865835`). 008-era scripts already did this with a retry loop; today's bare orchestration experiments made the requirement explicit. Folded into `run-zen-demo.sh` (T012) as a create→policy-set fast loop.
- **FI2 — exec syntax**: `openshell sandbox exec -n <name> -- <cmd>` (positional form mis-parses the name as the command).
- **FI3 — gateway restart/recreation does NOT clear the provider DB**: profiles `matilda/github/google-vertex-ai/vertex-claude` + providers survived a full pod delete (seeded or persisted; contradicts the 008 "ephemeral DB" caveat — keep the idempotent-create pattern anyway, it is harmless).
- **FI4 — gateway↔apiserver flaps persist post-010**: `kube_client … client error (SendRequest)` recurs every ~20–40 min in gateway logs (02:34Z/03:12Z/03:34Z/04:07Z…), apiserver steady at ~470m. Symptoms seen today: sandbox creates hanging ~300 s, status polls returning empty, sandboxes vanishing mid-provisioning. Gateway RBAC verified healthy (`can-i create/list/watch/get sandboxes -n openshell` = yes). Mitigation for the live phase: retry creates, keep the 5-min fence watch, treat the CLI create step as non-atomic.

### Discovered requirements (folded into plan as live risks)

- **DR1 — opencode version floor**: carrier image ships `opencode` 1.18.30 (008 era); the zen free-tier client-session validation is newer (post-2026-09). If the in-sandbox client is rejected (403 FreeTierError pattern), remediate by upgrading opencode inside the sandbox (`registry.npmjs.org` egress rule, justified by probe) — this IS the demonstration's remediation loop, not plan drift.
- **DR2 — free-tier lineup rots fast**: exo-free already 410 since catalog write; chosen model pinned in `deploy/openshell/demo/zen/opencode-zen.json`; re-run G0 model probe on any staleness symptom.

## Run Table

| Run | Mode | Sandbox | Create→Ready | Fence survival | Zen query | Deny proofs | Teardown | Notes |
|---|---|---|---|---|---|---|---|---|
| R1 (T014 G2) | `--setup` | zen-1791866112 | 2s | **PASS** (alive +5.5min) | n/a | n/a | **PASS** (empty list asserted) | preflight+provider+inject PASS; total 6m22s (04:35:12→04:41:34Z) |
| _pending_ | | | | | | | | |
## Policy Iterations (FR-003 trail)

| Iter | Denied destination (observed) | Rule added | Commit | Result |
|---|---|---|---|---|
| _pending_ | | | | |

## Timing Budget vs Actuals

| Segment | Budget | Actual | Verdict |
|---|---|---|---|
| login → sandbox Ready (G2) | ≤8 min | ~2s (auth warm) / 6m22s incl. fence window | **PASS** |
| remediation → first hi (G3) | ≤7 min | _pending_ | |
| **G2+G3 (SC-001)** | **≤15 min** | _pending_ | |
| sandbox-Ready → server hi (G4) | ≤5 min | _pending_ | |
| per-query latency (SC-002) | ≤2 min | _pending_ | |

## G5 Zero-Residual Proof

_pending_

## G6 Merge Record

_pending_
