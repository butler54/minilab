# Data Model: OpenShell GitOps Platform

**Date**: 2026-09-23 | **Feature**: `006-openshell-gitops-install`

All entities are GitOps resources (desired state in Git, reconciled by Argo CD). Secret *values* live only in vault; Git carries ExternalSecret references and non-secret configuration. Derived from spec Key Entities plus Phase 0 research.

## 1. PlatformRelease (values-level entity)

The operator-facing dial surface for the whole feature (see `contracts/values-contract.md`). Not a cluster object — resolved at render time.

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `openshell.enabled` | bool | `false` | Master switch for all OpenShell applications/subscriptions |
| `openshell.gatewayHostname` | string (FQDN) | — | Route host AND `certManager.serverDnsNames[0]`; must sit under the operator-owned DNS zone |
| `openshell.acmeEmail` | string (email) | — | Let's Encrypt account contact for both ClusterIssuers |
| `openshell.issuer` | enum(`staging`,`prod`) | `staging` | Selects which ClusterIssuer the chart's `serverIssuerRef` points at |
| `openshell.trustDomain` | string | derived from DNS zone | ZTWIM trust domain; immutable once created (D7) |
| `openshell.sandbox.maxConcurrent` | int | `3` | Drives ResourceQuota sizing (SC-007 envelope) |
| `openshell.demo.enabled` | bool | `false` | Deploys the demonstration coding-agent assets |

Validation rules: `gatewayHostname` must end with the configured DNS zone; `issuer=prod` requires staging verified first (quickstart gate); `maxConcurrent` ≥ 1, ≤ 5 (SNO budget).

## 2. Gateway (StatefulSet `openshell/openshell`)

- **Identity**: SA `openshell` (chart-created).
- **State**: PVC `openshell-data`, 1Gi RWO (chart-hardcoded), cluster default SC (LVMS). Survives pod restart; required by FR-006.
- **Configuration (immutable-ish)**: chart values per `research.md` D10 (telemetry off, sideload pinned, topology combined, AppArmor Unconfined, pinned images).
- **TLS**: `openshell-server-tls` (internal CA, supervisors) + `openshell-server-external-tls` (ACME via our ClusterIssuer, route FQDN) — SNI-selected (D2).
- **Credential store**: KEK Secret `openshell-kek` (from vault via ExternalSecret) referenced by `server.credentialStorage.existingSecret` (D4). Loss of this secret = loss of stored provider credentials — vault is the recovery path.
- **Relationships**: requires AgentSandbox CRDs served (D5); requires ClusterIssuer Ready (D6); registers Sandboxes.

## 3. Sandbox (CR `sandboxes.agents.x-k8s.io/v1beta1`, namespaced to `openshell`)

- **Created by**: operator via `openshell` CLI through the gateway (runtime action — documented in quickstart, not Git).
- **Pod identity**: SA `openshell-sandbox`, granted `privileged` SCC via Git-managed RoleBinding to `system:openshift:scc:privileged` in `openshell` ns (FR-004, declarative replacement for `oc adm policy`).
- **Pod behavior**: supervisor sideloaded via init-container; topology `combined`; egress deny-by-default under operator-supplied policy (FR-008).
- **Storage**: per-sandbox workspace PVC, 2Gi default, cluster default SC.
- **Capacity**: bounded by namespace ResourceQuota/LimitRange (D9, FR-012).
- **Identity (when D8 ships)**: SPIFFE ID issued per `ClusterSPIFFEID` registration (Entity 6).

## 4. CertificateSet (cert-manager)

- **ClusterIssuers** `letsencrypt-staging` / `letsencrypt-prod`: ACME account key Secrets (`*-account-key`) live in `cert-manager` ns; solver Secret `cloudflare-api-token` (key `api-token`) in `cert-manager` ns from vault via ExternalSecret. Zone selector scopes issuance to the operator's zone.
- **Certificate** `openshell-server-external-tls` (chart-rendered, in `openshell` ns): `dnsNames=[gatewayHostname]`, Secret `openshell-server-external-tls` containing `tls.crt`+`tls.key` (no `ca.crt` for ACME — nothing consumes it).
- **Lifecycle**: cert-manager auto-renews (~30d before 90d expiry); key rotates on renewal (rotationPolicy Always); gateway must tolerate key rotation (verification V-TLS).

## 5. WorkloadIdentity (ZTWIM operand)

 Singleton `cluster` CRs (immutable trustDomain/clusterName) → SPIRE server (StatefulSet, 2Gi PV, sqlite) + agent (DaemonSet, 1 pod on SNO) + CSI driver (DaemonSet plugin `csi.spiffe.io`, host sockets `/run/spire/agent-sockets`).

- **Trust domain**: `<operator DNS zone>`-derived (D7); format `spiffe://<trustDomain>/<path>`.
- **State**: SPIRE datastore PV + bundle ConfigMap named by `bundleConfigMap`.

## 6. ClusterSPIFFEID `openshell-sandbox-workloads` (D8)

- **Selector**: namespace `openshell`, SA `openshell-sandbox`.
- **ID template**: `/openshell/sandbox` (single identity for the sandbox class; per-pod uniqueness deferred — YAGNI at lab scale).
- **Consumers**: gateway chart with `server.providerTokenGrants.spiffe` enabled; supervisor exchanges JWT-SVID → OpenAI access token at the gateway/proxy layer.

## 7. SandboxPolicy (operator-supplied content, Git-managed mechanism)

- **Baseline (feature-shipped)**: deny-all egress baseline + policy plumbing (chart values/ConfigMap surface per upstream) in `charts/openshell-policy/`.
- **Operator content (not shipped)**: substantive allow rules, including the OpenAI endpoint rule used by the demo, come from the operator's own policy documents dropped into the same Git location (spec clarification Q1).
- **Format**: upstream OpenShell policy YAML — validated at CI time by a render/lint test (repo `tests/`), not by schema we define.

## 8. DemoAgent (FR-014)

- **Definition**: Git-managed config for the demonstration coding-agent sandbox (sandbox name, harness image pinned by tag/digest from `quay.io/aipcc/base-images/agentic/` per Red Hat blog supply-chain guidance, OpenAI model/endpoint reference).
- **Credential path**: OpenAI API key — vault → ExternalSecret → Secret in `openshell` ns consumed **by the gateway's provider credential store** (D8), never by the sandbox pod.
- **Observability**: metrics scraped via ServiceMonitor into the pattern's monitoring stack (FR-009); OCSF events stay CLI-served.

## Entity relationships

```text
PlatformRelease ──renders──> Gateway ──requires──> AgentSandbox CRDs ──> Sandbox
Gateway ──TLS──> CertificateSet (letsencrypt-prod) ──solver──> cloudflare-api-token (vault)
Gateway ──KEK──> openshell-kek (vault)
WorkloadIdentity ──issues──> ClusterSPIFFEID ──identity──> Sandbox
Gateway ──exchanges JWT-SVID──> OpenAI token (provider key from vault, gateway-side only)
DemoAgent ──runs-in──> Sandbox ──egress-governed-by──> SandboxPolicy
```
