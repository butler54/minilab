# Research: External Chart Sourcing — Decisions

**Date**: 2026-09-24 | **Feature**: `007-openshell-external-charts`

## D1 — Refactor approach: framework multi-source, one mapping per upstream chart

**Decision**: Replace all vendored upstream charts with clustergroup multi-source applications (verified mechanism, `templates/plumbing/applications.yaml` of clustergroup-chart 0.9.x): an app entry with `chartVersion:` renders as a two-source Application — source 1 = pattern git (`ref: patternref` for values files), source 2 = external `repoURL` with `chart:`+`targetRevision` or `path`+`targetRevision`. Per-app `extraValueFiles` carry each app's upstream-chart values from this repo.

**Rationale**: Native mechanism; no vendoring, no wrapper charts, values stay reviewable in-Git; identical model to the reference `../coco-pattern` (all its apps use `chart:` + `chartVersion:` against `quay.io/validatedpatterns`).

**Alternatives rejected**: (a) keep vendoring (user-declared fundamental flaw), (b) umbrella wrapper chart with OCI deps (still copies upstream bits into Git and needs `helm dep build` per bump), (c) single-source helm apps (no pattern values-file injection; loses shared global values).

## D2 — Chart-by-chart source mapping

| Upstream chart | Source | Reference in `values-prod.yaml` |
|---|---|---|
| NVIDIA OpenShell 0.0.116 | OCI registry `ghcr.io/nvidia/openshell` | `chart: helm-chart, chartVersion: 0.0.116` |
| kubernetes-sigs/agent-sandbox | GitHub git source (only distribution; no published artifact verified 2026-09-24) | `repoURL: https://github.com/kubernetes-sigs/agent-sandbox, path: helm, chartVersion: v1.0.3` |
| cert-manager operator + ClusterIssuer | VP community chart `ocp-certmanager` (OCI `quay.io/validatedpatterns`) | `chart: ocp-certmanager, chartVersion: 0.2.0` |
| ZTWIM operand config | VP community chart `ztwim` (OCI) | `chart: ztwim, chartVersion: 0.1.1` |

- OCI refs use bare registry form (`ghcr.io/...`, `quay.io/...`) — the framework's `chart:` source form (proven by coco-pattern); pinned to **exact versions** (FR-005 constitution: no `*` ranges for this feature's charts).
- ZTWIM operator + cert-manager operator **subscriptions stay in clustergroup `subscriptions:`** (operator install is pattern configuration, not a copied chart — matches lvms/eso precedent).

## D3 — Pattern-owned content that stays local (NOT upstream copies)

- `charts/openshell-platform/` — SCC RoleBinding, ResourceQuota/LimitRange, KEK ExternalSecret, ServiceMonitor (our namespace posture).
- `charts/openshell-extras/` (NEW, from wrapper `templates/`): OAuthClient + router-CA pull RBAC/Job (our OIDC integration manifests).
- `charts/openshell-policy/`, `charts/openshell-demo/` — our policy documents / demo assets.
- `charts/cert-manager-config/` — **slimmed** to only our `cloudflare-api-token` ExternalSecret (issuers move to VP chart), kept for wave-ordered secret-first semantics.
- `cluster-spiffe-id` moves INTO `charts/openshell-platform/` (our workload registration).
- Wiring stays in `values-prod.yaml`; new per-app override files added under `overrides/` (D4).

## D4 — Values layout: app-dedicated override files

**Decision**: each externally-sourced app gets a dedicated override file consumed ONLY by it via `extraValueFiles` (framework-supported), because upstream charts render at values root (no subchart alias when used directly):

