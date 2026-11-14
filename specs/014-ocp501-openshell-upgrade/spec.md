# Feature Specification: OCP 5.0.1 Operator Review & OpenShell 0.1.x Upgrade

**Feature Branch**: none — direct commits on `main` (Clarifications 2026-11-14; branch `014-ocp501-openshell-upgrade` was created by the specify hook but is not used for delivery)

**Created**: 2026-11-14

**Status**: Draft

**Input**: User description: "The cluster has been upgraded to OpenShift 5.0.1. 1. Do a review of the available operators in the operator hub, and update as appropriate. 2. Openshell is rapidly moving; upgrade to the latest 0.1.* release. 3. Run acceptance testing against openshell to check whether behaviour is as expected."

## Clarifications

### Session 2026-11-14

- Q: Should the operator hub review cover only pattern-managed operators, or also survey the hub for new operators to adopt? → A: Only pattern-managed subscriptions; align their channels/CSVs to 5.0.1. Surveying for new operators to adopt is out of scope (constitution IV: every added component must justify itself — a separate feature if ever wanted).
- Q: How should changes be delivered to `main`, given Argo CD only converges `main`? → A: Direct commits on `main`, each pushed as it becomes operative (feature 012 precedent); no feature branch, no merge record.
- Q: Should the cluster-observability operator's install-plan approval stay Manual, or switch to Automatic? → A: Switch to Automatic in the same values change; the feature-010 Manual pin has served its purpose and Automatic keeps convergence GitOps-clean.
- Q: If acceptance testing finds a genuine behavioral regression in the new OpenShell release, keep the pin or revert? → A: Keep the new pin and document the regression with root cause and upstream reference; revert only if the platform becomes unusable (auth or sandbox lifecycle broken).
- Post-`/speckit.analyze` remediation (2026-11-14): findings F1–F4, B3–B5, A1, C4 applied — the review's subscription set corrected to the seven pattern-declared keys (patterns-operator is framework-managed, observational only); FR-011 anchored to the review record instead of a channel alignment; SC-004 aligned with FR-008's `fail→documented` terminal state; drift defined as zero OutOfSync Argo CD applications; `ocpRelease` convention fixed to major.minor; FR-012 added for release-flagged behavior-delta remediation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Operator hub subscriptions reviewed and aligned to OCP 5.0.1 (Priority: P1)

As the lab operator, I want every operator subscription the pattern manages reviewed against the operator hub catalog now available on the OpenShift 5.0.1 cluster, and each subscription's channel/CSV pin updated in Git where a 5.0.1-appropriate channel exists, so that all platform operators run versions designed for the upgraded cluster — with the review itself recorded in Git — and no operator is left on a stale, 4.x-era channel.

**Why this priority**: The cluster platform version moved underneath the GitOps-managed operator pins; some pins (notably the LVM Storage pin at a 4.22-named channel and CSV, asserted by local tests against `global.lvmsCompatibility`) are version-tied to the previous major version. Until the operator layer is aligned, operator behavior on 5.0.1 is unverified and any OpenShell validation sits on an operator layer of unknown compatibility.

**Independent Test**: A review artifact in Git lists every pattern-managed subscription with its current channel/CSV, the 5.0.1-catalog state, and the decision taken; after convergence, every operator reports a running CSV whose channel is compatible with OpenShift 5.0.1, and the pattern's validation gates pass.

**Acceptance Scenarios**:

1. **Given** the cluster now runs OpenShift 5.0.1 while the pattern pins operator channels from the 4.x era, **When** the operator hub catalog on the upgraded cluster is reviewed against each pattern-managed subscription, **Then** a recorded review covers 100% of the subscription keys declared in the cluster-group values (lvms-operator, eso, cluster-observability-operator, cert-manager-operator, ztwim, rhbk, agent-sandbox), each with an explicit keep/update decision and rationale; the framework-managed patterns-operator subscription appears only as an observational note.
2. **Given** the review identifies a subscription whose pinned channel is not appropriate for OpenShift 5.0.1, **When** the channel/CSV pin is updated in the pattern values and pushed, **Then** Argo CD converges the subscription and the operator reaches a healthy state on a 5.0.1-compatible channel, with the related local pin-assertion tests updated in the same change.
3. **Given** the review identifies a subscription that is already correct for 5.0.1, **When** the review is recorded, **Then** that subscription's values are byte-identical to the pre-feature commit.
4. **Given** no operator is installed or upgraded by manual cluster commands, **When** convergence happens, **Then** all desired-state changes exist in Git (constitution I) and any forced sync is recorded (constitution II).

