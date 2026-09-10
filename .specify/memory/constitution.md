<!--
Sync Impact Report
- Version change: (unversioned template) -> 1.0.0
- Modified principles: N/A (initial ratification)
- Added sections: Core Principles (I-IV), Platform Constraints, Development Workflow, Governance
- Removed sections: template's generic Section 2 and Section 3 placeholders (superseded by
  Platform Constraints and Development Workflow)
- Follow-up TODOs: none
-->

# minilab Constitution

## Core Principles

### I. GitOps-First

Every workload, configuration, namespace, and cluster-scoped resource MUST be declared in
Git and reconciled by Argo CD. Git is the single source of truth for desired state; the
cluster is a disposable projection of it.

- No resource reaches the cluster except through an Argo CD-reconciled manifest.
- Manual `oc`/`kubectl` mutations are drift; once discovered they MUST be reverted or
  captured back into Git.
- `values-global.yaml` and the per-cluster-group value files are the only supported
  surface for configuration change.

Rationale: A home lab is rebuilt often and operated by one person. GitOps makes recovery
deterministic, makes history auditable, and removes configuration drift as a failure mode.

### II. Imperative Only Second

Imperative, on-cluster actions are permitted only when no declarative GitOps mechanism can
express the required operation (e.g. bootstrap, one-time migration, secret seeding).

- Imperative steps MUST be automated and idempotent — never a bare, undocumented command.
- Every imperative step MUST be recorded in Git (playbook, Job manifest, or script) with
  its rationale before it is run.
- After an imperative step completes, the result MUST be reconciled back under GitOps and
  the escape hatch documented.

Rationale: Some operations (initial Argo CD install, vault bootstrap) cannot bootstrap
themselves. Constraining them to a documented, repeatable path keeps "imperative second"
a bounded fallback rather than a loophole.

### III. Helm Only, No Kustomize

Application packaging and configuration MUST use Helm charts exclusively.

- `kustomization.yaml`, Kustomize overlays, and Kustomize patches are prohibited.
- Variation between clusters or environments MUST be expressed through Helm values files,
  not overlay composition.
- New applications MUST be added as Helm chart subscriptions in the pattern values, drawn
  from trusted, version-pinned chart sources.

Rationale: A single templating system keeps the pattern understandable. Mixing Helm and
Kustomize creates two mental models and two debugging paths, which defeats the project's
purpose.

### IV. Simplicity First

The simplest solution that satisfies the requirement MUST be chosen. Complexity MUST be
justified before it is accepted.

- Prefer fewer components, fewer dependencies, and fewer moving parts.
- Apply YAGNI: do not build for hypothetical future scale on a single-node lab.
- Every added component MUST state what capability it provides that an existing component
  cannot.
- Resource consumption MUST fit a single-node cluster budget; heavyweight approaches MUST
  be rejected in favor of lightweight equivalents.

Rationale: The target is a lightweight home lab. Complexity is the primary risk to
something one person must understand, run, and repair.

## Platform Constraints

The pattern targets a **single-node OpenShift (SNO)** cluster and MUST remain lightweight
enough to run within that footprint.

- Built on the Red Hat **Validated Patterns** framework (`values-global.yaml`,
  cluster-group value files, and the clustergroup chart).
- A single Argo CD instance reconciles the cluster (`singleArgoCD: true`).
- Secrets are managed through the pattern's vault and external-secrets mechanism; no
  secret material is committed to Git.
- All charts and container images MUST come from trusted, version-pinned sources.

## Development Workflow

- All changes are proposed as commits (and pull requests) to Git — never applied directly
  to the running cluster.
- Before being considered complete, a change SHOULD pass the pattern's validation gates:
  `make validate-schema`, `make validate-cluster`, and `make argo-healthcheck`.
- Any imperative exception follows the record-and-reconcile procedure of Principle II.
- Reviews MUST verify compliance with the Core Principles; a proposed plan that violates a
  principle MUST either be revised or document its justification under complexity tracking.

## Governance

- This constitution supersedes other practices and conventions where they conflict.
- Amendments require a pull request that states the change, its rationale, and its impact;
  approval follows the repository's normal review process.
- Versioning follows semantic versioning: **MAJOR** for incompatible governance or principle
  removals/redefinitions, **MINOR** for new or materially expanded principles/sections,
  **PATCH** for clarifications and non-semantic edits.
- Compliance is reviewed at every change: reviewers and the `/speckit.plan` Constitution
  Check gate MUST validate against these principles.
- Runtime development guidance lives in this repository (the pattern skills,
  `Makefile-common` validation targets, and the Validated Patterns documentation).

**Version**: 1.0.0 | **Ratified**: 2026-09-10 | **Last Amended**: 2026-09-10
