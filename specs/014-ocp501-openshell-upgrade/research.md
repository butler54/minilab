# Research: OCP 5.0.1 Operator Review & OpenShell 0.1.x Upgrade

**Date**: 2026-11-14 | **Method**: live queries against the upgraded cluster (`oc` 4.22.15 client vs. server 5.0.1, Kubernetes 1.36.5) and upstream sources (GitHub `NVIDIA/OpenShell` releases, `ghcr.io` OCI registry).

## 1. Operator hub on OpenShift 5.0.1 — catalog findings

Cluster state confirmed: `clusterversion` 5.0.1, Available. OLM on 5.0.1 runs a hybrid: legacy v0 `Subscriptions`/`CatalogSources` (redhat/certified/community, grpc, still in `openshift-marketplace`) coexist with OLM v1 `clustercatalogs` (`openshift-redhat-operators`, `openshift-certified-operators`, `openshift-community-operators`, all Serving=True). The legacy `packagemanifests` API serves 513 entries but is **not a complete view** of the v1 catalogs (relevant to RHBK below).

Per-operator findings (package manifests queried 2026-11-14; installed CSVs via `oc get csv -A`):

| Operator (subscription) | Pinned (Git) | 5.0.1 catalog | Installed | Decision |
|---|---|---|---|---|
| lvms-operator | `stable-4.22`, CSV `v4.22.0` | `stable-4.22`→v4.22.0; **`stable-5.0`→v5.0.0** | v4.22.0 Succeeded | **UPDATE** to `stable-5.0` / `v5.0.0` |
| openshift-external-secrets-operator | `stable-v1` | `stable-v1`→v1.2.1; `stable-v1.2`→v1.2.1 | v1.2.1 Succeeded | **KEEP** (already latest CSV on its channel) |
| cluster-observability-operator | `stable`, approval **Manual** | `stable`→v1.5.5; also `fast`→v1.5.5 | v1.5.3 Succeeded, subscription `UpgradePending`, Manual installplan for v1.5.4 unapproved | **UPDATE** approval → Automatic (converges to v1.5.5) |
| openshift-cert-manager-operator | `stable-v1` | `stable-v1`→v1.20.1; `stable-v1.20`→v1.20.1 | v1.20.1 Succeeded | **KEEP** |
| openshift-zero-trust-workload-identity-manager | `stable-v1` | `stable-v1`→v1.1.3 | v1.1.3 Succeeded | **KEEP** |
| `rhbk-operator` | `stable-v26.6` | **no `rhbk-operator` packagemanifest**; subscription condition `ResolutionFailed=True (ConstraintsNotSatisfiable)` though catalogs healthy | v26.6.9-opr.1 Succeeded (existing install keeps running) | **INVESTIGATE & FIX or HOLD** — see §2 |
| agent-sandbox-operator | `preview-0.9`, CSV `v0.9.0` | `preview-0.9`→v0.9.0 (only channel) | v0.9.0 Succeeded | **KEEP** |
| patterns-operator (framework-managed) | — (not declared in `clusterGroup.subscriptions`) | `fast`→v0.0.82 | v0.0.82 Succeeded | **KEEP (observational)** — installed by the Validated Patterns framework, not pattern-pinned |

Note (analysis remediation F1): the review's completeness gate counts the **seven pattern-declared subscription keys** in `values-prod.yaml` (`lvms-operator`, `eso`, `cluster-observability-operator`, `cert-manager-operator`, `ztwim`, `rhbk`, `agent-sandbox`). The on-cluster `patterns-operator` subscription is framework-managed — it has no Git pin surface in this repo — so it appears in the review artifact as an observational note only.

### Decisions & rationale

**Decision (lvms)**: move channel `stable-4.22` → `stable-5.0`, CSV `lvms-operator.v4.22.0` → `lvms-operator.v5.0.0`, in `values-prod.yaml` (`clusterGroup.subscriptions.lvms-operator`) and `values-global.yaml` (`global.lvmsCompatibility`: channel, startingCSV, `ocpRelease` 4.22→5.0, and the `cliImage` digest — the 4.22 pinned `ocp-v4.0-art-dev@sha256:84b0aa6...` must become the 5.0-appropriate digest, discoverable from the 5.0 release payload). Update `tests/test-lvms-ordering.sh` assertions in the same change; verify `charts/lvms-config` renders correctly against the stable-5.0 CSV (LVMCluster CRD compatibility).
- *Rationale*: lvms is the storage layer; its channel is version-tied to the platform (test asserts `ocpRelease == 4.22`). Running a 4.22-named operator CSV on 5.0.1 is exactly the stale-pin risk the feature exists to remove. The catalog offers a clean `stable-5.0` channel.
- *Alternatives considered*: staying on `stable-4.22` (rejected: currently installable/healthy but version-mismatched with the platform); `fast`-style channels (not offered for lvms).

