# Research: OpenShell GitOps Platform — Decisions

**Date**: 2026-09-23 | **Feature**: `006-openshell-gitops-install`

All external unknowns resolved. Sources cited per decision; full verification notes in `quickstart.md` where runtime behavior must be confirmed during implementation.

## D1 — OpenShell chart: v0.0.116, vendored into a local wrapper chart

**Decision**: Deploy NVIDIA OpenShell chart **0.0.116** (`oci://ghcr.io/nvidia/openshell/helm-chart`, chart version == appVersion) via a local wrapper chart `charts/openshell/` that carries the upstream chart as a committed, version-pinned dependency (Chart.yaml `dependencies:` + vendored `.tgz`, pinned by digest).

- The Red Hat blog's 0.0.85 is outdated; 0.0.116 is the newest verified release (docs site default "Latest (v0.0.116)"; GitHub release 2026-08-28). Sources: https://docs.nvidia.com/openshell/llms.txt, https://github.com/NVIDIA/OpenShell/releases
- **Rationale**: Git must contain complete desired state (Constitution I); Argo CD cannot run `helm dependency build` on OCI dependencies at sync time; vendoring keeps the chart bits in-Git, reviewable, and pinned.
- **Alternatives considered**: (a) Argo CD multi-source app pointing at the OCI registry — clustergroup-chart support for arbitrary OCI sources is unproven in this pattern and chart content leaves Git; (b) imperative `helm install` — violates GitOps-first. Both rejected.

## D2 — Gateway exposure: chart-managed Route + cert-manager external cert (SNI split)

**Decision**: Let the chart render the passthrough Route itself (`openshiftRoute.enabled=true`, `openshiftRoute.host=<gateway FQDN>`) with `certManager.enabled=true`, `certManager.serverIssuerRef={kind: ClusterIssuer, name: letsencrypt-prod}`, `certManager.serverDnsNames[0]=<same FQDN>`. `server.disableTls=false` (required when `openshiftRoute.enabled`). Dedicated hostname certificate (not the `*.apps` wildcard) — smaller blast radius; wildcard reuse remains an accepted alternative per spec assumptions.

