# Feature Specification: Opencode Interaction Scenarios on Cluster Sandboxes

**Feature Branch**: `009-opencode-ux-scenarios`

**Created**: 2026-09-28

**Status**: Draft

**Input**: User description: "Openshell on k8s design approach — Design and document the best user scenario for interacting with opencode via openshell. 1. Primary interaction method today is via the TUI with sandboxctl; ignore sandboxctl complexities for now. 2. I want to be able to sustain using the opencode TUI whether via openshell connect or via opencode connected to opencode server. 3. Consider explicitly multiple sandboxes running at the same time which has worked well today with podman/sandboxctl. Do testing and write up documentation on recommended usage. Sandboxctl is not a consideration yet."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - TUI interaction shapes evaluated, tested, and a recommendation documented (Priority: P1)

As the lab operator, I want the opencode TUI to be a sustainable daily interaction path against cluster sandboxes, evaluated across the two supported shapes — (a) TUI running INSIDE the sandbox reached through an attach/command channel and (b) TUI/client running LOCALLY connected to an agent-server session that runs inside the sandbox — so that a tested recommendation exists for which shape to use for which work, rather than ad-hoc guessing.

**Why this priority**: The TUI is the operator's primary working interface ("primary interaction method today is via the TUI"). Without a validated default interaction shape, daily usage is brittle (loses sessions, unclear reattachment, unclear edits/save semantics). One clear tested recommendation unblocks routine use.

**Independent Test**: Driving both shapes against a cluster sandbox with the matilda-backed agent: each shape must (i) successfully show the interactive TUI, (ii) survive a detach/reconnect cycle with the in-flight agent session still intact, (iii) be assigned at least one demonstrated real task run, and (iv) have its limits recorded (e.g. input lag, scroll behavior, what disappears on disconnect).

**Acceptance Scenarios**:

1. **Given** a cluster sandbox running the governed agent config, **When** the operator attaches via the platform-attach channel and uses the in-sandbox TUI, **Then** the session is usable and remains usable after detach-and-reattach.
2. **Given** the same sandbox, **When** the operator runs the local client/TUI against the sandbox-hosted agent-server session (remote-attach shape), **Then** the TUI drives the remote session successfully, and detach-and-reattach reconnects to the same agent conversation.
3. **Given** both shapes tested, **When** the operator consults the documented recommendation, **Then** the doc records per-shape instructions, proven reconnect behavior, and a decision matrix (when to pick which).

---

### User Story 2 - Multiple concurrent sandboxes keep isolation and stability (Priority: P2)

As the lab operator, I want ≥2 agent sandboxes running simultaneously on the cluster — matching the local podman multi-sandbox working style — so that a failed or busy sandbox does not freeze other work and daily multi-context usage behaves the same as it does locally.

**Why this priority**: The operator already works multi-sandbox locally; the cluster deployment must not regress working style (the quota ceiling is deliberately 3, making concurrency a first-class mode, not an edge case).

