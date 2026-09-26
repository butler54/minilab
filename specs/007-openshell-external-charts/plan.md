# Implementation Plan: Reference External Charts Instead of Vendoring

**Branch**: `006-openshell-gitops-install` (explicit user direction — refactor on the existing branch/PR) | **Date**: 2026-09-24 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/007-openshell-external-charts/spec.md`

## Summary

Refactor the OpenShell GitOps platform to eliminate all vendored upstream chart content. Every upstream chart is consumed via the Validated Patterns clustergroup's multi-source application model (verified from `templates/plumbing/applications.yaml`): external pinned sources — NVIDIA OpenShell from OCI `ghcr.io`, agent-sandbox from its GitHub `helm/` dir at tag, cert-manager and ZTWIM config from Validated Patterns community OCI charts (`ocp-certmanager`, `ztwim`) — with all chart values carried in per-app override files in this repo. Pattern-owned manifests (security bindings, quotas, secret wiring, policy documents, demo assets) remain as local charts. The single-`acme` ClusterIssuer topology from research.md D5 replaces the two-issuer design. All existing static validation properties are preserved via suite transformation, plus a new external-refs proof suite.

## Technical Context

**Language/Version**: YAML + Helm 3 templates; pattern framework = Validated Patterns clustergroup `0.9.*` (app multi-source generation verified against clustergroup-chart ≥0.9.34 source)
**Primary Dependencies**: clustergroup multi-source model; external sources: OCI `ghcr.io/nvidia/openshell` (`helm-chart` 0.0.116), git `github.com/kubernetes-sigs/agent-sandbox` `helm/` @ `v1.0.3`, OCI `quay.io/validatedpatterns` (`ocp-certmanager` 0.2.0, `ztwim` 0.1.1); cluster GitOps = OpenShift GitOps (Argo CD w / native multi-source + OCI support)
**Storage**: unchanged from 006 (gateway DB PVC, SPIRE 2Gi, workspace PVCs on LVMS default SC)
**Testing**: `make validate-openshell` (refactored suites + `test-external-refs.sh`), `tests/validate-pattern-config.sh`, `./pattern.sh make validate-schema`
**Target Platform**: existing pattern repo on `006-openshell-gitops-install`; runtime destination unchanged (designated OCP 4.22 SNO — testing phase shared with 006)
**Project Type**: GitOps refactor (source provenance change, zero new runtime behavior)
**Performance Goals**: N/A
**Constraints**: Helm-only; no upstream chart content in Git; exact immutable pins for the four feature charts; feature-dial contract (006 values-contract.md incl. ztwim.enabled) unchanged at the dial layer
**Scale/Scope**: 4 ExternalChartRefs, 5 pattern-owned charts, 4 app override files, 1 wave-plan revision

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Pre-Phase-0**: PASS (research decisions D1–D8 recorded with alternatives).
**Post-Phase-1 re-evaluation**: PASS —

- **I. GitOps-First**: PASS. External chart references are Git-declared, Argo-fetched; state provenance is MORE auditable than vendoring.
- **II. Imperative Only Second**: PASS. Nothing imperative added; online smoke step is an optional verification, not a state change.
- **III. Helm Only**: PASS. External chart consumption IS Helm (no kustomize introduced); local pattern-owned charts remain Helm.
- **IV. Simplicity First**: PASS. Net surface reduction: −1 wrapper chart, −2 copied chart trees; local content now only project-authored manifests. ACME topology simplifies two issuers → one.
- **Platform Constraints**: PASS. Trusted, version-pinned sources: exact versions everywhere in this feature; upstream OCI/git sources verified reachable; no secrets in Git (unchanged).

## Project Structure

### Documentation (this feature)

```text
specs/007-openshell-external-charts/
├── plan.md
├── research.md          # D1–D8 + residual risks
├── data-model.md        # ExternalChartRef, PatternOwnedChart, AppOverrideFile, AcmeIssuer
├── quickstart.md        # G1 gates, V-SRC proofs, V-REF runtime appendix
├── contracts/
│   ├── external-chart-contract.md   # authoritative external chart registry
│   └── values-layout-contract.md    # dial ⇄ override drift rules
└── tasks.md             # (next command)
```

### Source Code (repository root delta)

```text
values-prod.yaml            # app entries rewritten: ExternalChartRef for openshell,
                            #   agent-sandbox, cert-manager, ztwim; extraValueFiles;
                            #   waves per research D7
overrides/
├── values-openshell.yaml        # dials only — passthrough `openshell.*` block REMOVED
├── values-openshell-gateway.yaml  # NEW: NVIDIA chart root values
├── values-agent-sandbox.yaml      # NEW: git-sourced chart values
├── values-ztwim.yaml              # NEW: VP ztwim spire.* values
└── values-certmanager.yaml        # NEW: certmgrOperator single-acme issuer

charts/
├── openshell/                 # DELETED (wrapper + vendored tgz)
├── agent-sandbox/             # DELETED (vendored upstream helm/)
├── ztwim-config/              # DELETED (replaced by VP ztwim chart)
├── cert-manager-config/       # KEPT, slimmed: cloudflare ExternalSecret only
├── openshell-extras/          # NEW: from wrapper templates/ (OAuthClient,
│                              #   router-ca RBAC+job) — pattern-owned
├── openshell-platform/        # + ClusterSPIFFEID (moved from ztwim-config)
├── openshell-policy/          # unchanged (pattern-owned)
└── openshell-demo/            # unchanged (pattern-owned)

tests/
├── test-openshell-render.sh   # rewritten: merged-values asserts
├── test-openshell-pins.sh     # rewritten: covers values-prod pins + overrides
├── test-openshell-ztwim.sh    # downscoped to ClusterSPIFFEID + ztwim values intent
├── test-external-refs.sh      # NEW: SC-001/SC-002 proofs
└── (values/secrets/quota/ordering suites updated)

docs/ & README.md              # external-chart source registry + bump runbook links
```

**Structure Decision**: Upstream chart content = zero; application composition via framework multi-source entries; project manifests remain local charts (the file list above is exhaustive).

## Complexity Tracking

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|------------|--------------------------------------|
| Dedicated per-app override files (4 new files) | External charts render at values root — keys cannot live under a feature prefix | One giant shared override would collide keys across apps and break the dial contract |
| Single `acme` ClusterIssuer (replace two-issuer design) | VP `ocp-certmanager-chart` renders one ACME issuer (`acme` key); duplicate-key issuers collide | Keeping 006's letsencrypt-staging/prod pair would force a local issuer chart (back to local replication of upstream capability) |
