# Review Log: OCP 5.0.1 Operator Review & OpenShell 0.1.8 Upgrade

**Feature**: 014-ocp501-openshell-upgrade | **Contract**: [contracts/operator-review.md](contracts/operator-review.md) | **Started**: 2026-11-14

## Preconditions (T001)

| Check | Result | Evidence |
|---|---|---|
| Cluster on OpenShift 5.0.1, healthy | PASS | `oc get clusterversion` → 5.0.1, AVAILABLE=True, PROGRESSING=False (queried 2026-11-14) |
| Chart 0.1.8 at pinned trusted source | PASS | `helm show chart oci://ghcr.io/nvidia/openshell/helm-chart --version 0.1.8` → version 0.1.8, appVersion 0.1.8, digest `sha256:39a56c77b78edd2a5c4ac7e17720b5720e1649e5e9f63743342a53940c01be81` |
| openshell CLI 0.1.8 installable | PASS (release-asset channel) | brew stable is 0.1.7 (lags); 0.1.8 assets published on the GitHub release (`openshell-checksums-sha256.txt` present) — `make install-openshell-cli` falls back to the release asset when brew stable ≠ chart pin |
| Working tree clean on `main`, pushed | PASS | commit `a4467e4` pushed to origin/main before value changes began |

Note: workstation CLI currently reports 0.1.7 (brew) while the chart pins 0.1.3 — pre-existing skew, resolved by T016/T018 in US2.

## Operator Review (US1)

### lvms-operator — UPDATE

- **Package**: lvms-operator
- **Pin before**: channel=`stable-4.22`, csv=`lvms-operator.v4.22.0`, approval=Automatic
- **Pin after**: channel=`stable-5.0`, csv=`lvms-operator.v5.0.0`, approval=Automatic
- **5.0.1 catalog state**: `stable-4.22`→v4.22.0; `stable-5.0`→v5.0.0; installed v4.22.0 Succeeded
- **Decision**: UPDATE — the lvms channel is version-tied to the platform (asserted against `global.lvmsCompatibility`); the catalog offers a clean `stable-5.0` channel.
- **Evidence**: catalog snapshot below (T003)

### eso — KEEP

- **Package**: openshift-external-secrets-operator
- **Pin before**: channel=`stable-v1`, csv=-, approval=not declared in Git (OLM default Automatic)
- **Pin after**: identical
- **5.0.1 catalog state**: `stable-v1`→v1.2.1; `stable-v1.2`→v1.2.1; installed v1.2.1 Succeeded, AtLatestKnown
- **Decision**: KEEP — already at its channel's latest CSV; the alternate `stable-v1.2` channel resolves to the same CSV (switching = gratuitous churn, constitution IV).
- **Evidence**: catalog snapshot below (T003)

### cluster-observability-operator — UPDATE (approval mode)

- **Package**: cluster-observability-operator
- **Pin before**: channel=`stable`, csv=-, approval=Manual
- **Pin after**: channel=`stable`, csv=-, approval=Automatic
- **5.0.1 catalog state**: `stable`→v1.5.5; `fast`→v1.5.5; installed v1.5.3 Succeeded with subscription `UpgradePending` and an unapproved Manual installplan for v1.5.4
- **Decision**: UPDATE (approval only) — the 010-era Manual pin blocks a platform-aligned upgrade; decided in Clarifications 2026-11-14. Channel stays `stable`.
- **Evidence**: catalog snapshot below (T003); pending installplan `install-8zr4s` (v1.5.4, Manual, approved=false)

### cert-manager-operator — KEEP

- **Package**: openshift-cert-manager-operator
- **Pin before**: channel=`stable-v1`, csv=-, approval=Automatic
- **Pin after**: identical
- **5.0.1 catalog state**: `stable-v1`→v1.20.1; `stable-v1.20`→v1.20.1; installed v1.20.1 Succeeded, AtLatestKnown
- **Decision**: KEEP — at latest CSV; alternate channel resolves to the same CSV.
- **Evidence**: catalog snapshot below (T003)

### ztwim — KEEP

- **Package**: openshift-zero-trust-workload-identity-manager
- **Pin before**: channel=`stable-v1`, csv=-, approval=Automatic
- **Pin after**: identical
- **5.0.1 catalog state**: `stable-v1`→v1.1.3; installed v1.1.3 Succeeded, AtLatestKnown
- **Decision**: KEEP — at latest CSV on its only channel.
- **Evidence**: catalog snapshot below (T003)

