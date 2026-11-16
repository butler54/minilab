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

## US1 Convergence Evidence (T010–T012)

**Static gates (T010)**: `make test-static` — all shell tests passed (incl. updated lvms assertions); `./pattern.sh make validate-schema` — all assertions passed. Recorded 2026-11-14.

**Commit (T011)**: `89e8865` "feat(014): US1 — operator alignment to OCP 5.0.1..." pushed to `main` 2026-11-14; follow-up chart fixes `d14b9f2`, `bcaf87d`, `7f3fd8f`, `26e68f9` pushed 2026-11-15 (see remediation below).

**Convergence (T012)**, verified 2026-11-15:

| Check | Result |
|---|---|
| lvms subscription | `channel=stable-5.0`, `state=AtLatestKnown`, `installed=lvms-operator.v5.0.0` |
| lvms CSV | `lvms-operator.v5.0.0` **Succeeded** (replaced v4.22.0); operator pod Running |
| LVMCluster | `minilab-lvmcluster` **Ready** (condition met) |
| StorageClass | `lvms-loopback` (default): `WaitForFirstConsumer` / `Retain` — unchanged |
| cluster-observability | `state=AtLatestKnown`, `installed=v1.5.5` **Succeeded** (replaced v1.5.3 via Automatic installplan `install-w9dnc`) |
| eso / cert-manager / ztwim / agent-sandbox / patterns-operator | all `AtLatestKnown`, CSVs Succeeded (unchanged, as decided) |
| rhbk | documented HOLD — subscription `ResolutionFailed` (upstream catalog gap, see T009); installed CSV v26.6.9-opr.1 Succeeded, Keycloak serving |
| lvms-config app | **Synced + Healthy**; readiness hook job **Succeeded** ("Reached expected number of succeeded pods") and self-deleted per HookSucceeded policy |
| All other applications | 17/18 apps Synced+Healthy |

**Known display artifacts (documented, not drift)**:
- Root app `minilab-prod` shows **Degraded** solely from `Subscription/rhbk-operator` health (ResolutionFailed, upstream hold — FR-004 documented hold applies). Expected to persist until Red Hat publishes RHBK for OCP 5.0.
- Root app shows **OutOfSync** on four child Application CRs (observability-config, openshell-demo, openshell-policy, vault) — verified empty diff via `argocd app diff`; all four children are Synced+Healthy. An app-of-apps status artifact following the interrupted operations; no functional difference exists. Self-resolves on Argo's next full reconciliation or next Git change.
- The root app's sync operations end "unsuccessfully" (retry loop) because of the rhbk Failed health; applies complete regardless. Root operations were terminated manually once the applies were done (see imperative steps).

**Convergence remediation (chart fixes, all in Git)**:
1. `d14b9f2` — readiness job checked `deployment/topolvm-controller` + `daemonset/topolvm-node`, which never existed on this cluster (stack runs `vg-manager`); replaced with parameterized `daemonset/vg-manager` (`global.lvmsCompatibility.daemonSet`). Pre-existing defect surfaced by the re-sync.
2. `bcaf87d`/`7f3fd8f`/`26e68f9` — LVMS v5.0.0 ships a default-deny NetworkPolicy in `openshift-storage` allowing only its own pods; the readiness job was blocked from the API (i/o timeout to 172.30.0.1:443). Added `charts/lvms-config/templates/readiness-netpol.yaml` mirroring the operator's own allow rule (egress TCP 6443 — OVN-K evaluates post-DNAT, so the API service's 443 presents as the host-networked endpoint on 6443; DNS 5353 to openshift-dns). Final job run: Succeeded.


## Upgrade Evidence (US2)

