# Implementation Plan: Zen Sandbox Demo and Server Mode

**Branch**: `011-zen-sandbox-demo` | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-zen-sandbox-demo/spec.md`

## Summary

Demonstrate a zero-cost, least-privilege AI coding sandbox on the minilab SNO
cluster: an openshell-CLI-deployed sandbox where opencode answers "hi" via
OpenCode Zen **free-tier** models, with the sandbox egress policy remediated
iteratively (and Git-recorded) until it works; then the same agent exposed via
`opencode serve` and driven from the operator's **local** opencode client. The
approach reuses feature 008's proven asset family (policy-as-code chart, inject
script, run-demo driver, troubleshooting corpus), adds a `zen` provider profile,
a `policies/zen-demo.yaml` least-privilege policy built from a recorded
observe→justify→apply loop, and closes with full teardown and zero-residual
proof.

## Technical Context

**Language/Version**: Bash scripts (demo drivers), YAML (openshell policy v1, Helm values), strict JSON (opencode config template)

**Primary Dependencies**: openshell CLI 0.1.1 (pinned to gateway chart `0.1.1`, enforced by `make check-openshell-cli`); opencode (in-carrier image); OpenCode Zen free tier; OCP 4.22 SNO cluster + Keycloak `openshell` realm auth

**Storage**: N/A (gateway DB ephemeral by design; all durable state in Git + vault)

**Testing**: `make test-static` (incl. openshell policy/render/pin guards, FR-008), `make test-live` where applicable, quickstart gate scripts mirroring feature 010's acceptance pattern

**Target Platform**: minilab `sno` SNO cluster, `openshell` namespace gateway, operator workstation (macOS)

**Project Type**: platform demo / infrastructure validation assets (scripts + policy + config), not a shipped application

**Performance Goals**: SC-001 ≤15 min login→hi; SC-002 ≤2 min/query; SC-004 ≤5 min sandbox-ready→server-hi

**Constraints**: least-privilege egress (deny-all default, justified allowlist only); no paid credentials; no secret material in Git/vault-template drift; no public exposure (FR-007); sandbox bootstrap-fence window (~5 min) — pre-create/retry discipline; gateway token TTL 3600s with documented re-login

**Scale/Scope**: single operator, single cluster, one sandbox at a time (cluster ResourceQuota caps at maxConcurrent=3)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Evidence |
|---|---|---|
| I. GitOps-First | **PASS** | Policy lives in `charts/openshell-policy/policies/zen-demo.yaml` (GitOps-rendered ConfigMap — established 008 pattern); zen profile/config/scripts committed under `deploy/openshell/`; zen credential (if any) via new vault seed + ExternalSecret, never in Git |
| II. Imperative Only Second | **PASS** | openshell CLI has no declarative in-cluster consumer (`openshell policy set`, `sandbox create`, `provider create` are inherently imperative); all such steps automated in Git-committed, idempotent scripts modeled on `run-demo.sh`, each with recorded rationale |
| III. Helm Only, No Kustomize | **PASS** | Zen policy is a data file in the existing Helm chart; no new packaging mechanism |
| IV. Simplicity First | **PASS** | Reuses 008 asset family and existing gateway/image; fallback is the simplest possible reach (`oc port-forward`); no new operators, no new namespaces |
| Platform Constraints | **PASS** | Vault/external-secrets for any zen credential (`secret/data/hub/openshell-zen` seed); version-pinned sources (CLI pinned to chart 0.1.1) |

No violations → no Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/011-zen-sandbox-demo/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output (G0–G6 acceptance gates)
├── contracts/           # Phase 1 output (asset + policy contracts)
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root)

```text
deploy/openshell/
├── profiles/zen.yaml                 # zen provider profile (shape of matilda.yaml)
└── demo/zen/
    ├── opencode-zen.json             # opencode config template (zen free model)
    ├── run-zen-demo.sh               # US1+US2 driver (adapted run-demo.sh: preflight, create, inject, policy, hi, deny proofs, cleanup)
    └── run-zen-server.sh             # US3 driver (serve in sandbox, forward, attach-local instructions, teardown)

charts/openshell-policy/policies/
└── zen-demo.yaml                     # least-privilege egress policy, every rule justified inline

values-secret.yaml.template           # new optional seed: secret/data/hub/openshell-zen (zen API key, only if live probe shows keyless fails)

tests/
├── test-zen-policy.sh                # static: zen-demo.yaml lint (binaries present, protocol rest, justification comments)
└── (extended coverage via existing test-openshell-render.sh glob on policies/)
```

**Structure Decision**: Mirror the proven 008 layout: demo drivers under
`deploy/openshell/demo/zen/`, policy-as-data in the existing
`charts/openshell-policy` chart, profile beside `matilda.yaml`. No new charts,
no new namespaces, no Kustomize.

## Complexity Tracking

> No constitution violations — table intentionally empty.