**Independent Test**: Stand up two concurrent opencode-backed sandboxes with the governed config; drive an interactive session in each; independently prove for each sandbox (a) LLM access via the placeholder-injection model, (b) deny-listed egress attempts stay denied, (c) no cross-sandbox filesystem/policy leakage (one sandbox cannot see the other's workspace or config), and (d) cluster resource behavior stays healthy for the duration; then tear down both safely.

**Acceptance Scenarios**:

1. **Given** two concurrent sandboxes with the governed config, **When** both hold interactive agent sessions, **Then** both remain responsive and each form of proof (placeholder-only env, policy deny for non-allowlisted) holds per sandbox.
2. **Given** two concurrent sandboxes, **When** one sandbox's session makes a real LLM call, **Then** the other sandbox's session is unaffected (no throughput coupling or shared-state corruption).
3. **Given** concurrent sandboxes, **When** the operator deletes one, **Then** the other continues without degradation and residual state of the deleted sandbox is isolated.

---

### User Story 3 - Recommended-usage documentation shipped and tested (Priority: P3)

As the lab operator, I want a single authored documentation piece recording the tested interaction recommendations — connection shape decision matrix, day-to-day session management, multi-sandbox guidance, and known limitations — so that future usage follows written experience instead of rediscovery.

**Why this priority**: The value of every test in this feature compounds only when it's authored: an operator-facing recommendation document is this feature's deliverable output.

**Independent Test**: The documentation exists at a Git path, covers every P1/P2 acceptance dimension, and at least one reviewer reads it back for correctness against the live cluster (validate one interactive demo step directly from the doc).

**Acceptance Scenarios**:

1. **Given** the acceptance evidence from US1 and US2, **When** the doc is read back, **Then** each recorded limit is verifiably reproducible from its stated repro and each recommendation maps to evidence.
2. **Given** the doc, **When** a fresh contributor follows only the doc, **Then** they can attach to a sandbox interactively, exercise the reconnect behavior, and run concurrent sandboxes without external guidance.

### Edge Cases

- Attachable channel drops mid-generation (agent kept writing) — verify reconnect resumes the in-flight display rather than repeating work.
- Agent server inside sandbox dies/crashes while a local client is attached — the doc defines recovery (restart steps) rather than a mystery failure.
- 4th sandbox create attempt — must surface a deterministic, explainable refusal (quota ceiling), never a hang.
- Running TUI inside sandbox and the sandbox is deleted by another operator (or external ops) — behavior must be an explicit, readable failure, not silent.
- Local client loses network path to the cluster (WiFi blip) during a remote-attach session — define what's preserved and how to come back.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Both TUI interaction shapes (platform-attach into in-sandbox TUI; local TUI → sandbox-hosted agent session) MUST be exercised end-to-end on the cluster gateway with the matilda-anchored agent config, and outcomes (success/failure/per-shape limits) MUST be recorded.
- **FR-002**: Detach and reconnect behavior MUST be characterized and documented per shape: whether the agent session survives, how reconnect is performed, and what (if anything) visibly resets.
- **FR-003**: At least two concurrently running opencode-backed sandboxes MUST be demonstrated with per-sandbox proofs (placeholder-only credentials, allowlist-deny entre), consistent with the cluster's sandbox-concurrency quota ceiling; a 4th create attempt MUST be observed and recorded.
- **FR-004**: A recommendation document MUST be authored in Git (operator-facing) that contains: per-shape connect instructions, per-shape detach/reconnect recipes, a decision matrix, the multi-sandbox usage pattern, the quota behavior, and the known limitations table — each entry traceable to evidence gathered in US1/US2.
- **FR-005**: The interactive demo entrypoint(s) used for testing MUST land in Git as reusable operator scripts (may build on `deploy/openshell/demo/`), defaulting to the current carrier image and governed config, with required someday features (name override, image override, prompt override) flagged as env knobs.
- **FR-006**: Nothing in this feature MAY weaken the previously proven guarantees from `008-opencode-sandbox-demo` (env-var-only credential reference, placeholder injection, non-allowlisted egress denied, sandbox deletion cleanup) — the smoke path MUST be runnable during the multi-sandbox proof.

### Key Entities *(include if feature involves data)*

- **Interaction shape**: the evaluated connection mode (attach-in vs remote-attach) with its reconnect behavior, ergonomic profile, and documented limits.
- **Sandbox (interactive workload)**: one cluster sandbox instance carrying the governed agent config, optionally promoted for a live TUI session; identified and quota-counted.
- **Recommendation artifact**: the operator-facing Git doc recording the tested interaction guidance.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Both interaction shapes demonstrated end-to-end at least once each (0 open fails uncharacterized); per-shape behavior after a detach/reconnect cycle is observed at least once and recorded.
- **SC-002**: Two concurrent opencode sandboxes run simultaneously with all per-sandbox proofs passing (placeholder-only env, deny list, no cross-sandbox leakage), sustained for a contiguous ≥5-minute overlap window, observed via a recorded checkpoint.
- **SC-003**: The 4th concurrent sandbox create attempt produces a deterministic refusal recorded in notes (not a hang/indeterminate failure), happening in ≤60s from trigger to failed-state visibility.
- **SC-004**: The recommendation document exists in Git with ≥4 evidence-backed memory entries (each limit points at a repro) and ≤5 minutes from doc to first successful interactive attach for a reader following only the doc.
- **SC-005**: The previously proven 008 smoke remains green (`make validate-openshell-demo` passes once during this feature's wall clock, executed while any interactive test sandbox still exists to prove non-interference).

## Assumptions

- The governed agent config and matilda provider flow from 008 are the baseline for everything here (no new provider work).
- Cluster quota (`maxConcurrent: 3`) is the intentional concurrency ceiling and is asserted, not altered.
- sandboxctl is explicitly out of scope — testing targets the platform-native (openshell CLI) interaction paths only.
- TUI usability metrics are qualitative (usable/unusable after detach) rather than benchmark-grade latency; operator judgment is the verdict.
- The local client in the remote-attach shape is the current operator workstation (no additional device matrix).
