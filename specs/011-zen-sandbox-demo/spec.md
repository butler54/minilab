# Feature Specification: Zen Sandbox Demo and Server Mode

**Feature Branch**: `011-zen-sandbox-demo`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "Demonstrate the following: 1. a sandbox deployed using openshell cli; 2. That sandbox using opencode zen's free models to do a basic 'hi' query; 3. Remediate the network rules until that works; 4. Then deploy the opencode instance in server mode and access from a local opencode client and do a similar hi"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy a governed sandbox from the workstation CLI (Priority: P1)

The operator runs one scripted path on their workstation that authenticates to the
sandbox gateway and creates a fresh governed sandbox on the cluster, reaching a
ready state they can exec into. The path pre-verifies the authentication
prerequisite and reports clearly when a re-login is needed instead of failing
cryptically mid-run.

**Why this priority**: Nothing else in the demo exists without a live, CLI-created
sandbox. It is the independently demonstrable foundation ("look, governed sandbox
infrastructure works from my laptop").

**Independent Test**: Run the deploy script from a clean terminal; a named sandbox
reaches ready state, survives past the infrastructure's early-fencing window, and
accepts an exec/attach. Value delivered: proven CLI-driven sandbox lifecycle.

**Acceptance Scenarios**:

1. **Given** a valid gateway login, **When** the operator runs the deploy path,
   **Then** a sandbox is created, reaches ready, and is still alive 10 minutes
   later.
2. **Given** an expired gateway session, **When** the operator runs the deploy
   path, **Then** it stops before any mutation with an actionable re-login
   instruction.
3. **Given** the deploy path is re-run while a previous sandbox exists, **When**
   the operator invokes teardown, **Then** the prior sandbox is removed and the
   run remains idempotent.

---

### User Story 2 - Answer a basic query through a free hosted model from inside the sandbox (Priority: P1)

Inside the sandbox, the operator's coding agent answers a trivial prompt
("hi") using only the provider's **free** model tier. The sandbox's egress policy
is remediated iteratively — adding exactly the destinations the model traffic
needs and nothing more — until the query succeeds. Every remediation iteration is
recorded in Git with its justification.

**Why this priority**: This is the core demonstration: zero-cost model access
inside a *governed* environment, proving the network policy is precise enough to
permit exactly one external dependency while denying everything else.

**Independent Test**: Exec into the sandbox, run the query, and observe a model
response. Separately, attempt an unlisted egress destination and observe denial.
Value delivered: least-privilege, zero-cost AI inference behind a policy that
visibly works.

**Acceptance Scenarios**:

1. **Given** the sandbox from US1, **When** the agent is asked "hi" via the free
   model tier, **Then** a genuine model response is returned and recorded as
   evidence.
2. **Given** the final egress policy, **When** any destination outside the
   recorded allowlist is attempted from inside the sandbox, **Then** it is still
   denied.
3. **Given** the remediation loop, **When** a new destination is added to the
   allowlist, **Then** the change, the observed failure that motivated it, and
   its necessity justification are committed to Git before (or as) it takes
   effect.

---

### User Story 3 - Expose the agent in server mode and drive it from the local client (Priority: P2)

With the sandbox healthy, the operator starts the coding agent in server mode
inside the sandbox, connects their **local** client through the gateway's
supported connectivity mechanism, and repeats the "hi" query through the free
model tier — demonstrating a remotely-hosted, governed agent endpoint usable
from the operator's own tooling.

**Why this priority**: It extends the demo from "works inside the box" to
"usable as a shared, governed service" — the realistic operating shape for
sandboxed AI development. It depends on US1/US2 foundations but is an
independently demonstrable capability.

**Independent Test**: Start server mode in the sandbox, attach the local client
via the supported path, and run the same basic query end-to-end. Value
delivered: locally-driven, remotely-governed agent interaction.

**Acceptance Scenarios**:

1. **Given** the healthy sandbox and working model path, **When** the agent runs
   in server mode, **Then** the local client connects through the gateway-provided
   connectivity mechanism and lists its session
2. **Given** the attached local client, **When** the operator submits "hi",
   **Then** the free-tier model responds and the interaction is visible from
   both ends.
3. **Given** the demo is complete, **When** teardown runs, **Then** the server,
   sandbox, and any forwarding state are removed with zero residual resources.

### Edge Cases

- **Bootstrap fencing**: sandboxes can be deleted by infrastructure fencing
  during their first ~5 minutes if the control plane is briefly slow (documented
  upstream behavior). The deploy path must detect this and retry/recreate rather
  than present an orphaned demo state.
- **Ephemeral gateway state**: gateway-side profiles/provider registrations do
  not survive gateway restarts; the setup must recreate them idempotently.
- **Stale workstation credentials**: expired gateway sessions surface as opaque
  token errors (`invalid_grant`); the flow must pre-check and instruct re-login.
- **Free-tier variability**: free models can impose rate limits or availability
  changes; the demo must surface provider errors distinctly from policy denials
  so remediation never "fixes" the wrong layer.
- **Cold image pulls**: the first sandbox image pull on a cold node takes
  minutes; the demo communicates this instead of appearing hung.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The sandbox deploy, query, server-mode, and teardown paths MUST be
  automated as runnable assets committed to Git (constitution Principle II) and
  be safely re-runnable (idempotent create/teardown).
- **FR-002**: The sandbox egress policy MUST be least-privilege: it permits only
  the destinations required for the free-model query path and the
  bootstrap/runtime needs of the sandbox; every permitted destination MUST have a
  recorded justification in Git.
- **FR-003**: Remediation of the network rules MUST follow a recorded
  observe-diagnose-justify-apply loop: each blocked-destination observation is
  captured as evidence, and each resulting policy change is traceable to the
  observation that motivated it.
- **FR-004**: The demo MUST use the provider's free model tier only; no paid
  credential MAY be required, and no secret or token material may be committed
  to Git (any credential that proves necessary comes from the pattern's
  vault/external-secrets mechanism).
- **FR-005**: The deploy path MUST pre-verify gateway authentication and fail
  fast with re-login instructions when the session is stale, before attempting
  any mutation.
- **FR-006**: A basic "hi" query MUST produce an observable, recordable model
  response both interactively (US2) and via server mode (US3); the evidence MUST
  be captured into a committed demo log.
- **FR-007**: Server-mode access from the local client MUST use the gateway's
  supported connectivity mechanism (e.g. its port-forwarding/attach facilities);
  the demo MUST NOT create publicly reachable exposure (no public ingress for
  the sandbox server).
- **FR-008**: Policy assets MUST pass the pattern's static validation gates
  (including sandbox-network-policy linting for TLS, duplicate-host, and binary
  coverage issues) before they are applied; all Git changes land on `main` per
  the established GitOps flow.
- **FR-009**: Teardown MUST be complete and verifiable: after the demo, zero
  sandboxes, forwards, or demo-side resources remain, and this is proven by a
  post-teardown check.

### Key Entities

- **Sandbox**: A governed, ephemeral execution environment created through the
  gateway CLI; has a lifecycle (bootstrap-fence window, ready, teardown) and a
  network policy binding.
- **Egress Policy (allowlist)**: The set of permitted external destinations plus
  permitted in-sandbox binaries; each entry carries a justification.
- **Model Endpoint**: The free-tier hosted model service the agent queries;
  characterized only by the network destinations it requires.
- **Demo Session / Evidence Log**: The recorded narrative of runs — deploy
  timestamps, policy iterations, query transcripts, teardown proof — committed
  alongside the assets.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator completes the full US1+US2 demo (login → sandbox ready
  → first successful "hi") in under 15 minutes, excluding one-time cold image
  pulls.
- **SC-002**: Each successful "hi" query returns a model response in under 2
  minutes end-to-end from prompt submission.
- **SC-003**: 100% of egress attempts to destinations NOT on the recorded
  allowlist remain denied in the proof run (minimum 5 probes across distinct
  hosts).
- **SC-004**: From sandbox-ready, server mode plus local-client attach plus the
  server-driven "hi" completes in under 5 minutes.
- **SC-005**: Every policy remediation lands in Git with its motivating evidence;
  zero manual cluster mutations remain unreconciled at demo close.
- **SC-006**: After teardown, a cluster check shows zero residual sandboxes and
  zero residual demo resources; the post-teardown proof is included in the demo
  log.
- **SC-007**: All pattern validation gates pass on the final merged state
  (`make test-static`, schema validation), on `main`.

## Assumptions

- Target environment is the existing `sno` minilab cluster and its existing
  sandbox gateway (the same linkage proven by feature 008's demo).
- The free model tier is reachable without a paid account; if a lightweight
  token proves necessary, it is sourced through the pattern's vault mechanism,
  never committed (recorded as a discovered requirement if encountered).
- The 008-era operational knowledge (token TTL ≈ 1h, bootstrap-fence behavior,
  ephemeral gateway DB, CLI version pinning) still holds and is reused rather
  than re-discovered.
- Server-mode exposure stays private to the operator's workstation via the
  gateway connectivity mechanism; no shared/multi-user access is in scope.
- The demo is a single-operator, single-cluster demonstration; multi-cluster or
  multi-user operation is out of scope.
- Long-horizon sandbox endurance beyond the demo windows is out of scope (per
  the stabilization-first priority set in feature 010).
