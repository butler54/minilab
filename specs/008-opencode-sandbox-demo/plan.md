# Implementation Plan: Opencode-in-Sandbox Demo (Matilda LLM)

**Branch**: `008-opencode-sandbox-demo` | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/008-opencode-sandbox-demo/spec.md`

## Summary

Demonstrate the opencode coding agent running inside a governed OpenShell sandbox on the cluster gateway (`openshell.tokyo-brunch.com`), using a manually injected Matilda (Maincode) config instead of agent defaults, so the lab proves end-to-end: agent workload → egress allowlist → credential placeholder injection → denial observability. Carrier: the operator's own `ghcr.io/butler54/openshell-sandbox:latest` image (built FROM the same NVIDIA community base the cluster pins, so agent-runtime compatible). Config + policy artifacts land in Git; live steps (provider registration, policy apply, sandbox lifecycle, config injection) are documented imperative operations per Constitution II. sandboxctl is attempted first on the local gateway; its blockers are raised as issues; direct `openshell` emulation is the primary demo path.

## Technical Context

**Language/Version**: Bash + YAML config artifacts only (no compiled code). OpenShell chart 0.1.1, CLI 0.1.1, opencode-ai 1.18.3x (npm-installed in carrier image).

**Primary Dependencies**: OpenShell k8s gateway 0.1.1 (cluster), Keycloak OIDC (RHBK 26.6), matilda provider profile + provider (already registered), Matilda edge API `https://matilda.maincode.com/api/v1/code`, carrier image `ghcr.io/butler54/openshell-sandbox:latest` (FROM `ghcr.io/nvidia/openshell-community/sandboxes/base@sha256:aeef1c63...` — same digest as chart `sandbox.default_image`).

**Storage**: Git (demo artifacts under `deploy/openshell/demo/`); sandbox workspace volume (ephemeral per spec FR-009); gateway SQLite for provider record (KEK-encrypted, already exists).

**Testing**: `make validate-openshell` (offline render/drift) + `make validate-openshell-live` (live smoke) + recorded quickstart V-DEMO acceptance steps.

**Target Platform**: SNO OpenShift 4.22 (x86_64), cluster gateway 0.1.1; opencode runs inside sandbox pod on `openshell` ns.

**Performance Goals**: Setup-to-first-response < 10 min from docs (SC-001); cleanup < 2 min (SC-005).

**Constraints**: GitOps-first for infra artifacts; imperative steps recorded in Git before running (Constitution I/II); no custom image build for this feature (runtime config injection); `sandbox.maxConcurrent=3` quota on cluster gateway; binaries list enforcement weights.

**Scale/Scope**: Single demo sandbox, single operator session.

## Constitution Check

| Gate | Status | Notes |
|---|---|---|
| I. GitOps-First | PASS | Demo assets (provider profile, egress policy, opencode config template, runbook) live in Git under `deploy/openshell/` and `charts/openshell-policy/`; live cluster state is injected via recorded imperative steps only. |
| II. Imperative Only Second | PASS | Provider registration, policy apply, sandbox create, config injection are all unavoidable-live operations; each is scriptable, idempotent, and recorded in `deploy/openshell/demo/` + quickstart before execution. |
| III. Helm Only, No Kustomize | PASS | No packaging changes; no Kustomize. |
| IV. Simplicity First | PASS | Reuses existing gateway/provider/policy chain; carrier image already built and published by user's own `butler54/containers`; no new images or services. |

## Project Structure

### Documentation (this feature)

```text
specs/008-opencode-sandbox-demo/
├── spec.md              # scope, FR-001..FR-009, SC-001..SC-005
├── plan.md              # (this file)
├── research.md          # Phase-0 findings (image lineage, injection mechanism, session shapes, binaries)
├── data-model.md        # artifact surfaces (config bundle, provider, policy, runbook)
├── contracts/
│   └── demo-assets.md   # file/surface contracts for demo artifacts
└── quickstart.md        # scriptable validation steps for V-DEMO
```

### Source Code (repo changes)

```text
deploy/openshell/
├── profiles/matilda.yaml                 # (exists) provider profile imported --global
└── demo/
    ├── opencode-matilda.json             # canonical opencode config template (matilda provider, env-var key, model)
    ├── inject-config.sh                  # copies template into a live sandbox (idempotent)
    └── run-demo.sh                       # interactive demo entrypoint (session + proofs + cleanup)
charts/openshell-policy/policies/
├── sample-matilda-demo.yaml              # (exists) egress policy — extended with agent-runtime binaries
docs/openshell-demo-opencode.md           # operator runbook (setup → smoke → interactive → proofs → cleanup)
```

## Phase 0 Research

See [research.md](research.md).

## Phase 1 Design

See [data-model.md](data-model.md), [contracts/demo-assets.md](contracts/demo-assets.md), [quickstart.md](quickstart.md).
