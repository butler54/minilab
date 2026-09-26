# Data Model: External Chart Sourcing

**Date**: 2026-09-24 | **Feature**: `007-openshell-external-charts`

All entities are GitOps constructs — desired state in Git, resolved by Argo CD at sync time. This feature changes **where upstream chart bits come from**, not the platform's runtime entity model (see 006's data-model.md for gateway/sandbox/identity entities).

## 1. ExternalChartRef

A pinned application-source entry in `values-prod.yaml`. The unit this feature exists to establish.

| Field | Type | Constraint |
|-------|------|------------|
| `name` | string | Matches the application key (e.g. `openshell`, `agent-sandbox`, `cert-manager`, `ztwim`) |
| `namespace` | string | Destination namespace (unchanged from 006) |
| `chart` | string (optional) | Chart name when the source is a helm chart (`helm-chart`, `ocp-certmanager`, `ztwim`) |
| `path` | string (optional) | Chart directory when the source is a git repository (`helm` for agent-sandbox); exactly one of `chart`/`path` per ref |
| `repoURL` | string (optional) | Present only when overriding the pattern default `global.multiSourceRepoUrl` (agent-sandbox git, NVIDIA ghcr) |
| `chartVersion` | string | **Exact, immutable** version. No ranges/wildcards for this feature's charts. `0.0.116`, `v1.0.3`, `0.1.1`, `0.2.0` |
| `extraValueFiles` | list[path] | Points at this app's dedicated override file(s) under `overrides/` |
| `annotations.sync-wave` | int | Per research.md D7 |

Validation rules (test-enforced): FR-001 (no upstream chart content under `charts/`); exact `chartVersion` on every ExternalChartRef; every ExternalChartRef's `extraValueFiles` exist.

## 2. PatternOwnedChart

Local Helm chart authored by this project — the ONLY permitted `charts/` content after this feature.

- `openshell-platform` — namespace posture: SCC RoleBinding, ResourceQuota/LimitRange, KEK ExternalSecret, gateway ServiceMonitor, ClusterSPIFFEID
- `openshell-extras` — OAuthClient, router-CA pull RBAC + fetch Job
- `openshell-policy` — policy documents (deny-all baseline, operator drop-ins)
- `openshell-demo` — OpenAI ExternalSecret + demo sandbox definition ConfigMap
- `cert-manager-config` — cloudflare token ExternalSecret ONLY (issuers moved to the VP chart)

Inviolable rule (FR-001): these directories MUST NOT contain vendored upstream templates, CRDs, packaged archives, or generated copies of upstream artifacts. Verified by `test-external-refs.sh`.

## 3. AppOverrideFile

Per-app values file under `overrides/`, consumed by exactly one application via its `extraValueFiles`:

| File | Serves | Content class |
|------|--------|---------------|
| `values-openshell-gateway.yaml` | `openshell` | NVIDIA chart root keys (no `openshell.` alias prefix): server, route, certManager, agentSandbox, image, supervisor, security contexts, credentials |
| `values-agent-sandbox.yaml` | `agent-sandbox` | image tag pin, namespace.create=false, resources, seccomp |
| `values-ztwim.yaml` | `ztwim` | `spire.*` — trustDomain, CA subject, persistence, disabled network policies |
| `values-certmanager.yaml` | `cert-manager` | `certmgrOperator`: channel + single ACME `acme` ClusterIssuer with Cloudflare DNS-01 solver |
| `values-openshell.yaml` | shared (all) | UNCHANGED `global.openshell.*` feature dials (006 contract superset; passthrough `openshell.*` block removed) |

Validation rules: `values-openshell.yaml` no longer contains a top-level `openshell:` passthrough key; dial↔override drift assertions map dials to their new locations (values test).

## 4. AcmeIssuer

The single ACME ClusterIssuer topology (D5).

| Field | Source of truth |
|-------|-----------------|
| `name` | constant `acme` |
| `spec.acme.server` | staging URL iff `openshell.issuer=staging`, prod URL iff `prod` |
| `spec.acme.privateKeySecretRef.name` | `letsencrypt-{staging,prod}-account-key` tracking the same dial |
| `spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef` | `{name: cloudflare-api-token, key: api-token}` (Secret from cert-manager-config) |
| `spec.acme.solvers[0].selector.dnsZones[0]` | `global.dnsZone` |

## Relationships

```text
ExternalChartRef --rendered-by--> clustergroup --> multi-source Application
    (external source) + (pattern values from git)
AppOverrideFile --injected into--> its ExternalChartRef's Application.helm.valueFiles
PatternOwnedChart --is-a--> local path Application (006 model, unchanged)
AcmeIssuer --referenced by--> openshell chart certManager.serverIssuerRef.name = "acme"
```