---

### User Story 2 - OpenShell platform upgraded to the latest 0.1.x release via GitOps (Priority: P1)

As the lab operator, I want every openshell version pin in the GitOps configuration — the upstream chart version and the per-component image tags in the gateway values override — raised from 0.1.3 to the latest stable 0.1.* release, with the workstation CLI updated to match, so the platform runs the current release from the same trusted, version-pinned upstream sources, converged by Argo CD rather than manual mutation.

**Why this priority**: OpenShell is iterating rapidly within 0.1.x; the lab is a validation environment for it and falls behind upstream fixes as soon as a release lands. The version tie between chart, component images, and CLI is deliberately enforced by repo gates, so the upgrade must move all pins together.

**Independent Test**: `git log` shows the pin change; Argo CD reports the openshell applications Synced+Healthy; the running gateway pod's image tag equals the new chart pin; the gateway answers a status inquiry; `openshell --version` on the workstation matches and the version-tie check passes.

**Acceptance Scenarios**:

1. **Given** the pattern pins openshell at 0.1.3 (chart version plus gateway/sandbox-runtime/supervisor image tags), **When** the latest stable 0.1.x release is identified from the pinned upstream source and the pins are raised, committed, and pushed, **Then** Argo CD converges (with any forced refresh/sync recorded) and all openshell-related applications report Synced and Healthy.
2. **Given** the sync completed, **When** inspecting the gateway workload and workstation, **Then** the gateway pod image tag equals the new pin, a gateway status inquiry succeeds, the CLI reports the same version, and the version-tie check passes unmodified.
3. **Given** the new release changes the chart's value schema, **When** pre-push render validation runs, **Then** any required values changes are made in the override file in the same change (static gates fail before push rather than the cluster after).

---

### User Story 3 - Acceptance testing verifies expected OpenShell behavior post-upgrade (Priority: P2)

As the lab operator, I want the repo's acceptance suite for openshell — static validation, live auth smoke, and the scripted demo smoke — executed against the upgraded platform, with any behavioral deviation from expected outcomes root-caused and either fixed in Git or documented with an upstream reference, so I have recorded evidence that the platform behaves as expected on the new release and the new operator layer.

**Why this priority**: This is the confidence step that justifies the other two; it only becomes meaningful once the platform and operator layer are upgraded (US1, US2). It converts "upgraded" into "upgraded and verified".

**Independent Test**: The acceptance suite runs to completion against the live cluster with results (pass/fail per stage, evidence) recorded in a feature tracking artifact; a sandbox lifecycle — create, use under policy, teardown — completes cleanly with zero residual state.

**Acceptance Scenarios**:

1. **Given** the upgraded platform, **When** the static acceptance suite runs, **Then** every gate passes (values, secrets, quota, render, ordering, pins, ztwim shell tests, CLI version tie).
2. **Given** gateway auth is available, **When** the live auth smoke runs, **Then** Keycloak OIDC login and gateway status succeed end-to-end.
3. **Given** a reachable cluster and authenticated gateway, **When** the scripted demo smoke runs, **Then** the sandbox is created, the expected prompt exchange succeeds, and teardown leaves zero sandboxes and zero forwards.
4. **Given** an acceptance stage fails, **When** the failure is investigated, **Then** it is either fixed via a Git change and re-validated, or recorded with root cause and an upstream reference — never silently skipped or the check weakened.

---

### Edge Cases

