# Demo Log: Zen Sandbox Demo and Server Mode (011)

**Feature**: `011-zen-sandbox-demo` | **Started**: 2026-10-09

Evidence record per contract Z5. Each run appends; nothing is retro-written.

## G0 — Research Spike Answers

| Item | Result | Evidence |
|---|---|---|
| T002 CLI pin | **PASS** (0.1.1 == chart) | `make check-openshell-cli`; *but* gateway auth stale: `invalid_grant` + missing mTLS CA → re-login required (user action) |
| T004 zen keyless probe | **Conditional success** | curl keyless: `exo-free`→410 deprecated; `kimi/glm/trinity-*-free`→401 "not supported"; `ling-3.1-flash-free`→403 `FreeTierError: free tier only from within OpenCode` (UA/session-header spoofing also 403 — relay validates genuine client session). **Genuine opencode v2.0.20 workstation client: keyless `hi` → `ZEN_HI_OK` ✓.** Verdict: keyless works ONLY via a modern opencode client; no API key needed |
| T005 zen endpoint + model identity | **Resolved (DR2 rotated live)** | catalog `https://models.opencode.ai/api.json`: provider id `opencode`, base `https://opencode.ai/zen/v1`, 15+ `*-free` models. **2026-10-13 re-probe (T016 iter0)**: `ling-3.1-flash-free` (T005 pick) live on the relay but ABSENT from opencode 1.18.30's bundled registry → in-sandbox `ProviderModelNotFoundError` before any egress (zero network, <2s). New pick at intersection of bundled-registry × live relay: **`opencode/ling-3.0-flash-fin-free`** (both catalogs). |
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
| R2 (04:43Z) | batch | zen-1791869164 | 2s | died seconds after Ready (cause unclear; next runs healthy) | FAIL unknown (UnknownError err_14a50219) | **INVALID** (guards too weak at that commit) | vanished | gateway token died mid-batch; deny probes counted a deleted sandbox → exec-liveness guard added |
| R3 (05:31Z, T016 iter0) | `--setup`+query | zen-1791869467 | 2s | n/a (SKIP_FENCE_WAIT) | **FAIL classified: provider/model-catalog** — `ProviderModelNotFoundError: ling-3.1-flash-free` absent from opencode 1.18.30 bundled registry; zero egress attempted | n/a (deleted post-probe) | manual delete | curl zen direct under deny-all: `Immediate connect fail for 198.18.0.4: Permission denied` (sinkhole; policy deny live and fast) |
| R4 (05:32–05:43Z, T016–T019) | `--setup`+iter loop | zen-1791869553 | 2s | n/a | **PASS iter5** — `> build · ling-3.1-flash-free` → `ZEN_HI_OK` (single turn, transcript /tmp evidence below; wall 39s ≤ 2min ✓) | **PASS 5/5** (each `Immediate connect fail for 198.18.0.x: Permission denied`) | deleted; list empty | iterations 0–5 below; policy **effective** at close |
| R5 (05:45–05:50Z, T021–T024) | server mode | zen-1791870352 | 2s | n/a | **PASS** via local→forward→server (`ZEN_HI_OK`, ling-3.1-flash-free) | n/a (lifecycle reused) | forward stopped+port closed; sandbox deleted; list empty; zero stray procs | FR-007 gateway path confirmed; version-skew findings recorded |
| _pending_ | | | | | | | | |

### T018 terminal transcript (05:43:0xZ, zen-1791869553, policy v3)

```text
$ openshell sandbox exec -n zen-1791869553 -- sh -c 'cd /sandbox && opencode run "Reply with exactly: ZEN_HI_OK"'
> build · ling-3.1-flash-free
ZEN_HI_OK
```
Query wall time 39s (SC-002 ≤2 min, PASS). Provider-success classification: model response text, no ERROR-level lines, rc=0.

### T019 deny proofs (05:43:4xZ, same sandbox, exec-live guard passed)

```text
deny: example.com          (Immediate connect fail for 198.18.0.7: Permission denied)
deny: github.com           (Immediate connect fail for 198.18.0.8: Permission denied)
deny: pypi.org             (Immediate connect fail for 198.18.0.9: Permission denied)
deny: api.openai.com       (Immediate connect fail for 198.18.0.10: Permission denied)
deny: registry-1.docker.io (Immediate connect fail for 198.18.0.11: Permission denied)
deny count: 5/5 (SC-003 100%, PASS)
```

T020: **N/A** — keyless mode (T004/T006 verdict); no credentials exist to leak.

## US3 Server Mode (05:45–05:50Z, zen-1791870352, G4)

**T021/T022 — serve + transport**: `opencode serve --hostname 0.0.0.0 --port 4096` detached in-sandbox (`setsid nohup`, log `/tmp/opencode-serve.log`: "opencode server listening on http://0.0.0.0:4096"); in-sandbox health `http://127.0.0.1:4096/config` → 200. **FR-007 verdict: gateway-native forward CONFIRMED viable** — `openshell forward service $SB --target-port 4096 --local 4096`; local `curl http://127.0.0.1:4096/global/health` → `{"healthy":true,"version":"1.18.30"}`. `oc port-forward` fallback NOT needed.