**Decision (cluster-observability)**: switch `installPlanApproval` Manual → Automatic (FR-011), same commit as review recording. The subscription is already `UpgradePending` with an unapproved Manual installplan (v1.5.4) — after switching, OLM proceeds; the catalog's latest is v1.5.5. Stale Manual installplans (`install-8zr4s` for v1.5.4) may need one recorded cleanup step or natural supersession — observe first, act only if stuck.
- *Rationale*: decided in Clarifications 2026-11-14; the 010-era churn-stabilization served its purpose and Manual now blocks a platform-aligned upgrade.
- *Alternatives considered*: keep Manual + one-off approved installplan (rejected: leaves a recurring manual escape hatch); `fast` channel (rejected: `stable` is the appropriate cadence).

**Decision (eso, cert-manager, ztwim, agent-sandbox)**: KEEP all pins. Each is `AtLatestKnown` with its channel's latest CSV installed and Succeeded; eso/cert-manager's alternate channels (`stable-v1.2`, `stable-v1.20`) resolve to the same CSVs, so switching would be gratuitous churn (constitution IV). The framework-managed patterns-operator subscription (v0.0.82, channel `fast`) is likewise healthy and is recorded as an observational KEEP — it has no Git pin surface in this repo.
- *Alternatives considered*: migrating eso→`stable-v1.2` and cert-manager→`stable-v1.20` for future-proofing (rejected: no functional difference today; revisit when the `stable-v1` channels stop receiving updates).

## 2. RHBK resolution failure on 5.0.1 (investigation item)

