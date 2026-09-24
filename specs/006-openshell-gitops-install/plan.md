# Implementation Plan: OpenShell Agent Sandbox Platform via GitOps

**Branch**: `006-openshell-gitops-install` | **Date**: 2026-09-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/006-openshell-gitops-install/spec.md`

## Summary

Install NVIDIA OpenShell (agent sandboxing platform, chart v0.0.116) on the minilab SNO cluster (OCP 4.22 / K8s 1.35) entirely through the Validated Patterns GitOps machinery: vendored Helm charts and OLM subscriptions reconciled by Argo CD, zero imperative cluster mutation. The gateway is exposed on a public FQDN via a chart-rendered TLS-passthrough Route with a Let's Encrypt certificate (cert-manager operator, ACME DNS-01 via Cloudflare, staging→prod). SPIFFE/SPIRE is deployed via the GA ZTWIM operator and integrated where OpenShell 0.0.116 consumes it (provider token grants via JWT-SVID — verify at implementation), with a living readiness record in Git. A demonstration coding-agent sandbox calls the OpenAI API through policy-approved egress; all credentials flow vault → External Secrets, none enter Git or the sandbox.

Key research corrections to assumptions: upstream v0.0.116 (blog's 0.0.85 stale); mTLS user auth **unsupported** on Kubernetes gateways → OpenShift built-in OAuth serves as OIDC issuer (fallback: port-forward); NVIDIA-documented agent-sandbox `manifest.yaml` URL 404s → vendor its `helm/` chart @ v1.0.3 instead; chart lacks sandbox capacity knobs → namespace ResourceQuota enforces the 3-sandbox envelope.

## Technical Context

**Language/Version**: YAML + Helm 3 templates (Go templating), POSIX shell tests; platform OCP 4.22 (Kubernetes 1.35)

**Primary Dependencies**: OpenShell chart 0.0.116 (OCI `ghcr.io/nvidia/openshell/helm-chart`, vendored pinned); kubernetes-sigs/agent-sandbox v1.0.3 (`helm/` vendored); cert-manager Operator for RHOCP `stable-v1` (operand 1.20.3); ZTWIM operator `stable-v1` (v1.1.1; SPIRE 1.13.3, spiffe-csi 0.2.8); Validated Patterns clustergroup 0.9.*; existing pattern ESO+vault

**Storage**: LVMS default SC — gateway DB 1Gi RWO (chart-fixed), SPIRE datastore 2Gi, 3×2Gi sandbox workspaces, all RWO on default SC

**Testing**: `make validate-schema`, `make validate-cluster`, `make argo-healthcheck`; repo-convention shell tests `tests/test-openshell-*.sh` (render, ordering, pins, quota); runtime gates V-* in [quickstart.md](quickstart.md)

**Target Platform**: Single-node OpenShift 4.22 (home lab, evaluation posture per upstream "experimental" status)

**Project Type**: Infrastructure / GitOps feature of a Validated Pattern repo (no application source code)

**Performance Goals**: N/A (evaluation platform); capacity envelope: 3 concurrent sandboxes without platform starvation (SC-007)

**Constraints**: Helm-only (no kustomize); no secrets in Git; LE prod duplicate-SAN limit 5/7d (staging-first); DNS-01 only; chart renders GitOps-safe (preflight off, KEK from existing Secret); FITS SNO budget via ResourceQuota/LimitRange

**Scale/Scope**: 1 operator, 1 demonstration agent, ≤3 concurrent sandboxes, ~5 new namespaces, 2 operator subscriptions, 7 local charts

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Pre-Phase-0 evaluation**: PASS with recorded complexity justifications below.

**Post-Phase-1 re-evaluation**: PASS — every artifact in `research.md`, `data-model.md`, `contracts/`, `quickstart.md` and the project structure conforms:

- **I. GitOps-First**: PASS. Namespace, SCC binding (RoleBinding to `system:openshift:scc:privileged`, replacing `oc adm policy`), quotas, CRDs, controllers, operators, issuers, ZTWIM CRs, chart workloads, policy baseline — all Git-declared, Argo-reconciled. CLI registration, sandbox runtime actions, and vault seeding are the only imperative acts and are recorded per Principle II (quickstart table).
- **II. Imperative Only Second**: PASS. Four recorded escape hatches (G0 vault seed; `openshell gateway add/login`; sandbox create/exec; conditional cert-manager restart), each idempotent, documented, leaving desired state in Git.
- **III. Helm Only**: PASS. All manifests arrive via local Helm charts (incl. vendored upstream charts); operators via the pattern's existing OLM `subscriptions` mechanism (lvms/eso/coo precedent). Zero kustomize.
- **IV. Simplicity First**: PASS with justifications (Complexity Tracking). No external DB (SQLite on PV), no dedicated IdP (OpenShift OAuth), upstream community SPIRE not introduced (ZTWIM only), single Argo instance, YAGNI on per-pod SPIFFE IDs and identity of the agent runtime (deferred, recorded).
- **Platform Constraints**: PASS. `singleArgoCD` untouched; secrets exclusively via vault/ESO (contracts/secrets-contract.md); all chart/image sources trusted and pinned (OCI digest pin, vendored tarball, stable operator channels, concrete image tags — FR-005); footprint bounded by ResourceQuota and soak gate V-SOAK.

## Project Structure

### Documentation (this feature)

```text
specs/006-openshell-gitops-install/
├── plan.md              # This file
├── research.md          # Phase 0: 10 decisions (D1–D10) + residual risks
├── data-model.md        # Phase 1: platform entities as GitOps resources
├── quickstart.md        # Phase 1: G0–G4 gates + V-* runtime validations
├── contracts/
│   ├── values-contract.md    # operator-facing values surface
│   ├── secrets-contract.md   # vault paths ↔ ExternalSecrets ↔ cluster Secrets
│   └── ztwim-assessment.md   # FR-011 living-record contract
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT created here)
```

### Source Code (repository root, additions only)

```text
values-global.yaml         # + global.dnsZone, global.acmeEmail
values-prod.yaml           # + namespaces (openshell, cert-manager, cert-manager-operator,
                           #   zero-trust-workload-identity-manager, agent-sandbox-system),
                           # + subscriptions (openshift-cert-manager-operator,
                           #   openshift-zero-trust-workload-identity-manager),
                           # + applications (below, waved), + openshell.* values block