- What happens when the operator hub on 5.0.1 does not yet offer a channel for a given operator that is marked compatible with 5.0.1 (e.g., a Red Hat build lagging the platform release)? → The review records the gap, the subscription stays on its current channel if it remains installable/healthy, and the hold is documented rather than force-migrating to an unverified channel.
- What happens when the latest openshell 0.1.x chart is not yet published at the pinned OCI location, or the CLI is not yet installable through the normal workstation channel? → Availability is verified as the first task of the upgrade; if absent, the change is held and recorded rather than breaking the running platform.
- What happens when the cluster-observability operator churns CSVs after its install-plan approval switches from Manual to Automatic (decided 2026-11-14)? → The values change to `Automatic` lands in the same commit as the review record that decides it; if churn waves reappear, the decision is reverted in Git with rationale rather than re-pinning silently.
- What happens when an operator upgrade requires CRD or namespace changes the current values cannot express? → Caught by render validation before push; values updated in the same change, or the upgrade deferred with rationale.
- What happens when the openshell upgrade restarts the gateway while sandboxes or port-forwards exist? → Teardown before upgrade as needed; zero residual state verified afterward.
- What happens when acceptance testing reveals a genuine behavioral regression in the new openshell release? → Root-caused and documented with an upstream reference; the pin stays on the new release unless the platform becomes unusable (auth or sandbox lifecycle broken), in which case the pin commit is reverted on `main` (decided 2026-11-14).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A review of the operator hub on the OpenShift 5.0.1 cluster MUST be performed covering every operator subscription declared in the pattern's cluster-group values — the seven subscription keys `lvms-operator`, `eso` (openshift-external-secrets-operator), `cluster-observability-operator`, `cert-manager-operator` (openshift-cert-manager-operator), `ztwim` (openshift-zero-trust-workload-identity-manager), `rhbk` (rhbk-operator), and `agent-sandbox` (agent-sandbox-operator) — and the review MUST be recorded in Git as a durable artifact (feature tracking document) listing, per subscription key: current channel/CSV pin, 5.0.1-catalog availability, and an explicit keep/update decision with rationale. The framework-managed `patterns-operator` subscription (present on-cluster but not declared in the pattern values) is recorded as an observational note only, with no Git pin decision.
- **FR-002**: Where the review determines an update is appropriate, the subscription's channel and/or CSV pin MUST be updated in the pattern values (including `values-global.yaml` lvms compatibility fields and `values-prod.yaml` subscriptions) and any local tests that assert those pins MUST be updated in the same change; unrelated version strings that merely coincide MUST NOT be touched. The `global.lvmsCompatibility.ocpRelease` value uses major.minor form (`5.0`), matching the lvms channel.
- **FR-003**: All cluster convergence MUST be driven by Argo CD from Git (constitution I); any forced refresh/sync MUST be performed at most as a recorded imperative step (constitution II). No operator may be installed, upgraded, or approved by unrecorded manual cluster commands.
- **FR-004**: After convergence, every pattern-managed operator MUST report a healthy installed CSV on a channel the review determined compatible with OpenShift 5.0.1, or carry a documented hold rationale in the review artifact.
- **FR-005**: All openshell version pins declared in Git — the chart version in the pattern values and each component image tag in the gateway values override — MUST be raised from 0.1.3 to the latest stable 0.1.x release, from the same trusted, version-pinned upstream sources (`oci://ghcr.io/nvidia/openshell/helm-chart` and `ghcr.io/nvidia/openshell/*` images).
- **FR-006**: The workstation openshell CLI MUST be updated to the same version and the version-tie check MUST pass unmodified (no weakening of the tie).
- **FR-007**: The openshell acceptance suite MUST be executed against the upgraded platform and its results recorded: the static gates, the live auth smoke, and the scripted demo smoke, plus a sandbox create/use/teardown lifecycle check. Each stage's outcome (pass/fail, evidence) MUST be captured in the feature tracking artifact.
- **FR-008**: Any acceptance failure MUST be root-caused and either fixed via a Git change (then re-validated) or documented with an upstream reference; acceptance checks MUST NOT be skipped or weakened to force a pass.
- **FR-009**: Static validation gates MUST pass after all edits: the repo's static test suite and the pattern schema validation.
- **FR-010**: At feature end there MUST be zero residual state: no sandboxes, no port-forwards, no manual cluster drift (zero Argo CD applications OutOfSync); the operator review and acceptance evidence MUST be committed in the feature's spec directory.
- **FR-011**: The cluster-observability operator subscription's install-plan approval MUST be switched from Manual to Automatic in the same commit as its review record (the review keeps its channel `stable`; only the approval mode changes), so post-review operator convergence requires no manual install-plan approval.
- **FR-012**: Release-flagged behavior deltas between openshell 0.1.3 and the target release (per the upstream release notes) MUST be audited and, where they affect this repo's drivers, policies, scripts, or values, remediated in Git before acceptance testing runs.