- Chart behavior verified: route template targets service port `grpc` with `tls.termination: passthrough`; install **fails** if `host` is not in `certManager.serverDnsNames`, and if `server.disableTls=true`. With cert-manager enabled the chart creates **two** server certs — internal (`openshell-server-tls`, chart CA, cluster-local SANs for supervisors) and external (`openshell-server-external-tls`, our ClusterIssuer, route FQDN only) — and selects between them by **SNI**. A public ACME issuer for the external cert while the internal CA keeps serving supervisors is an explicitly supported design. Source: https://docs.nvidia.com/openshell/kubernetes/managing-certificates
- `pkiInitJob.serverDnsNames` applies only to self-signed mode — **do not** copy the FQDN into it.
- Gotchas to honor: public CA certs must not carry internal SANs (chart fails install); `server.grpcEndpoint` must stay cluster-internal (supervisors can't verify the ACME cert); keep `certManager.clientCaFromServerTlsSecret=true` (default).

## D3 — User authentication: OpenShift built-in OAuth as OIDC issuer (verify at implementation)

**Decision**: Configure `server.oidc.*` against OpenShift's built-in OAuth server's discovery endpoint, with `server.oidc.caConfigMapName` referencing a ConfigMap carrying the cluster ingress CA (value exists in chart values for non-public issuers). Verification task in quickstart (V-AUTH).

- **Forcing fact**: mTLS client certificates are **not supported for user authentication on Kubernetes gateways** — "the Helm chart does not render `mtls_auth`"; Kubernetes deployments must use OIDC or a trusted access proxy. Sources: https://docs.nvidia.com/openshell/kubernetes/access-control, https://docs.nvidia.com/openshell/reference/gateway-auth
- This supersedes the spec assumption (spec updated in place 2026-09-23).
- **Alternatives considered**: (a) Deploy Keycloak — heavyweight IdP for a single-user lab violates Simplicity First, rejected; (b) `server.auth.allowUnauthenticatedUsers=true` behind a trusted proxy — adds a proxy component and weakens authN on a public FQDN, rejected; (c) port-forward-only local access — preserved as documented fallback if OpenShift-OAuth-as-OIDC proves incompatible.

## D4 — GitOps rendering requirements of the OpenShell chart

**Decision**: Set `agentSandbox.preflight.enabled=false` (server-side `helm template` cannot discover cluster APIs) and `server.credentialStorage.existingSecret=<gateway KEK secret>` (chart's `lookup`-based KEK generation breaks under GitOps rendering; the KEK Secret is created by External Secrets from vault, so it survives re-renders and rebuilds — SC-004 depends on this).

- Source: chart 0.0.116 values comments (both flags documented as required for GitOps workflows).

## D5 — Agent Sandbox prerequisite: vendored upstream Helm chart @ v1.0.3

**Decision**: Vendor `kubernetes-sigs/agent-sandbox` **v1.0.3** `helm/` chart directory into `charts/agent-sandbox/` (core controller only, `controller.extensions=false`), image pinned `registry.k8s.io/agent-sandbox/agent-sandbox-controller:v1.0.3`, explicit small resources (upstream sample: 10m/64Mi req, 500m/128Mi lim), `seccompProfile: RuntimeDefault`. Argo CD renders chart `crds/` automatically; enable Server-Side Apply for the application.

- Latest release v1.0.3 (2026-09-17); released YAML is huge (single-file manifest would exceed annotation limits) and the **NVIDIA-documented `releases/latest/download/manifest.yaml` URL is stale (404)** — the repo's own `helm/` chart is the clean GitOps source. Sources: https://github.com/kubernetes-sigs/agent-sandbox/releases/tag/v1.0.3, `helm/` in repo at v1.0.3
- Controller is distroless non-root, API-access-only; fits `restricted-v2` SCC as-is — **no privilege grants needed**. RBAC covers pods/PVCs/services/events/leases/sandboxes only.
- Kubernetes compatibility: OCP 4.22 ships Kubernetes 1.35 (release-4.22 rebased on v1.35.8); agent-sandbox states no minimum, built on client-go v0.37 — compatible. OpenShell needs only `agents.x-k8s.io` v1beta1 served (v1.0.x removed v1alpha1; preflight accepts v1beta1).
- **Alternatives considered**: vendor flattened `sandbox.yaml` as Helm templates — works but one 206 KB blob and no values surface; the OLM bundle — adds an unnecessary operator packaging layer. Both rejected.

## D6 — cert-manager: Red Hat operator via OLM Subscription; LE staging + prod ClusterIssuers

**Decision**: Add Subscription `openshift-cert-manager-operator` (channel `stable-v1`, `redhat-operators`, namespace `cert-manager-operator` with its own OperatorGroup; operand lands in hardcoded `cert-manager` namespace, operand cert-manager v1.20.3). Manage issuers in `charts/cert-manager-config/`: two ClusterIssuers (`letsencrypt-staging`, `letsencrypt-prod`), ACME `dns01.cloudflare.apiTokenSecretRef={name: cloudflare-api-token, key: api-token}`, `selector.dnsZones=[<operator domain>]`. The API-token Secret is delivered to the `cert-manager` namespace by External Secrets from vault and must sync **before/with** the issuers (workaround for eager solver validation in operand ≤1.21.0).

- Package/channel verified via operator bundle metadata; GA (CSV maturity stable). Upstream jetstack Helm chart (v1.21.2) rejected: outside the repo's OLM-subscription convention. Sources: github.com/openshift/cert-manager-operator bundle, https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/
- Staging issuer required during bring-up: Let's Encrypt production allows only **5 duplicate certificates per identical SAN set per 7 days**; GitOps churn would burn that in one afternoon. Flip the chart's `serverIssuerRef` to `letsencrypt-prod` once issuance is proven. Source: https://letsencrypt.org/docs/rate-limits/
- Cloudflare **API Token** (not global key), permissions `Zone:DNS:Edit` + `Zone:Zone:Read` scoped to the single zone.
- ACME-issued Secrets contain `tls.crt`/`tls.key` only (no `ca.crt`) — nothing in the design consumes `ca.crt`.

## D7 — ZTWIM: GA 1.1.1 via OLM Subscription; singleton `cluster` CRs

**Decision**: Add Subscription `openshift-zero-trust-workload-identity-manager` (channel `stable-v1`, **only channel**; namespace `zero-trust-workload-identity-manager` with its own OperatorGroup; current CSV v1.1.1 — GA, no feature gates, `installPlanApproval: Automatic` documented). Manage `charts/ztwim-config/` with singleton CRs (`metadata.name: cluster`) in that namespace: `ZeroTrustWorkloadIdentityManager` (trustDomain from operator-owned domain, clusterName, bundleConfigMap), `SpireServer` (sqlite3 datastore, 2Gi PV on cluster default SC, rsa-2048 CA), `SpireAgent` (k8sPSAT node attestor, k8s workload attestor), `SpiffeCSIDriver` (defaults: plugin `csi.spiffe.io`, socket dir `/run/spire/agent-sockets`). Set explicit small `resources` on each CR (operator applies none by default).

- Component versions at 1.0.0: SPIRE server/agent 1.13.3, spire-controller-manager 0.6.3, SPIFFE CSI driver 0.2.8. Sources: ZTWIM chapter in OCP 4.22 Security & Compliance guide; github.com/openshift/zero-trust-workload-identity-manager(-release) catalogs + samples
- `trustDomain`/`clusterName` on the top-level CR are effectively immutable — treat as create-once (documented in repo; recreate procedure = delete operator CRs then re-apply, which invalidates issued identities).
- Workload registration uses `ClusterSPIFFEID` (spire-controller-manager): selector on namespace+ServiceAccount; functional in the operator but thinly documented in OCP docs — verify empirically (V-SPIFFE in quickstart).

## D8 — SPIFFE integration point: real, and stronger than expected

**Decision**: Integrate OpenShell with ZTWIM via **`server.providerTokenGrants.spiffe`** (present in upstream OpenShell docs and repo `main`; **must be verified against chart 0.0.116 values at implementation** — V-SPIFFE). The sandbox supervisor fetches a JWT-SVID from `csi.spiffe.io` and exchanges it for a short-lived provider token; the OpenAI key therefore lives **only at the gateway** (delivered from vault) and never enters the sandbox execution context. A `ClusterSPIFFEID` registers the `openshell-sandbox` identity (e.g. `/openshell/sandbox`).

- Sources: github.com/NVIDIA/OpenShell `examples/spiffe-token-grant-demo`, https://docs.nvidia.com/openshell/latest/reference/gateway-config; chart mounts `csi.spiffe.io` volumes into gateway and sandbox pods when enabled
- Impact on spec artifacts: FR-010/FR-014 satisfied **without** injecting the OpenAI key into the sandbox secret/env at all — the ExternalSecret for OpenAI lands in the gateway path only. US4's "integrate what is consumable" becomes a live integration, not just groundwork.
- Fallback if 0.0.116 lacks the shipped values: ZTWIM still deploys (user decision), the demo uses a gateway-side registered provider credential without SPIFFE exchange, and the gap is recorded per FR-011 with re-evaluation trigger "OpenShell release documenting `providerTokenGrants.spiffe` in chart values".

## D9 — Resource guardrails: ResourceQuota + LimitRange in the `openshell` namespace

**Decision**: Enforce the 3-concurrent-sandbox envelope with a `ResourceQuota` (pods count + CPU/memory ceilings sized for gateway + 3 sandboxes × expected profile) and a `LimitRange` (default requests/limits for sandbox pods) in `openshell`, in `charts/openshell-platform/`. Reason: chart 0.0.116 exposes **no per-sandbox CPU/memory or max-concurrency knobs** (verified against `values.yaml` and gateway-config reference); namespace quota is the only GitOps-native enforcement. Known limitation recorded as a residual risk: per-sandbox sizing is operator-policy territory (the operator brings their own policy config; quota is the backstop).

## D10 — Operational defaults pins

**Decision**: `server.telemetryEnabled=false`; `supervisor.sideloadMethod=init-container` (explicit — OCP 4.22/K8s 1.35 auto-detect would pick `image-volume`, but ImageVolume is not GA until K8s 1.36 and its OCP 4.22 enablement state is unverified); gateway `image.tag=0.0.116`; `server.sandboxImage` pinned to a concrete tag/digest (default is a floating `latest` community image — FR-005); `server.appArmorProfile=Unconfined` (upstream-documented requirement for supervisor netns mounts); `supervisor.topology=combined` (default; full enforcement). Gateway StatefulSet DB: chart-hardcoded 1Gi RWO PVC, inherits cluster default StorageClass (LVMS) — FR-006 satisfied without configuration. Sandbox workspace PVCs: `server.workspaceDefaultStorageSize=2Gi` (default), default SC.

## Implementation findings (added 2026-09-24, recorded for traceability)

- **F1 — SPIFFE integration confirmed present in 0.0.116** (T035 gate PASSED; upgrades D8 from probable-consumable to consumable): `server.providerTokenGrants.spiffe.{enabled,workloadApiSocketPath}` in values; gateway config renders `provider_spiffe_workload_api_socket_path`; workload template mounts CSI volume driver `csi.spiffe.io` in gateway and sandbox pods. Source: vendored `charts/openshell` dependency templates.
- **F2 — FR-008 partial deviation**: 0.0.116 has **no declarative policy source** (policy mutation exists only via authenticated API; user auth is interactive OIDC, so a headless in-cluster applier is impossible). Policy content lives in Git (`charts/openshell-policy` → ConfigMap); application to sandboxes is a documented imperative step (Constitution II), checklist-tracked. **Evaluation re-run 2026-09-24 (T049)**: exhaustive check of the vendored 0.0.116 values + gateway config confirms no policy file/ConfigMap/watch mechanism — only `policyValidationFailureMode` for API-submitted candidates. No migration available at the pinned version; re-check at every upstream bump (charts/openshell/README.md update procedure).
- **F3 — OIDC CA source**: gateway `server.oidc.caConfigMapName` points at ConfigMap `openshell-oidc-ca` (openshell ns), populated by a least-privilege fetch Job from `router-ca` (openshift-config-managed). OAuthClient is a PUBLIC PKCE client (`openshell-cli`, no secret) — audience matches upstream default; redirect URIs are placeholders confirmed in V-AUTH.
- **F4 — Supervisor metrics**: gateway Service exposes `metrics` port 9090 (ServiceMonitor shipped); supervisor metrics are per-ephemeral-sandbox-pod — extend with PodMonitor if V-METRICS finds a stable port.
- **F5 — ImageVolume**: on OCP 4.22 (K8s 1.35) upstream auto-detect would choose `image-volume` (pre-GA); pinned `init-container` per D10.

## Residual risks

| Risk | Mitigation |
|------|------------|
| OpenShift OAuth as OIDC issuer unverified | V-AUTH task; fallback = port-forward local access, gap recorded (D3) |
| ~~`providerTokenGrants.spiffe` in 0.0.116~~ **RESOLVED (F1)** — confirmed present in vendored chart | Remaining: verify ZTWIM-issued SVID end-to-end exchange in V-SPIFFE |
| ClusterSPIFFEID behavior thinly documented by OCP | V-SPIFFE empirical check (identity issued to labeled pod) |
| cert-manager operand ≤1.21.0 solver-validation staleness | Sync ordering: token Secret before/with issuer; documented restart workaround |
| LE prod duplicate-SAN rate limit (5/7 days) | Staging issuer first; prod flip only after proven issuance |
| nftables optional-expression failures on RHCOS (upstream-documented) | V-EGRESS verifies required reject rules in effect, not just requested |
| PKI hook jobs re-randomizing trust roots on upgrade | cert-manager mode removes TLS generation from hooks (JWT-only hook remains); verify on first upgrade |