### rhbk — HOLD (upstream catalog gap)

- **Package**: rhbk-operator
- **Pin before**: channel=`stable-v26.6`, csv=-, approval=Automatic
- **Pin after**: identical (no 5.0.1-compatible channel exists to move to)
- **5.0.1 catalog state**: `rhbk-operator` package is **absent from Red Hat's v5.0 operator index** — both the OLM v1 clustercatalog (`openshift-redhat-operators`, source `registry.redhat.io/redhat/redhat-operator-index:v5.0`) and the legacy CatalogSource (`redhat-operators`, same image) serve the v5.0 index without it; `oc get packagemanifest rhbk-operator` → NotFound. Subscription condition: `ResolutionFailed=True (ConstraintsNotSatisfiable)` — "no operators found in package rhbk-operator in the catalog referenced by subscription rhbk-operator". Installed `rhbk-operator.v26.6.9-opr.1` remains **Succeeded** and Keycloak (OpenShell's OIDC IdP) keeps serving (pod events healthy, 2026-11-14).
- **Decision**: HOLD — the installed CSV is healthy and serving; the upgrade block is upstream (RHBK not yet published to the OCP 5.0 operator index), not a local pin error. Per the spec's edge case: record the gap, stay on the current pin, do not force-migrate to an unverified product (e.g., legacy `rhsso-operator` 7.6). Re-check trigger: when Red Hat publishes rhbk-operator for the 5.0 index, a follow-up updates the channel.
- **Evidence**: catalog snapshot below (T003); §RHBK investigation (T009)

### agent-sandbox — KEEP

- **Package**: agent-sandbox-operator
- **Pin before**: channel=`preview-0.9`, csv=`agent-sandbox-operator.v0.9.0`, approval=Automatic
- **Pin after**: identical
- **5.0.1 catalog state**: `preview-0.9`→v0.9.0 (only channel); installed v0.9.0 Succeeded, AtLatestKnown
- **Decision**: KEEP — at the channel head; no 5.0-specific channel offered.
- **Evidence**: catalog snapshot below (T003)

### patterns-operator — framework-managed, observational

- **Package**: patterns-operator (installed by the Validated Patterns framework; NOT declared in `clusterGroup.subscriptions` — no Git pin surface in this repo)
- **Observed state**: channel=`fast`→v0.0.82; installed v0.0.82 Succeeded, AtLatestKnown
- **Decision**: KEEP (observational) — healthy at channel head; out of the review's Git-decision scope.
- **Evidence**: catalog snapshot below (T003)

## Catalog Snapshot (T003)

(captured 2026-11-14)

### clustercatalogs (OLM v1)

```
NAME                            LASTUNPACKED   SERVING   AGE
openshift-certified-operators   55m            True      64d
openshift-community-operators   55m            True      64d
openshift-redhat-operators      54m            True      64d
```

Legacy CatalogSources (OLM v0, still present in openshift-marketplace): `redhat-operators`, `certified-operators`, `community-operators` (grpc, 64d). The legacy `packagemanifests` API serves 513 entries but is not a complete view of the v1 catalogs (rhbk-operator absent from it).

### Installed CSVs (pattern-relevant)

```
agent-sandbox-system                       agent-sandbox-operator.v0.9.0                 0.9.0            Succeeded
cert-manager-operator                      cert-manager-operator.v1.20.1                 1.20.1           Succeeded
external-secrets-operator                  openshift-external-secrets-operator.v1.2.1    1.2.1            Succeeded
keycloak-system                            rhbk-operator.v26.6.9-opr.1                   26.6.9-opr.1     Succeeded
openshift-cluster-observability-operator   cluster-observability-operator.v1.5.3         1.5.3            Succeeded
openshift-storage                          lvms-operator.v4.22.0                         4.22.0           Succeeded
patterns-operator                          patterns-operator.v0.0.82                     0.0.82           Succeeded
zero-trust-workload-identity-manager       zero-trust-workload-identity-manager.v1.1.3   1.1.3            Succeeded
```

### Subscription states

