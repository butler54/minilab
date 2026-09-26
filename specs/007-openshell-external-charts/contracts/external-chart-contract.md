# Contract: External Chart Registry

**Feature**: `007-openshell-external-charts` | **Phase 1 artifact**

The authoritative registry of every upstream chart the pattern consumes. Any change to source, kind, or version is a reviewed change to this table (and the matching values entries). New upstream charts require the same registry row first.

| Chart (logical) | Source kind | Source URL | Path/Chart | Pinned version | Application key | Values file |
|-----------------|-------------|------------|------------|----------------|-----------------|-------------|
| NVIDIA OpenShell gateway | OCI (ghcr) | `ghcr.io/nvidia/openshell` | chart `helm-chart` | `0.0.116` | `openshell` | `overrides/values-openshell-gateway.yaml` |
| Agent Sandbox controller | Git (GitHub) | `https://github.com/kubernetes-sigs/agent-sandbox` | path `helm` | `v1.0.3` (tag) | `agent-sandbox` | `overrides/values-agent-sandbox.yaml` |
| cert-manager operator+issuer (VP) | OCI (quay VP) | `quay.io/validatedpatterns` (pattern default) | chart `ocp-certmanager` | `0.2.0` | `cert-manager` | `overrides/values-certmanager.yaml` |
| ZTWIM SPIRE config (VP) | OCI (quay VP) | `quay.io/validatedpatterns` (pattern default) | chart `ztwim` | `0.1.1` | `ztwim` | `overrides/values-ztwim.yaml` |
| HashiCorp Vault (existing) | OCI (quay VP) | `quay.io/validatedpatterns` | chart `hashicorp-vault` | `0.1.*` (existing pattern decision, out of scope) | `vault` | — |
| External Secrets (existing) | OCI (quay VP) | `quay.io/validatedpatterns` | chart `openshift-external-secrets` | `0.0.*` (existing, out of scope) | `secrets-operator` | — |

## Rules

1. **Exact pins** for this feature's four charts (FR-006): no `*`, no `latest`, no branch names (the agent-sandbox git ref is an immutable release tag, asserted in `test-external-refs.sh`).
2. **One source of truth**: a chart's version appears in exactly one place — its application entry in `values-prod.yaml`. Values files never duplicate the version.
3. **Digest verification on version bump** (FR-004 edge case): when bumping any of the four, record the upstream artifact digest (chart tgz digest via `helm show chart`/skopeo, or git tag→commit) in the bump commit message.
4. **Subscriptions for operators stay in clustergroup `subscriptions:`** (cert-manager operator, ZTWIM operator, and the existing lvms/eso/coo) — operator installation is patterned config, not a vendored artifact.