**Observed**: `rhbk-operator` subscription (package `rhbk-operator`, channel `stable-v26.6`, source `redhat-operators/openshift-marketplace`) reports `CatalogSourcesUnhealthy=False` but **`ResolutionFailed=True (ConstraintsNotSatisfiable)`**. The installed CSV `rhbk-operator.v26.6.9-opr.1` remains Succeeded, so Keycloak (OpenShell's OIDC IdP) keeps serving — but upgrades are blocked and the pin cannot be validated against the 5.0.1 catalog. `oc get packagemanifest rhbk-operator` → NotFound, while sibling Red Hat packages (e.g., `rhsso-operator`) resolve; the 513-entry legacy packagemanifests view does not aggregate all OLM v1 `clustercatalog` content.

**Decision**: resolve at execution as the review's one open investigation — enumerate what the 5.0.1 catalogs actually serve for RHBK (query the `openshift-redhat-operators` clustercatalog contents / Red Hat operator docs for the RHBK 5.0-era package name and channels, e.g., a newer `stable-v26.x`). Then either update the subscription channel in Git, or record a documented hold (installed CSV healthy, upgrade blocked upstream) — both outcomes satisfy FR-004. Keycloak downtime risk to OpenShell auth is the acceptance-relevant concern: any RHBK change must precede the OpenShell acceptance run, or the hold must be recorded first.
- *Rationale*: the spec's edge case for "Red Hat build lagging the platform release" covers this; force-migrating to an unverified channel would violate the review's own rules.
- *Alternatives considered*: pinning RHBK to rhsso-operator (rejected: different product); ignoring the condition (rejected: FR-001 requires an explicit decision).

## 3. OpenShell 0.1.3 → 0.1.8 (latest stable 0.1.x)

**Decision**: target **0.1.8** (released 2026-11-10; latest stable, `dev` pre-release excluded). Chart verified available at the pinned trusted source: `oci://ghcr.io/nvidia/openshell/helm-chart`, version 0.1.8, digest `sha256:39a56c77b78edd2a5c4ac7e17720b5720e1649e5e9f63743342a53940c01be81`, appVersion 0.1.8. CLI 0.1.8 available via brew/GitHub release assets (`openshell-checksums-sha256.txt` published).
- *Rationale*: spec defines "latest 0.1.*" as newest stable 0.1.x at upgrade time; 0.1.8 is it. 0.1.4–0.1.8 is a five-release jump, so the intermediate upgrade notes compound — captured below.
- *Alternatives considered*: stepping through each release (rejected: chart upgrades replace state directly; no migration value in intermediates); waiting for 0.1.9 (rejected: no reason to hold; rollback policy already decided).

### Release-note findings that affect this deployment (0.1.4 → 0.1.8)

- **OCSF 1.8.0 only** (0.1.7, breaking): OpenShell now emits OCSF 1.8.0 records only; `ocsf_schema_version`-style settings are deprecated and ignored. Any OCSF evidence collection in acceptance must expect 1.8.0 records.
- **OCSF attribution moved** (0.1.8): supervisor events use `device.container.uid`/`device.container.name`; gateway Activity/Detection events use `resources[].type: "sandbox"`; other classes use `unmapped.sandbox_id`/`unmapped.sandbox_name`. Collectors reading top-level `container.uid` must be updated if any local parsing exists.
- **Filesystem policy paths through symlinks now fail sandbox launch** (0.1.8), including best-effort mode. **Directly relevant to the policy-at-create mechanism validated in feature 012** — demo policies must be checked for symlink-traversing paths and rewritten to target paths.
- **IPv4-mapped IPv6 endpoints** (0.1.8): rules like `host: "::ffff:203.0.113.7"` must become plain IPv4. Audit demo policies for mapped-IPv6 hosts.
- **REST endpoints return 403 for HTTP upgrade requests** in enforce and audit modes (0.1.8): WebSocket traffic needs explicit `protocol: websocket` rules. Relevant if any demo flow uses WebSockets.
- **Gateway memory leak on deleted sandboxes fixed** + no 3.4 MiB/sandbox stream pre-allocation (0.1.8): improves the repeated create/delete cycles the acceptance suite performs.
- **Kubernetes sandbox deletion no longer waits the 30s pod grace period** (0.1.8): teardown checks in the demo smoke get faster.
- **CLI renews expired OIDC client-credentials tokens** (0.1.8) and the Go SDK now shares `oidc_token.json` with the CLI — run `openshell gateway login` once after upgrading to replace older token files (helps the auth smoke; partially mitigates minilab#9 token-expiry pain).
- **`openshell status --gateway <name>` now exits non-zero when the gateway is not registered** (0.1.8): scripts using `openshell status` for preflight must expect the new exit semantics.
- **Gateways refuse to start without auth configured** (0.1.6): our gateway has Keycloak OIDC — satisfied; `config preflight` now warns when `allow_unauthenticated_users` is set (it is not).
- **Supervisor/sandbox-runtime compatibility** (0.1.6): new sandboxes open the control connection sandbox→supervisor; supervisor and sandbox-runtime binaries must move together — our pin set already drift-asserts exactly this.
- Chart features gained along the way (no action, note only): Restricted-PSS namespace install (0.1.5), `server.extraEnv` (0.1.6), metrics TLS (0.1.8), `priorityClassName`/`topologySpreadConstraints` (0.1.8).

### Pin surfaces to change (single commit)

`values-prod.yaml` → `clusterGroup.applications.openshell.chartVersion: "0.1.3"` → `"0.1.8"`; `overrides/values-openshell-gateway.yaml` → gateway/sandboxRuntime/supervisor `image.tag` `"0.1.3"` → `"0.1.8"` (3 tags); `tests/test-openshell-pins.sh` expected version; workstation CLI via `make install-openshell-cli` (reads the chart pin); `make check-openshell-cli` must pass unmodified.

## 4. Acceptance-suite surface (verified from Makefile)

Stages: `make validate-openshell` (static: values, secrets, quota, render, ordering, pins, ztwim), `make test-static` (full static suite incl. lvms assertions), `make check-openshell-cli` (version tie), `make validate-openshell-live` (Keycloak OIDC + gateway auth smoke; needs `oc` + DNS), `make validate-openshell-demo` (scripted V-DEMO smoke via `deploy/openshell/demo/run-demo.sh --smoke`; skips when cluster/gateway unreachable — during acceptance the skip conditions must NOT trigger, else the stage counts as failed per FR-008), plus a manual sandbox create/use/teardown lifecycle check with zero-residual verification. Full contract: [contracts/acceptance-suite.md](contracts/acceptance-suite.md).

## 5. Unresolved items handed to tasks

None blocking. The RHBK channel enumeration (§2) is an execution-time investigation with a decided contingency, not an open design question.