**T023 — local drive (findings)**: local client 2.0.25 `run --server` → `ClientError: UnsupportedContentType: text/html` (**version skew**: v2 client expects API surface absent from server 1.18.30). Version-matched `opencode-ai@1.18.30 run --attach` connects (sees the model) but prints an empty assistant turn on this non-TTY capture. Demonstrated deterministically via the server's HTTP API through the same forward:

```text
POST /session                       → {"id":"ses_ecc31818bffebzjIZ3DJRjeitQ",...}
POST /session/ses_ecc31818/message (model opencode/ling-3.1-flash-free, "Reply with exactly: ZEN_HI_OK")
ASSISTANT: ZEN_HI_OK      (model ling-3.1-flash-free; local transcript above)
```

**T024 — teardown**: forward stopped & port closed (post-teardown `curl :4096` connection refused), sandbox deleted, `openshell sandbox list` empty, no stray forward processes.
## Policy Iterations (FR-003 trail)

| Iter | Denied destination (observed) | Rule added | Commit | Result |
|---|---|---|---|---|
| 0 | none — opencode failed locally (`ProviderModelNotFoundError`, 05:31Z) | n/a — model name fix (DR2), `opencode-zen.json` → ling-3.0-flash-fin-free | 4157cd1 | reclassified model-catalog |
| 1 | opencode.ai:443 (chat stream, AI_APICallError Cannot connect, 05:35:09Z) | `allow_opencode_ai_443` | 8ee04dc | policy v2 |
| 2 | models.opencode.ai:443 (models.dev transport error, 05:37:01Z) | `allow_models_opencode_ai_443` | f4a6ed6 | policy v3, model endpoits open |
| 3 | none — relay now answers: `Model is unavailable` (05:39:58Z). Relay probe matrix (workstation, keyless): FreeTierError=servable {ling-3.1-flash-free, muse-spark-1.2-contributor-free, cat-jam-free}; unavailable {ling-3.0-flash-fin-free, glm-5, qwen3.6, minimax-m3}; deprecated {mimo-v2.5→mimo-v2.6} | n/a — DR2 model switch → `muse-spark-1.2-contributor-free` (in bundled registry AND relay-servable) | fefe7d9 | rejected client-side (see iter4) |
| 4 | none — `muse-spark-1.2` rejected by client registry **but with a NEW list** (05:42:23Z: suggests muse-spark-1.3/cat-jam/exo) — discovery: with models.dev reachable, opencode refreshes its registry from the LIVE catalog (registry ≠ static bundle since iter2) | n/a — model → `ling-3.1-flash-free` (T005 pick, live on relay and now live in-client) | fefe7d9 | config switched |
| 5 (terminal) | — | n/a | current commit | **PASS `ZEN_HI_OK`** (transcript below, 39s) |

## Timing Budget vs Actuals

| Segment | Budget | Actual | Verdict |
|---|---|---|---|
| login → sandbox Ready (G2) | ≤8 min | ~2s (auth warm) / 6m22s incl. fence window | **PASS** |
| remediation → first hi (G3) | ≤7 min | ~11.5 min (05:31:07→05:42:34Z) | **EXCEEDED — deviation**: DR2 lineup rotated twice mid-loop (model-catalog + relay-availability failures required two model switches + relay probe matrix); spec assumption "chosen model remains valid" was violated *by the provider* during the run. Pure egress remediation was 2 iterations (~5 min) |
| **G2+G3 (SC-001)** | **≤15 min** | ~16.4 min setup-inclusive | **EXCEEDED — deviation** (same root cause as G3; excludes the earlier auth-wait interruptions) |
| sandbox-Ready → server hi (G4) | ≤5 min | ~3.2 min (05:45:56Z Ready → 05:49z ZEN_HI_OK via forward+API) | **PASS** |
| per-query latency (SC-002) | ≤2 min | 39s (terminal query) | **PASS** |

## G5 Zero-Residual Proof

Post-US3 (05:49:52Z): sandbox `zen-1791870352` deleted; `openshell sandbox list -g k8s` → "No sandboxes found"; `openshell forward list` → "No active forwards"; `pgrep -fl "forward service"` → none; `curl http://127.0.0.1:4096/config` → connection refused. Earlier runs R1–R4 each ended with an empty-list assertion. No demo pods (`oc get pods -n openshell` shows only `openshell-0` + completed probes), no policy residue beyond Git, no secrets anywhere (keyless design).

## G6 Merge Record

Merged `011-zen-sandbox-demo` → `main` at merge commit **ef6d169** (2026-10-13, --no-ff). All 29 tasks closed; evidence trail in this file; gates re-verified on main post-merge.
