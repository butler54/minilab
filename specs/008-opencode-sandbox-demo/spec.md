# Feature Specification: Opencode-in-Sandbox Demo (Matilda LLM)

**Feature Branch**: `008-opencode-sandbox-demo`

**Created**: 2026-09-27

**Status**: Draft

**Input**: User description: "Demonstrate running opencode in the sandbox using sandboxctl, if not openshell directly emulating sandboxctl until sandboxctl is fixed (you raise bugs instead). It's important to note the following: you will need to manually inject in the config for matilda as a LLM not the defaults for now."

## Clarifications

### Session 2026-09-27

- Q: Which gateway must the demo pass on to count as done? → A: Cluster gateway only; local podman gateway is an optional sandboxctl-compat smoke with no full proofs.
- Q: Interactive or batch agent session shape? → A: Both — interactive session is the primary demo experience; a non-interactive one-shot smoke must exist to make re-verification cheap and scripted.
- Q: Pre-built demo image vs runtime-injected config? → A: Runtime injection (Option B), but the carrier sandbox image is the operator's own `butler54/containers` sandbox image family (`ghcr.io/butler54/openshell-sandbox*`), not the stock NVIDIA community base. Image builds/version pinning are acknowledged to take time.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Governed coding agent completes a task against matilda (Priority: P1)

