# Research: Zen Sandbox Demo and Server Mode

**Date**: 2026-10-09 | **Feature**: `011-zen-sandbox-demo`

All Technical Context unknowns resolved below. Sources: feature-008 repo assets
(as-is on this branch), opencode.ai docs, community reports (2025–2026),
live repo inventory.

## D1 — Zen free-tier access model (credential strategy)

**Decision**: Attempt **keyless `*-free` model IDs first** via a live probe in the
implementation spike; if anonymous access is rejected, fall back to a **free
OpenCode Zen API key** (account sign-up, no payment details) seeded in vault as
`secret/data/hub/openshell-zen` and delivered via ExternalSecret — satisfying
FR-004 (no *paid* credential; a $0-cost token is permitted by the spec's
Assumptions).

**Rationale**: 2026 reports conflict: opencode markets "free models included",
zen docs require a login/API key, community reports say keyless anonymous access
to `*-free` IDs was shut down ~2026-09, while others report the relay accepts
anonymous calls for `*-free` IDs only when no bearer is sent (401 if a non-empty
bearer is presented) and may require a session-ID header. Only a live probe
against the real endpoint settles it; both paths are FR-004-compliant, so the
spike decides with evidence and the chosen path is recorded in the demo log.

**Alternatives considered**: (a) Matilda provider reuse — violates the feature's
explicit "opencode zen free models" requirement; (b) assuming keyless works
without probing — contradicted by shutdown reports; (c) paid zen credits —
violates FR-004 spirit.

## D2 — Zen endpoint / model identity (probed, not assumed)

**Decision**: The exact base URL, provider id, and model id are **resolved
empirically in the spike** from opencode's own discovery
(`https://models.opencode.ai/api.json` plus the zen endpoint) and recorded in
`deploy/openshell/demo/zen/` assets. Expected shape from current docs/community:
OpenAI-compatible chat-completions endpoint on the opencode.ai domain, free
models as `<model>-free` IDs (e.g. `jev-1.13-free` pattern), referenced from
opencode config as a provider-configured model id.

**Rationale**: Model line-ups and ID spellings churn (limited-time free launches
rotate). Hard-coding from documentation snapshots was the cause of 008's
`ProviderModelNotFoundError`. The config template is verified by a probe step
before the demo runs (and re-verified whenever the demo is re-run).

**Alternatives considered**: pinning today's known free IDs — rejected, rot risk;
recorded as spike output instead.

## D3 — Egress remediation loop mechanics (FR-002/FR-003)

**Decision**: Start from `policies/sample-openai-only.yaml` (curl+opencode
binaries, zero endpoints) and run the recorded loop: run query → capture
supervisor `OCSF NET:OPEN DENIED` events → add the single observed
`host:port/protocol` rule with an inline justification comment (+ commit) →
repeat to success. Every rule in the final `zen-demo.yaml` carries a `justification`
comment naming the probe that motivated it; `binaries` entries use
kernel-resolved paths from 008's discovery (`/usr/bin/curl`, `/usr/bin/node`,
`/usr/lib/node_modules/opencode-ai/bin/opencode.exe` — re-verified in spike).

**Rationale**: Openshell denies egress by default; L7 `protocol: rest` is
mandatory for any credentialed endpoint (placeholder rewrite); the deny log is
the authoritative evidence source (008-proven). This *is* the demonstration of
"remediate the network rules until that works".

**Alternatives considered**: broad `opencode.ai` wildcard allow up-front —
rejected, it would demonstrate nothing and violates FR-002 least-privilege.

## D4 — Server-mode transport (FR-007 default vs fallback)

**Decision**: Spike first whether openshell 0.1.1 exposes any sandbox TCP
forwarding (`openshell sandbox connect --help`, gateway feature list). Repo
evidence strongly suggests **it does not** — `connect`/`exec` are the only
channels — so the expected landing is the sanctioned fallback:
`opencode serve --hostname 0.0.0.0 --port 4096` inside the sandbox,
`oc port-forward` to the sandbox pod (or its service) from the workstation,
local `opencode attach http://localhost:4096`. Gate the fallback on the recorded
spike evidence (per the clarify session: "decided by a planning-phase spike and
recorded with evidence"). Optional hardening: `OPENCODE_SERVER_PASSWORD` so the
forwarded endpoint is not unauthenticated on the workstation's loopback.

**Rationale**: This is the canonical opencode remote pattern (upstream docs and
issue-tracker consensus: serve + port-forward + attach). It requires **zero new
egress policy** (traffic enters via the k8s API port-forward, not sandbox
egress) and zero public exposure (FR-007's hard bound, both cases).

**Alternatives considered**: (a) Route/ingress — spec-forbidden; (b)
`openshell sandbox connect` + server inside the attach session — doesn't reach
the *local* client, defeating US3; (c) `oc exec` stdio bridge — fragile
workaround of a solved problem.

## D5 — Sandbox image and opencode availability

**Decision**: Reuse the 008 carrier image `ghcr.io/butler54/openshell-sandbox:latest`
(FROMS the digest-pinned NVIDIA community agent image used by the platform
chart; `opencode` npm-global already installed at `/usr/lib/node_modules/opencode-ai/...`).
Upgrade/rebuild only if the spike finds the in-image opencode too old for zen
free models or `serve` semantics — recorded if so.

**Rationale**: Cold starts cost minutes; version churn is the risk, addressed by
the probe — same discipline as 008 D1 advised.

**Alternatives considered**: new purpose-built image — constitution Simplicity
(no capability the existing image lacks is yet identified).

## D6 — Auth prereqs and known-cluster caveats (carried from 008/010)

**Decision**: Preflight asserts (in order): CLI pin (`make check-openshell-cli`),
`openshell status -g k8s` authenticated (else print the device-flow re-login:
`OPENSHELL_NO_BROWSER=1 openshell gateway login k8s`), gateway reachability,
and zen profile/provider existence on the gateway (recreate idempotently —
gateway DB is ephemeral, issue #7). Fence window accepted behavior: create →
verify alive past ~5.5 min before measuring success (008 quickstart pattern);
recreate on fence-death.

**Rationale**: All four failure modes are documented, recur regularly (feature
010 hit the stale token on 2026-10-09), and cheaply pre-checkable.

**Alternatives considered**: long-lived automation OIDC client — deferred (008
D7); alert-manager noise from `openshell` ns — cosmetic, unrelated.

## Resolved-by-research vs resolved-by-spike

| Item | Status |
|---|---|
| Zen credential path | **Spike** (keyless probe first; key path ready) |
| Zen endpoint/model IDs | **Spike** (discovery + probe) |
| Policy file shape, binaries, `protocol: rest` requirement | Resolved (008 contracts C6) |
| Remediation loop mechanics + evidence capture | Resolved (D3) |
| Server transport default/fallback logic | **Spike confirms**; fallback path designed (D4) |
| Image, auth prereqs, fence handling | Resolved (008 D1/D6 carry-over) |