```
agent-sandbox-system                       agent-sandbox-operator             preview-0.9    AtLatestKnown   agent-sandbox-operator.v0.9.0
cert-manager-operator                      openshift-cert-manager-operator    stable-v1      AtLatestKnown   cert-manager-operator.v1.20.1
external-secrets-operator                  openshift-external-secrets-operator stable-v1     AtLatestKnown   openshift-external-secrets-operator.v1.2.1
keycloak-system                            rhbk-operator                      stable-v26.6   AtLatestKnown*  rhbk-operator.v26.6.9-opr.1  (*ResolutionFailed=True ConstraintsNotSatisfiable)
openshift-cluster-observability-operator   cluster-observability-operator     stable         UpgradePending  cluster-observability-operator.v1.5.3
openshift-storage                          lvms-operator                      stable-4.22    AtLatestKnown   lvms-operator.v4.22.0
patterns-operator                          patterns-operator                  fast           AtLatestKnown   patterns-operator.v0.0.82
zero-trust-workload-identity-manager       openshift-zero-trust-workload-identity-manager stable-v1 AtLatestKnown zero-trust-workload-identity-manager.v1.1.3
```

### Package channels (legacy packagemanifests view; rhbk-operator absent — see fallback)

```
lvms-operator: stable-4.22 (v4.22.0), stable-5.0 (v5.0.0)
openshift-external-secrets-operator: stable-v1 (v1.2.1), stable-v1.2 (v1.2.1)
cluster-observability-operator: fast (v1.5.5), stable (v1.5.5)
openshift-cert-manager-operator: stable-v1 (v1.20.1), stable-v1.20 (v1.20.1)
openshift-zero-trust-workload-identity-manager: stable-v1 (v1.1.3)
agent-sandbox-operator: preview-0.9 (v0.9.0)
patterns-operator: fast (v0.0.82)
```

**rhbk fallback evidence (packagemanifest absent)**: `oc get packagemanifest rhbk-operator` → NotFound; subscription `rhbk-operator` (source `redhat-operators/openshift-marketplace`, channel `stable-v26.6`) reports `CatalogSourcesUnhealthy=False AllCatalogSourcesHealthy` but `ResolutionFailed=True ConstraintsNotSatisfiable`; sibling Red Hat packages (e.g. `rhsso-operator`) resolve normally. Keycloak pods continue serving from the installed CSV. → investigated in T009.

## RHBK Investigation (T009)

**Question**: the rhbk-operator subscription reports `ResolutionFailed=True (ConstraintsNotSatisfiable)` on 5.0.1 — is a channel fix available, or is this an upstream gap?

**Findings** (2026-11-14):

1. `oc describe subscription -n keycloak-system rhbk-operator` → message: *"constraints not satisfiable: no operators found in package rhbk-operator in the catalog referenced by subscription rhbk-operator"*. Catalog health is fine (`AllCatalogSourcesHealthy`).
2. The subscription's source (`redhat-operators/openshift-marketplace`) serves `registry.redhat.io/redhat/redhat-operator-index:v5.0` — **the same image** as the OLM v1 clustercatalog `openshift-redhat-operators`. No catalog split-brain.
3. `oc get packagemanifest rhbk-operator` → NotFound; no rhbk-like package in any catalog (only `rhsso-operator` — the legacy RH-SSO product, channels `alpha`→7.5.1, `stable`→7.6.14 — and community `keycloak-operator`, `fast` channel).
4. The installed CSV `rhbk-operator.v26.6.9-opr.1` is Succeeded; Keycloak statefulset healthy and serving OpenShell OIDC.

**Conclusion**: Red Hat has not published the RHBK operator to the OCP 5.0 operator index (v5.0). No channel change can fix the subscription resolution; migrating to `rhsso-operator` would be a product downgrade and an unverified substitution (violates the review's own rules). **HOLD** recorded in the rhbk review record. The `ResolutionFailed` condition is expected to persist until upstream publication and is documented as upstream-gap evidence, not local drift. Follow-up trigger: re-check `oc get packagemanifest rhbk-operator` after Red Hat publishes RHBK for 5.0; then update `clusterGroup.subscriptions.rhbk.channel` in a follow-up feature.

## Upgrade Evidence (US2)

(pending)

## Acceptance Evidence (US3)

(pending)

## Imperative Steps (constitution II)

| # | Action | Rationale | Result | Reconcile-back |
|---|---|---|---|---|
| 1 | (pending) | | | |