As the lab operator, I want the opencode AI coding agent to run inside a governed OpenShell sandbox, use the Matilda (Maincode) LLM endpoint configured via a manually injected config (not the agent's defaults), and complete a small coding task, so that the platform proves its core value proposition: a real AI agent doing real work under enforced egress and credential governance.

**Why this priority**: This is THE demonstration gate (V-DEMO) of the OpenShell lab deployment. All prior gates (auth, egress policy, credential injection) exist to make this moment meaningful. It exercises every runtime property end-to-end: sandbox scheduling, LLM-config injection, credential placeholder resolution, egress allow/deny, and event observability.

**Independent Test**: Create the sandbox with the injected agent config, run a one-shot coding prompt against Matilda, and confirm the agent's answer/tool output returns successfully while the sandbox egress is denied for any destination other than the Matilda API host.

**Acceptance Scenarios**:

1. **Given** an OpenShell gateway with the matilda provider registered and the matilda egress policy in Git, **When** a sandbox is created carrying the manually injected opencode Matilda config, **Then** the agent starts inside the sandbox and presents an interactive or one-shot coding session.
2. **Given** that running session, **When** the operator submits a small coding request (e.g. "write a python one-liner that prints OK"), **Then** the agent completes the request using the Matilda LLM and returns the generated artifact/output to the operator.
3. **Given** the agent session, **When** any process inside the sandbox attempts egress to a non-allow-listed destination, **Then** the attempt is denied and a denial event is observable.
4. **Given** the agent session, **When** the operator lists the sandbox's environment and files, **Then** no real LLM credential (key bytes) is present — only an opaque placeholder/reference.

---

### User Story 2 - sandboxctl-driven variant attempted, bugs recorded (Priority: P2)

As the lab operator, I want the same demonstration attempted through `sandboxctl` first, and when sandboxctl fails, the equivalent achieved with direct `openshell` operations that emulate sandboxctl's lifecycle — with each sandboxctl defect raised as an issue — so that the operator-preferred workflow regains track and sandboxes offered by the platform stay reproducible through the vendor-free path.

**Why this priority**: sandboxctl is the operator's established local tooling; keeping parity with it reduces divergence between local and cluster demo paths. Documented emulation keeps the demo unblocked while upstream is fixed.

**Independent Test**: Attempt a sandboxctl sandbox bring-up for the governed opencode demo; capture the failure precisely; file an issue per distinct defect; and demonstrate the same end-state via direct platform operations.

**Acceptance Scenarios**:

1. **Given** sandboxctl on the operator workstation, **When** the operator attempts to launch the opencode demo sandbox with the Matilda config, **Then** either it succeeds (demo proceeds through sandboxctl) or a concrete failure is captured with reproduction steps.
2. **Given** a captured sandboxctl failure, **When** the defect is recorded, **Then** a GitHub issue exists containing version, environment, repro steps, and expected-vs-actual behavior for each distinct defect blocking the demo.
3. **Given** sandboxctl remains broken, **When** the operator follows the documented emulation (direct sandbox creation, config injection, session start), **Then** the User Story 1 acceptance scenarios all pass without sandboxctl in the loop.

---

### Edge Cases

- Manual config injection into the sandbox filesystem/effective agent config fails or is overridden by agent defaults on startup — the demo must detect drift (agent ignoring the Matilda endpoint) and surface it loudly rather than silently using defaults.
- The Matilda endpoint is unreachable from the sandbox at demo time — the operator gets a clear diagnostic instead of an opaque agent error.
- The credential placeholder fails to resolve at egress time (stale provider registration) — the demo setup validates the provider attachment before starting the session.
- sandboxctl fails in ways that partially mutate local gateway state (stale DB records) — cleanup/reset steps must be documented so the emulation path starts from a known-good baseline (lesson from the 0.0.96 → 0.1.1 stale-state incident).
- The sandbox exits mid-session — the demonstration records what state survives deletion and what is intentionally ephemeral.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The demo MUST run an opencode agent inside an OpenShell sandbox reachable by the operator, with the agent's LLM target being the Matilda (Maincode) endpoint and model configured by a MANUALLY INJECTED config (the agent defaults pointing to public OpenAI MUST NOT be used).
- **FR-002**: The injected config MUST reference the LLM API key by environment variable name only (no inline key anywhere in the configured files), consistent with the credential-placeholder model already proven on the platform.
- **FR-003**: The demo MUST be achievable via two recorded paths: (a) `sandboxctl`-driven, and (b) direct platform operations emulating sandboxctl; path (b) MUST contractualize all setup steps (sandbox creation, config injection, provider attach, policy apply, session start) so they are repeatable by the operator and traceable in Git.
- **FR-004**: The operator MUST be able to run a bounded coding task (generate-and-show output) through the agent in under 10 minutes of setup from documented steps alone.
- **FR-004a**: The demo MUST support BOTH session shapes, with the interactive agent session as the primary demo experience (operator drives a live session) AND a non-interactive one-shot smoke (prompt in, response captured) that makes the acceptance criteria re-verifiable without manual interaction.
- **FR-005**: For every distinct sandboxctl defect that blocks path (a), an issue MUST be raised containing version, environment, reproduction, and expected vs actual behavior, linked from the feature notes.
- **FR-006**: During the entire agent session, egress to any destination other than the Matilda API host MUST be denied with observable events; the operator MUST be able to demonstrate this interactively during the demo (at least one live denied probe).
- **FR-007**: No real LLM credential MUST appear in the sandbox environment, filesystem, or args at any point; the operator MUST be able to prove this by inspection during the demo.
- **FR-008**: The manual config injection mechanism MUST be recorded as a version-controlled artifact (config file template + documented injection step), and MUST include the Matilda base URL and model identifier. The demo sandbox MUST run on the operator's own image lineage from `butler54/containers` (`ghcr.io/butler54/openshell-sandbox*`, opencode preinstalled), created with runtime injection of the LLM config (no demo-specific image rebuild required); config refinement MAY later graduate to a custom image bake, but that is out of scope here.
- **FR-009**: The demo MUST be deformable to a single cleanup command/documented sequence that removes the sandbox and leaves no residual state on the gateway.

### Key Entities *(include if feature involves data)*

- **Demo agent config bundle**: the operator-controlled opencode configuration (model, endpoint base URL, headers) injected into the sandbox; references the key only by env-var name. Lives in Git.
- **LLM provider registration**: the gateway-side named provider whose placeholder is what's actually visible inside the sandbox (already exists for matilda on the cluster gateway).
- **Sandbox egress policy**: the Git-versioned allowlist permitting only the Matilda host for the demo binaries (exists; may need binary extension for the agent runtime).
- **Demo runbook**: the repeatable ordered steps (create/config/apply/start/demonstrate-proof/clean) recorded for path (b) emulation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An agent answers a bounded coding prompt inside a governed sandbox, end-to-end in under 10 minutes of setup from documented steps, 3 times out of 3 attempts.
- **SC-002**: Zero real LLM credential bytes are observable inside the sandbox across env, filesystem, and process args during the run (operator-verified, 100% of checks).
- **SC-003**: 100% of non-allow-listed egress attempts from the sandbox are denied and observable (≥5 varied probes during the demo).
- **SC-004**: Every sandboxctl defect blocking the primary path is tracked in a raised issue (count matching the number observed during the attempt; zero unrecorded blockers).
- **SC-005**: Cleanup returns the gateway-to-lab baseline (no leftover sandboxes) in under 2 minutes via documented steps.

## Assumptions

- Primary execution target is the canonical cluster gateway (openshell.tokyo-brunch.com) — ALL acceptance scenarios and success criteria refer to it; the local podman gateway is only an optional sandboxctl-compat smoke target (attempt, record, no proofs required), since the matilda provider profile, egress policy, and admin OIDC auth are wired cluster-side only.
- The manual config injection is intentionally one-off/manual for this feature; declaratively packaging the demo config into a reusable sandbox template is out of scope.
- The demo sandbox rides the operator's `butler54/containers` `sandbox/*` image family (multi-arch, published to ghcr.io with opencode + heavy tooling preinstalled). These images are `latest`-tagged today; allowing time for image builds/pinning is accepted and does not block the demo path.
- The agent runtime's official config syntax (model/endpoint switching via config file + env var) is accepted as the supported integration surface; no agent code changes are in scope.
- Matilda account quota is available for demo-scale usage (single-agent coding task), and its API-key auth plus base-path shape remain unchanged.
- Bugs raised as issues target the appropriate upstream/project repository and reference concrete version information.
