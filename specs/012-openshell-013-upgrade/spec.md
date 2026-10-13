# Feature Specification: Upgrade OpenShell Stack to 0.1.3

**Feature Branch**: none — direct commits on `main` (Clarifications 2026-10-13)

**Created**: 2026-10-13

**Status**: Draft

**Input**: "Based on issue butler54/minilab#8, minilab must be updated to openshell 0.1.3: update the GitOps deployment code, commit and push; force an Argo CD sync; validate that policy set at sandbox-create time is accepted, and fix if not."

**Tracking**: butler54/minilab#8 (policy-at-create + stack upgrade), feeds the simplification planned alongside it.

## Clarifications

### Session 2026-10-13

- Q: How should the 012 work land on `main` so Argo CD convergence and live validation can happen mid-feature? → A: Commit directly on `main` (no feature branch, no merge record); every staged change pushes to `main` as it becomes operative (GitOps: only `main` is converged by Argo CD).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform stack upgraded to 0.1.3 via GitOps (Priority: P1)

As the lab operator, I want every openshell version pin in the GitOps configuration (chart version and component image tags) raised to 0.1.3, committed and pushed, and the cluster reconciled by Argo CD — a forced sync if needed — so that the gateway and sandbox runtime on minilab sno run the current release with its upstream fixes (session-retry on startup, proxy/CAS retries, OCSF JSONL events, sandbox-leak fixes, optional cluster-scoped RBAC), without manual cluster mutations.

**Why this priority**: Until the platform is on 0.1.3, the policy-at-create validation has no meaning (behavior under test is version-sensitive) and the known 0.1.1-era faults that cost hours during feature 011 (gateway flaps, OCSF evidence gaps, sandbox leaks) remain unfixed.

**Independent Test**: `git log` shows the version-pin change; Argo CD reports the openshell applications as Synced+Healthy; the running gateway pod's image tag is 0.1.3 and the platform answers status requests. Observable without any further work.

**Acceptance Scenarios**:

1. **Given** minilab main at openshell pin 0.1.1, **When** the version-pin change is committed and pushed, **Then** Argo CD converges (with one explicit forced refresh/sync recorded in Git history or logs) and all openshell-related applications report Synced and Healthy.
2. **Given** the sync completed, **When** inspecting the gateway workload, **Then** its image tag is 0.1.3 and the platform responds to a gateway status inquiry successfully.
3. **Given** the prior 011 issue, **When** listing cluster state after sync, **Then** no manual drift was introduced: all desired state changes exist in Git (constitution I).

---

### User Story 2 - Workstation toolchain parity at 0.1.3 (Priority: P1)

As the operator's tooling, the openshell CLI installed on the workstation must match the chart-pinned version (0.1.3), enforced by the repo's existing version-tie check, so client/server skew never silently reappears.

**Why this priority**: The repo gates (`make check-openshell-cli`) deliberately fail on CLI/chart skew; an out-of-date CLI would block every downstream validation in this feature.

**Independent Test**: `openshell --version` reports 0.1.3 and `make check-openshell-cli` passes.

**Acceptance Scenarios**:

1. **Given** the workstation CLI is 0.1.1, **When** the pin-consistent update is performed, **Then** the version-tie check passes with no statement of skew.

---

### User Story 3 - Policy-at-create validated and adopted by demo flows (Priority: P2)

As the operator validating issue #8's central claim, I want to prove that creating a sandbox *with an initial policy attached at create time* results in a sandbox that reaches ready state with that policy in effect from the start — no admission-rejected window, no 300-second repair race — and I want the repo's demo flows (zen free-tier demo, 008 smoke demo) to prefer that mechanism for the *initial* policy while keeping post-create iterative policy updates working; if the at-create behavior fails, I want the failure root-caused and either fixed here or documented with the race-based fallback retained.

**Why this priority**: This is the functional justification of issue #8; it only becomes testable once US1 lands, and the demo simplification is the lasting benefit.

**Independent Test**: Create a sandbox passing a policy file at create; assert ready state with the policy active (verifiable by an egress attempt matching the policy decision) in a bounded time, with no policy-repair events; then run the zen demo flow end-to-end once to confirm the remediation loop still works.

**Acceptance Scenarios**:

1. **Given** an upgraded platform, **When** a sandbox is created with the policy supplied at create time (CLI flag or the documented environment variable), **Then** it reaches a usable state with the policy in effect from its first executable action, without `ConfigurationInvalid`.
2. **Given** that validation passes, **When** the repo's demo scripts are updated accordingly, **Then** the zen demo smoke path still passes (h="hi" answered; deny proofs; zero residual) and iterative post-create policy updates still take effect on the live sandbox.
3. **Given** the validation fails in a way not fixable here, **When** documenting the outcome, **Then** the scripts retain the existing create+policy-set fast loop and the failure is recorded in Git with upstream references.

---

### Edge Cases