**0.1.8 delta audit (T013, FR-012)**, 2026-11-15:
- Policies (`charts/openshell-policy/policies/*.yaml`): clean — all endpoint hosts are plain hostnames (opencode.ai, models.opencode.ai, matilda.maincode.com, api.openai.com; no `::ffff:` mapped IPv6); filesystem paths are system paths outside the writable workspace (0.1.8's symlink rule targets paths *inside* a writable workspace); binary paths already kernel-resolved per the 011 contract; all credentialed endpoints use `protocol: rest` (no WebSocket flows — the 403-on-upgrade change is not triggered).
- Demo drivers (`deploy/openshell/demo/run-demo.sh`): `openshell status -g "$GATEWAY"` preflight at line 31 already treats non-zero exit as failure — the 0.1.8 semantics (non-zero for unregistered gateway) strengthen the check; no change needed.
- `gateway.ocsfLog.enabled` **re-tested at 0.1.8**: `helm template` of chart 0.1.8 with `ocsfLog.enabled=true` renders zero OCSF wiring (same as 0.1.3) — upstream #3264/#3876 still open. Override comment updated; value stays unset.

**Pin change (T014–T016)**: commit `acdc5e3` — `values-prod.yaml` chartVersion `0.1.3`→`0.1.8`; `overrides/values-openshell-gateway.yaml` gateway/sandboxRuntime/supervisor tags → `0.1.8`; tests updated (`test-openshell-pins.sh`, `test-openshell-render.sh`, `test-external-refs.sh` — the latter two also carried 0.1.3 pins, caught by T019 gates).

**Teardown (T017)**: idempotent delete loop cleared 7 leftover sandboxes (fw, coco, sandboxctl, analysis, network, cliptest, docs — Nov 4–13 leftovers); final `openshell sandbox list` → "No sandboxes found."

**CLI (T018)**: `make install-openshell-cli` — brew stable (0.1.7) lags; installed 0.1.8 via the GitHub-release fallback (checksum verified); `make check-openshell-cli` passed. Gateway device login pending user authorization (see below).

**Gates (T019)**: `make validate-openshell` ✓, `make test-static` ✓ (after the two additional test pins updated), `./pattern.sh make validate-schema` ✓.

**Convergence (T020)**, verified 2026-11-15: commit `acdc5e3` pushed; openshell app sync initially raced the push and the argocd JWT expired mid-flight (re-issued); after refresh+sync: **openshell app Synced+Healthy, "successfully synced (all tasks run)"**, gateway StatefulSet image `ghcr.io/nvidia/openshell/gateway:0.1.8`, fresh pod `openshell-0` Running with 0 restarts; all 5 openshell apps (openshell, -demo, -keycloak-config, -platform, -policy) Synced+Healthy. CLI `openshell status -g k8s` verification pending gateway login.


## Acceptance Evidence (US3)

**Stage 1 — static suite (T021)**, 2026-11-16: `make test-static` ✓, `make validate-openshell` ✓ — all shell tests pass (lvms + openshell pin assertions at 0.1.8/stable-5.0).
**Stage 2 — schema (T021)**: `./pattern.sh make validate-schema` ✓ — all assertions passed.
**Stage 3 — CLI tie (T021)**: `make check-openshell-cli` ✓ — "openshell CLI version check passed (0.1.8)".
**Stage 4 — convergence (T022)**, 2026-11-16:
- `make validate-cluster` ✓ — connectivity, auth, StorageClass, OCP version compatibility all pass.
- `make argo-healthcheck` ✗ → **fail→documented**: fails on `vp-gitops/minilab-prod` only. Root cause (verified, not drift): (a) health **Degraded** from `Subscription/rhbk-operator` `ResolutionFailed` — the documented upstream hold (RHBK absent from the OCP 5.0 operator index; see T009); (b) sync **OutOfSync** display on 4 child Application CRs (observability-config, openshell-demo, openshell-policy, vault) — `argocd app diff` shows an empty diff and all four children are Synced+Healthy; a status artifact of the interrupted sync operations. All other 17 applications Synced+Healthy. Remediation of (a) requires upstream publication (follow-up trigger recorded); (b) is cosmetic and self-resolves on the next completed root sync.
- Environment note: `make argo-healthcheck`/`validate-cluster` initially failed with "playbook rhvp.cluster_utils.* could not be found" — the collection is not on Galaxy; installed `rhvp.cluster_utils:1.1.0` from `git+https://github.com/validatedpatterns/rhvp.cluster_utils.git` into `~/.ansible/collections` and ran make with `ANSIBLE_COLLECTIONS_PATH` exported (environment fix; the gates themselves unmodified).
- 010 CPU posture: `olmconfig.cluster.spec.features.disableCopiedCSVs=true` — the no-op CSV copy-status PUT mechanism is intact (olm-config app Synced+Healthy).
- Drift found and removed during the check: stale duplicate `Application/minilab-prod` in `openshift-gitops` namespace (created 2026-10-26, never reconciled — no status; feature-013-era leftover in the wrong Argo namespace). Finalizer removed first to prevent cascade, then deleted. Healthcheck failure count dropped from 2 to 1 (the documented root-app hold only).
- Orphaned Completed sandbox pods `api-watch2`/`cache-quorum-diag` (48d old) deleted from `openshell` namespace (zero-residual, FR-010).

**Stages 5–7 (T023–T025)**: pending gateway device-login authorization (CLI OIDC token expired; fresh code issued).


## Imperative Steps (constitution II)

| # | Action | Rationale | Result | Reconcile-back |
|---|---|---|---|---|
| 1 | Hard-refresh annotations on `minilab-prod` + `lvms-config` apps (`oc patch ... argocd.argoproj.io/refresh`) | Argo poll cadence too slow for interactive convergence (FR-003 permits recorded forced syncs) | Refresh triggered; root sync started | No state change — comparison only |
| 2 | `oc port-forward svc/vp-gitops-server -n vp-gitops 18443:443` + `argocd login` (admin) | argocd CLI needed to force syncs; CLI context expects local forward | Session established (re-established 2026-11-15 after oc token expiry) | No cluster state change |
| 3 | `argocd app sync lvms-config` (twice, 2026-11-14) | lvms-config manual/auto sync needed nudge post-push | Resources applied; readiness hook job created | All applied state matches Git (app Synced) |
| 4 | Deleted orphaned `minilab-lvmcluster-default-storage` SA/ClusterRole/ClusterRoleBinding (openshift-storage) | Argo flagged as prune-orphans; no chart/repo reference exists (pre-v5.0.0 operator artifact); blocked root sync via lvms-config OutOfSync | lvms-config → Synced+Healthy; root sync unblocked | Drift removal per constitution I; verified storageclass still default, LVMCluster Ready |
| 5 | `argocd app terminate-op minilab-prod` (2026-11-14 and 2026-11-15) | Operation pinned to pre-push manifest retried endlessly on rhbk Failed health; blocked manifest refresh | New sync picked up 89e8865; subscriptions applied | Applies match Git; terminating an operation changes no state |
| 6 | Deleted stale COO installplan `install-8zr4s` (v1.5.4, Manual, unapproved) | Created under the old Manual policy; OLM does not retro-approve Manual plans after the Git switch to Automatic | OLM generated Automatic `install-w9dnc` (v1.5.5), approved and installed | Installplan is OLM-owned transient state; subscription spec remains Git-declared |
| 7 | Deleted failing `lvms-config-readiness` job + removed Argo hook finalizer (`oc patch ... /metadata/finalizers`) — several times | Job blocked by missing netpol (see chart fixes); stuck Terminating on Argo hook finalizer, blocking sync operations | Job recreated fresh after each fix; final run Succeeded | Hook job is Argo-managed transient state, recreated from Git on each sync |
| 8 | `oc adm release info --image-for=cli` | Discover the OCP 5.0 CLI image digest for `global.lvmsCompatibility.cliImage` (B2 remediation) | `ocp-v5.0-art-dev@sha256:74e575...` recorded in values-global.yaml | Value now Git-declared |
| 9 | `argocd app diff minilab-prod` (verification only) | Confirm the root's OutOfSync display on 4 child Application CRs is cosmetic | Empty diff — no functional difference | Read-only |