charts/
├── agent-sandbox/         # vendored upstream helm/ @ v1.0.3 (research D5); resources+seccomp values
├── cert-manager-config/   # ClusterIssuers letsencrypt-{staging,prod}; token ExternalSecret;
│                          #   operator-readiness gate (lvms-operator-readiness precedent)
├── ztwim-config/          # cluster singleton CRs + ClusterSPIFFEID; operator-readiness gate
├── openshell-platform/    # privileged-SCC RoleBinding, ResourceQuota, LimitRange (D9)
├── openshell/             # wrapper: Chart.yaml OCI dependency 0.0.116 vendored (.tgz,
│                          #   digest-pinned) + upstream-research values (D2/D4/D8/D10)
├── openshell-policy/      # deny-all baseline + operator policy drop-in mechanism
└── openshell-demo/        # demo coding-agent assets (openshell.demo.enabled gate), OpenAI
                           #   ExternalSecret, harness image pinned

tests/
└── test-openshell-{render,ordering,pins,quota,secrets}.sh   # repo-convention shell tests

docs/
└── openshell-spiffe-assessment.md  # instantiated FR-011 living record (contracts/ztwim-assessment.md)
```

**Sync wave plan**: subscriptions (clustergroup) → `cert-manager-config` −6 (issuers after operand Ready) → `agent-sandbox` −5 (CRDs+controller before gateway) → `ztwim-config` −4 → `openshell-platform` −3 (SCC/quota) → KEK ExternalSecret ≤ −2 → `openshell` 0 → `openshell-policy` +1 → `openshell-demo` +2. Readiness-gate jobs mirror `charts/lvms-operator-readiness`.

**Structure Decision**: Repo-convention Validated Patterns layout — all feature material as local charts under `charts/`, wired through `values-prod.yaml` clusterGroup (namespaces/subscriptions/applications) exactly as `lvms-config`/`observability-config` precedents; shell tests under `tests/` mirroring existing naming; no new top-level directories except `docs/` for the living assessment.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| ZTWIM/SPIRE stack (+~5 pods) | Explicit user scope decision (clarify Q2: deploy now, integrate what's possible); SPIFFE issuance is a capability no existing pattern component provides | "Document-only readiness" fails the user's requirement; upstream community SPIRE duplicates ZTWIM and loses RHT support/GA backing |
| cert-manager operator (2 namespaces) | Publicly trusted gateway cert via DNS-01 per user decision (specify Q1); LE staging needed to respect 5/7d duplicate-SAN limit | Chart-internal PKI gives no WebPKI trust (custom CA per workstation); wildcard `*.apps` cert reuse considered, dedicated cert chosen for smaller blast radius |
| Vendored wrapper charts (agent-sandbox, openshell) | Git completeness: Argo CD cannot fetch OCI deps at sync time; NVIDIA's documented manifest URL is stale (404) | Multi-source OCI app leaves chart content outside Git and is unproven in this clustergroup version |
| OIDC via OpenShift built-in OAuth | Upstream: mTLS user-auth unsupported on Kubernetes gateways; no lab IdP exists | Deploying Keycloak (~GB footprint, HA concerns) for a single-user lab violates IV; `allowUnauthenticatedUsers` unsafe on a public FQDN |