- Upstream chart/service image 0.1.3 unavailable at the pinned OCI location → detect before sync; hold the change and document rather than breaking the running platform.
- Chart 0.1.3 introduces schema/incompatible value changes that the extraValueFiles no longer satisfy → render validation must catch this before push (static gates fail → fix values accordingly).
- CLI 0.1.3 not yet installable through the normal workstation channel → document the channel/version pin used rather than silently downgrading the check.
- Upgrade restarts the gateway while sandboxes/supervisors from 0.1.1 exist → teardown-before-upgrade as needed; zero residual verified afterward.
- Gateway/CLI auth token expiring mid-validation (issue #9 territory) → batch validation work tightly after login; preflight guards already exist.
- Argo CD self-healing/concurrency: forced sync is an imperative step and must be recorded (constitution II).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: All openshell version pins declared in Git — helm chart version in the pattern values and each component image tag in the gateway values override — MUST target exactly 0.1.3, from the same trusted, version-pinned upstream source (`oci://ghcr.io/nvidia/openshell/helm-chart` and `ghcr.io/nvidia/openshell/*` images). Unrelated charts that happen to share the 0.1.1 version string (e.g., `ztwim`, `rhbk`) MUST NOT be touched.
- **FR-002**: The change MUST be delivered as **commits made directly on `main`** and pushed (per Clarifications 2026-10-13: no feature branch, no merge record for this feature; Argo CD only converges `main`, so every change pushes to `main` as it becomes operative). Cluster convergence MUST be driven by Argo CD only (constitution I — no imperative platform mutations).
- **FR-003**: One explicit force-refresh/sync of the affected Argo CD applications MUST be performed and recorded (command/output in the feature's tracking artifact) so convergence timing is observable rather than waiting on poll default (constitution II record of an imperatively-triggered action).
- **FR-004**: After the sync, ALL openshell-related applications MUST be Synced+Healthy, and one of the gates (`make argo-healthcheck` or equivalent app listing) MUST show no degraded openshell apps.
- **FR-005**: The workstation openshell CLI MUST be updated to 0.1.3 and `make check-openshell-cli` MUST pass unmodified (no weakening of the version tie).
- **FR-006**: Policy-at-create MUST be validated end-to-end: create a sandbox whose initial policy is passed at create time and demonstrate the policy is active from the sandbox's first operation (e.g., an allowlisted egress succeeds and/or a non-allowlisted one is denied) *without* any post-create `policy set` race and with no `ConfigurationInvalid` admission errors.
- **FR-007**: Existing demo drivers (`deploy/openshell/demo/zen/run-zen-demo.sh`, `deploy/openshell/demo/run-demo.sh`) MUST be updated to obtain initial policy via the at-create mechanism (flag or env var) where validation allows, while preserving post-create iterative `policy set` for the remediation-loop narratives.
- **FR-008**: If FR-006 validation fails with a cause not fixable within this feature, the scripts MUST retain the existing create+policy-set loop, and the failure MUST be root-caused and recorded with an upstream reference.
- **FR-009**: Static gates MUST pass after all edits: `make test-static` and `./pattern.sh make validate-schema`.
- **FR-010**: At feature end, zero residual state: no sandboxes, no forwards, no manual cluster drift, and the demo evidence appended to `specs/011-zen-sandbox-demo/demo-log.md` or a new feature tracking artifact.

### Key Entities

- **Version pin set**: chart version (`values-prod.yaml` → `clusterGroup.applications.openshell.chartVersion`) and image tags (`overrides/values-openshell-gateway.yaml`: `gateway`, `sandboxRuntime`, `supervisor` image tags) — the single source of truth for platform versions.
- **Argo CD applications**: `openshell` (gateway) and dependencies (`openshell-keycloak-config`, `openshell-policy`, etc.) that must converge on the new desired state.
- **Sandbox policy**: the openshell policy YAML applied at sandbox-create (and updated iteratively afterward).
- **Version-tie guard**: `tests/check-openshell-cli.sh` enforcing CLI == chart version.

## Success Criteria *(mandatory)*

- **SC-001**: After push, all openshell Argo CD applications are Synced+Healthy within 15 minutes (including the forced sync).
- **SC-002**: The running gateway pod image tag reads 0.1.3 and a gateway status inquiry succeeds against it.
- **SC-003**: The workstation CLI reports 0.1.3 and `make check-openshell-cli` passes.
- **SC-004**: A sandbox created with an initial policy supplied at create reaches a usable state with that policy effective from its first operation, within 5 minutes and with zero admission-rejection/`ConfigurationInvalid` events.
- **SC-005**: The zen demo smoke path completes once post-upgrade end-to-end (governed sandbox → free-tier "hi" → ≥5 deny proofs → clean teardown), and iterative in-session policy updates continue to apply.
- **SC-006**: At completion: zero sandboxes, zero forwards, no manual drift, all green gates, and issue #8 referenced with evidence.

## Assumptions

- Upstream release 0.1.3 (2026-10-09) publishes a `helm-chart` 0.1.3 at the pinned OCI repo and matching component images; availability is verified as the first task — if false, the change is not merged and the issue records the hold.
- The 0.1.x value schema migration note in `overrides/values-openshell-gateway.yaml` remains sufficient for 0.1.3; any new required values surface during pre-push render validation.
- Interactive/demo validation uses the existing gateway auth workflow; long-token behavior is out of scope (tracked in minilab#9).
- Rollback plan, if upgrade destabilizes the platform: revert the pin commit directly on `main` and re-sync (declarative); no bespoke backup step is warranted for a homelab whose state is Git-defined.
- Delivery mechanics (decided 2026-10-13): direct commits on `main`, no feature branch and no G6-style merge record — a deliberate simplification for this work order since every change must hit `main` to become operative (GitOps convergence); any intermediate branch would be dead code from the cluster's perspective.
- Component version upgrades do not require CRD drift handling beyond what the chart performs.