### Key Entities

- **Subscription pin set**: the operator subscriptions in `values-prod.yaml` (`clusterGroup.subscriptions`) plus the lvms compatibility fields in `values-global.yaml` — the single Git surface for operator versions.
- **Operator hub catalog**: the package manifests available on the OpenShift 5.0.1 cluster, the review's source of truth for available channels and CSV compatibility.
- **OpenShell version pin set**: chart version (`values-prod.yaml` → `clusterGroup.applications.openshell.chartVersion`) and image tags (`overrides/values-openshell-gateway.yaml`) — must move together, drift-asserted by tests.
- **Version-tie guard**: the CLI/chart version check enforcing workstation CLI == chart pin.
- **Acceptance evidence**: the feature tracking artifact recording the operator review decisions, upgrade evidence, and acceptance results.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The operator review artifact covers 100% of pattern-managed subscriptions, and after convergence every operator is healthy on a 5.0.1-compatible channel or carries a documented hold.
- **SC-002**: All Argo CD applications are Synced and Healthy within 15 minutes of the final push (including any recorded forced sync).
- **SC-003**: The running gateway pod image tag equals the new openshell pin, a gateway status inquiry succeeds, and the workstation CLI reports the same version with the version-tie check passing.
- **SC-004**: Every acceptance stage (static gates, live auth smoke, demo smoke, sandbox lifecycle) terminates in `pass` or `fail→documented` (root cause + upstream reference) with results recorded; no stage is skipped or weakened.
- **SC-005**: At completion: zero sandboxes, zero port-forwards, zero Argo CD applications OutOfSync (drift-free), and all validation gates green.

## Assumptions

- The OpenShift 5.0.1 cluster upgrade itself is already complete and the cluster is healthy; re-upgrading or validating the platform upgrade is out of scope. Only the GitOps-managed layer above it is in scope.
- "Update as appropriate" means: review every pattern-managed subscription against the 5.0.1 catalog and update channel/CSV pins where a compatible channel exists — not adding new operators, not removing existing ones.
- "Latest 0.1.* release" is the newest stable 0.1.x published at the pinned upstream sources at the time of the upgrade; availability (chart, images, CLI) is verified as the first task, and the exact version is recorded in the tracking artifact. A 0.2/1.x release, if one exists, is out of scope.
- "Acceptance testing" means the repo's existing acceptance surface: the static shell tests, the live auth smoke, the scripted demo smoke, and a sandbox lifecycle check — plus behavioral spot-checks of anything the new release's notes flag as changed.
- Delivery mechanics (decided 2026-11-14, 012 precedent): direct commits on `main`, each pushed as it becomes operative — no feature branch and no merge record; every change must hit `main` to become operative (GitOps convergence), so intermediate branch state would be dead code from the cluster's perspective.
- The cluster-observability operator's install-plan approval switches from Manual to Automatic in the same values change as its channel alignment (decided 2026-11-14); if CSV churn resurfaces, the decision is reverted in Git with rationale.
- Rollback policy (decided 2026-11-14): a regression keeps the new pin and is documented with an upstream reference; the pin is reverted on `main` and re-synced (declarative) only if the platform becomes unusable (auth or sandbox lifecycle broken). No bespoke backup step.
- Interactive validation uses the existing gateway auth workflow; token-expiration handling is out of scope (minilab#9 precedent).