- `overrides/values-openshell-gateway.yaml` — NVIDIA chart root keys: `server.*`, `openshiftRoute.*`, `certManager.*`, `agentSandbox.*`, `image.*`, `supervisor.*`, `podSecurityContext`, `securityContext`, `credentialStorage` (all ported from 006's `charts/openshell/values.yaml` + passthrough dials, dropping the `openshell.` alias prefix).
- `overrides/values-agent-sandbox.yaml` — `image.tag=v1.0.3`, `namespace.create=false`, resources, `containerSecurityContext.seccompProfile` (ported from vendored values; template hardcodes image.tag reality via values test).
- `overrides/values-ztwim.yaml` — `spire.trustDomain` ← `openshell.trustDomain|dnsZone`, CA subject, `persistence.size 2Gi`, default-deny NetworkPolicies OFF (lab).
- `overrides/values-certmanager.yaml` — `certmgrOperator: {operatorChannel: stable-v1, issuers: [{acme: {...cloudflare dns01...}}]}`.
- `overrides/values-openshell.yaml` — **unchanged** `global.openshell.*` feature dials + `openshell.*` subchart passthrough REMOVED (superseded by the gateway override); drift guards updated to compare dials vs the new override files.

## D5 — ACME issuer topology change (VP chart constraint)

**Decision**: one ClusterIssuer named `acme` (VP `ocp-certmanager.chart` renders `ClusterIssuer` per issuer-map key, and the key doubles as the ACME spec kind; staging+prod as separate issuers is not supported). `openshell.issuer` now flips the ACME **server** URL (+ account-key secret name) in `values-certmanager.yaml`; the gateway's `certManager.serverIssuerRef.name` is constant `acme`.

- Simpler than 006's two-issuer design; identical safety semantics (staging server URL until flip).
- Values test asserts: `openshell.issuer: staging` ⇔ ACME server URL `acme-staging-v02...`; `prod` ⇔ `acme-v02...`.

## D6 — ClusterSPIFFEID and ZTWIM CRs via VP `ztwim` chart

VP chart renders `ZeroTrustWorkloadIdentityManager`, `SpireServer` (with valid `jwtIssuer` helper — the T047 trap is designed out upstream), `SpireAgent`, `SpiffeCSIDriver`, optional OIDC discovery, network policies (we keep policies off). It does NOT render ClusterSPIFFEID registrations (workload-specific) → ours lives in `charts/openshell-platform/`.

## D7 — Wave plan (applications in `values-prod.yaml`)

```
-7 cert-manager-config   (cloudflare token ExternalSecret — secret first)
-6 cert-manager          (VP ocp-certmanager: operator-adjacent config + acme ClusterIssuer)
-5 agent-sandbox         (git source, CRDs+controller)
-4 ztwim                 (VP ztwim: SPIRE stack)
-3 openshell-platform    (SCC, quota, KEK ES, ServiceMonitor, ClusterSPIFFEID)
-1 openshell-extras      (OAuthClient, router-CA fetch job)
 0 openshell             (NVIDIA chart externals source)
+1 openshell-policy
+2 openshell-demo
```

Unchanged blocks: lvms-config -10, vault/eso ops, observability +20. Deviations from 006: cert-manager gains its own wave; extras split from the wrapper chart.

## D8 — Test strategy transformation

Rendering external sources offline: `helm template` against OCI/git sources requires fetching (network). Suites keep running offline by **rendering via the fetchable external charts with locally fetched fixtures?** — rejected (recreates vendoring-by-test). Chosen approach:

- Suite evolution: value/render assertions now synthesize **merged-values assertions** (yq-merge of values files → property checks) rather than `helm template` runs for external apps; `helm template` still runs for our LOCAL charts. Fetch-based smoke (`helm template oci://... --version X | spot-check`) is added as an OPTIONAL online step in CI/testing-phase, not a make-gate.
- New test `test-external-refs.sh`: SC-001/SC-002 proofs — no upstream chart content under `charts/` (heuristics: no `templates/**` from upstream signatures, no `*.tgz`, no `crds/` dirs), every external app has exact-version `chartVersion`, and agent-sandbox pin is an immutable tag (`v1.0.3`, not branch).
- Existing suites keep validating: dials contract, secrets contract, quota math (local charts render), ordering (now incl. VP/external apps), pins (now scans override files + app entries), ztwim assertions (now against OUR remaining ClusterSPIFFEID + values-ztwim intent).

## Residual risks

| Risk | Mitigation |
|------|------------|
| ghcr OCI ref syntax mismatch on target cluster's ArgoCD | V-REF quickstart check on designated cluster: Application renders `helm-chart@0.0.116` Healthy; fallback `repoURL: oci://...` form documented |
| Clustergroup `0.9.*` floor below multi-source support | Runtime floor assert in testing phase (V-ORDER checks rendered Application kinds); upgrade path = bump `clusterGroupChartVersion` globally (separate change) |
| agent-sandbox tag force-push (immutable-by-convention only) | `test-external-refs.sh` records expected tag shape; testing-phase records upstream tag→commit binding |
| VP chart values drift (`ztwim` 0.1.x, `ocp-certmanager` 0.2.x) | Exact version pins + per-app override keys asserted by suites |
| Local render tests lose `helm template` depth for external charts | Online smoke step in testing phase; offline merged-values asserts cover rule-based properties |
| `openshell.*` passthrough removal breaks 006-era test expectations | Suites updated in the same change set (007 tasks), no stale assertions survive |
