# Feature Specification: Reference External Charts Instead of Vendoring

**Feature Branch**: `006-openshell-gitops-install` (explicit user direction: refactor lands on the existing branch/PR)

**Created**: 2026-09-24

**Status**: Draft

**Input**: User description: "The 006-openshell-gitops-install branch and PR is fundamentally floored in the following way: it's manually copied in all of the charts. Using ../coco-pattern (on main) as a reference you should be able to reference external charts from URL (and/or container images). Use documentation in ../coco-pattern, github.com/validatedpatterns and https://validatedpatterns.io/patterns/ to back your analysis and refactor. Do so on the existing branch."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Upstream Charts Referenced, Not Copied (Priority: P1)

As a pattern maintainer, I want every upstream chart (OpenShell, agent-sandbox, cert-manager, ZTWIM) pulled from its authoritative external source by the pattern's application definitions, so that no copy of upstream chart content exists in this repository and version bumps become a values-file change instead of vendoring surgery.

**Why this priority**: User-identified fundamental flaw; copying upstream charts breaks provenance, makes updates opaque, and duplicates what the Validated Patterns framework already supports natively (as demonstrated by `../coco-pattern` and the clustergroup chart).

**Independent Test**: List every chart artifact in the repository; confirm zero upstream chart templates, CRDs, or packaged tarballs exist, while the pattern's rendered applications still resolve the same upstream charts with pinned versions.

**Acceptance Scenarios**:

1. **Given** the refactor is complete, **When** the repository's charts directory is inspected, **Then** only pattern-owned manifests exist (no vendored upstream chart contents, no upstream `.tgz` archives).
2. **Given** a rendered pattern, **When** the GitOps application specifications are examined, **Then** the OpenShell gateway, the sandbox controller substrate, cert-manager, and the identity layer all resolve to pinned external chart references.
3. **Given** an upstream version bump, **When** the operator updates the pinned version in the pattern's values files, **Then** the next reconciliation uses the new upstream version with no chart surgery.

---

### User Story 2 - Framework-Native Composition Preserves Behavior (Priority: P1)

As the feature operator, I need the refactored wiring to carry the same effective configuration — pins, security posture, guardrails, ordering, feature gates — so that the static validation suites continue to prove the same properties and the deferred testing phase remains valid.

**Why this priority**: A source-locations-only refactor that silently drops hard-won configuration (convergence fixes, envelope guardrails, drift guards) would regress the feature; equivalence of effective configuration is the core acceptance burden.

**Independent Test**: Run the full static validation suite (`make validate-openshell`, pattern config validation, schema validation) and confirm every previously-proven property still holds under the new source model.

**Acceptance Scenarios**:

1. **Given** the refactored pattern, **When** the openShell feature values are rendered, **Then** all convergence-validated properties still hold (KEK secret key, SPIFFE toggle semantics, sandbox envelope quota, pinned versions, no floating images, wave ordering).
2. **Given** pattern-owned custom manifests (OAuth client, certificate-authority fetch, SCC binding, metrics scraping, policy documents, demo assets), **When** the repository is reviewed, **Then** they remain as locally owned content, clearly separated from upstream chart sources.
3. **Given** the external chart references, **When** they cannot be reached (offline render), **Then** static tests still validate everything that does not require fetching (and the suite documents what requires fetch).

---

### Edge Cases

- The sandbox-controller substrate is not published to any chart registry (source-only upstream project); its external reference must pin an immutable repository tag — a tag move or force-push upstream breaks reproducibility and must be detectable.
- The OpenShell chart's registry serves OCI artifacts; registry-side republishing (non-immutable tags) must be guarded against via digest verification at version-bump time.
- An upstream source being briefly unreachable must not leave the operator unable to audit desired state: every pinned reference and the last-known-good must be visible in Git.
- Pattern-owned charts depend on the same shared value conventions as external charts; value-key drift between local and external charts (e.g. feature dials vs chart-native keys) must be caught by tests.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: No upstream chart content (templates, CRDs, packaged archives, rendered copies) may exist in this repository; pattern-owned manifests are the only allowed local chart content.
- **FR-002**: Every upstream chart MUST be referenced from an authoritative external source using the pattern framework's supported mechanisms (external chart-source URL with exact version pin, matching the model demonstrated by the reference pattern and the Validated Patterns clustergroup), with the rendered application specs carrying the pinned reference.
- **FR-003**: Where a community Validated Patterns chart exists for a dependency (identity layer, certificate management), it MUST be preferred over a hand-rolled local equivalent.
- **FR-004**: Where no published chart artifact exists (source-only upstream), the reference MUST pin an exact immutable upstream repository tag via the framework's external-source mechanism, and version-controlled detectability of upstream changes MUST be preserved.
- **FR-005**: All existing effective configuration MUST survive the refactor: version pins, telemetry opt-out, storage-class delegation, sandbox capacity guardrails, SPIFFE toggle + fallback semantics, certificate issuance posture (staging-first), policy-as-code mechanism, demo assets, and secrets wiring. The static validation suites MUST pass without weakening.
- **FR-006**: Version and digest pinning obligations (existing FR-005 from feature 006) MUST continue to be enforced by tests, extended to the new reference locations.
- **FR-007**: The refactor MUST preserve declarative ordering guarantees (dependency waves) across externally-sourced and locally-owned applications.

### Key Entities

- **External Chart Reference**: A pinned pointer (source URL + version) from a pattern application to an upstream chart; the unit this feature exists to establish. Immutable, single-place, testable.
- **Pattern-owned Chart**: Local manifests authored by this project (security bindings, quotas, secret wiring, policy documents, demo assets) — the only permitted local chart content.
- **Feature Values**: The operator-facing dial surface (unchanged contract), which the refactor's values layout must continue to honor without leaking upstream chart structure into the dials.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of upstream chart sources are referenced externally — zero upstream chart files or archives exist under `charts/` (verified by test).
- **SC-002**: Bumping an upstream version touches only values files (line count of the change is limited to the version field(s)); verified by a scripted before/after render comparison.
- **SC-003**: All static validation suites pass with zero relaxations relative to the pre-refactor suite set.
- **SC-004**: The deferred testing-phase runbook (quickstart) requires only reference-shape updates (no re-scoping of runtime validation).

## Assumptions

- The work lands on the existing `006-openshell-gitops-install` branch (explicit user direction); pre-merge rework on that branch is acceptable.
- The Validated Patterns clustergroup version in use supports: external chart-source references with values from pattern files, per-application source overrides, and per-application extra value files (verified against the framework source during planning for its exact 0.9.x semantics).
- Upstream sources are reachable at reconciliation time from the cluster's GitOps controller (online cluster; air-gap is out of scope per feature 006 assumptions).
- Pattern-owned helper manifests remain local by definition — this feature governs only upstream chart sourcing, not the relocation of project-authored configuration.
- The OpenAI/demo, policy, and platform-posture charts from feature 006 are pattern-owned and intentionally stay local; none are upstream copies.
