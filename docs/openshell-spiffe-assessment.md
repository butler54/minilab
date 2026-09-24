# OpenShell ↔ SPIFFE/ZTWIM readiness assessment

Living record per `specs/006-openshell-gitops-install/contracts/ztwim-assessment.md`.
**Update this file in the same PR as any ZTWIM or OpenShell version change.**

## Snapshot

| Field | Value |
|-------|-------|
| Last updated | 2026-09-24 (feature 006 implementation) |
| Recorder | `/speckit.implement` run, branch 006-openshell-gitops-install |
| Target | OCP 4.22 SNO, OpenShell chart 0.0.116 (vendored) |

## Operator availability

| Item | Status | Evidence |
|------|--------|----------|
| ZTWIM operator for OCP 4.22 | **Available, GA** (v1.1.1, channel `stable-v1`, Automatic install plans) | OCP 4.22 ZTWIM chapter; operator release catalog (research.md D7) |
| Deployed via pattern | Wired: Subscription `ztwim` + `charts/ztwim-config` (singleton `cluster` CRs) | values-prod.yaml, charts/ztwim-config/ |
| SVID issuance on-cluster | **Pending verification** — testing phase V-SPIFFE | — |

## OpenShell integration points

| Integration point | Status | Evidence / trigger |
|-------------------|--------|--------------------|
| `server.providerTokenGrants.spiffe` (gateway exchanges sandbox JWT-SVID → provider token) | **CONSUMABLE at 0.0.116** — values + gateway config + `csi.spiffe.io` mounts confirmed in vendored chart (research F1). Wired ON in `charts/openshell/values.yaml`. End-to-end exchange **pending V-SPIFFE** | vendored chart templates |
| SPIFFE identity of the agent runtime itself (per Red Hat blog roadmap) | **DEFERRED** — not shipped upstream as of 0.0.116 | Re-evaluate on each OpenShell release notes / chart values diff |
| ClusterSPIFFEID registration for `openshell-sandbox` pods | Configured (`/openshell/sandbox`); behavioral verification pending (ClusterSPIFFEID is thinly covered in OCP docs) | testing phase V-SPIFFE |

## Re-evaluation triggers

1. Any OpenShell chart bump (run the charts/openshell/README.md update procedure and re-run V-SPIFFE).
2. Any ZTWIM operator release beyond 1.1.1 on `stable-v1`.
3. OpenShell release notes mentioning "agent identity", "SVID lifecycle", or workload-level attestation.

## Deferred items (explicit)

- SPIFFE identity for the agent *runtime* (identity-for-provider-credentials only).
- Per-pod SPIFFE IDs (`/openshell/sandbox` class-level identity is the lab-scope choice).
- SPIRE OIDC discovery provider (not needed for in-cluster token exchange).
