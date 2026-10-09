# Root-Cause Analysis: minilab CPU Saturation

**Date**: 2026-10-09 (JST)
**Cluster**: `sno` (single-node OpenShift 4.22.13 / K8s 1.35.6, 8 CPU, control-plane+worker)
**Analyst session**: `/speckit.specify` for `010-reduce-cpu-usage`

## Executive Summary

The dominant cause of CPU saturation is a **reconciliation war between ArgoCD and OLM**
over the `agent-sandbox-controller` Deployment. OLM retries a permanently-failing CSV
install ~6–7 times per second with no backoff, producing ~23 PUTs/s on
`clusterserviceversions` and ~110/s total API traffic. GitOps cadence (180s) and
default 30s Prometheus scraping are secondary contributors.

## Evidence

### 1. Node-level baseline

```text
$ oc adm top nodes
NAME   CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
sno    7652m        102%     22375Mi         77%
```

Top CPU consumers (`oc adm top pods -A`):

| Pod | CPU |
|-----|-----|
| kube-apiserver-sno (openshift-kube-apiserver) | 2706m |
| olm-operator (openshift-operator-lifecycle-manager) | 1458m |
| vp-gitops-application-controller-0 | 1029m |
| etcd-sno | 295m |
| prometheus-k8s-0 (openshift-monitoring) | 280m |
| api-server/monitoring stacks otherwise | <150m each |

### 2. Root cause — CSV install loop (OLM vs ArgoCD)

`oc get csv -n agent-sandbox-system` → phase **Failed**;
ArgoCD app `agent-sandbox` → sync status **Unknown**.

The Deployment `agent-sandbox-system/agent-sandbox-controller`:

- **ArgoCD copy** (Helm, app `agent-sandbox`, created 2026-09-26): selector
  `{"matchLabels":{"app.kubernetes.io/instance":"agent-sandbox","app.kubernetes.io/name":"agent-sandbox"}}`
- **OLM CSV copy** (`agent-sandbox-operator.v0.9.0`): expects selector
  `{"matchLabels":{"app":"agent-sandbox-controller"}}`

Same name, different **immutable** selectors → every OLM install attempt fails:

```text
Warning  InstallComponentFailed  Deployment.apps "agent-sandbox-controller" is
invalid: spec.selector: Invalid value: {"matchLabels":{"app":"agent-sandbox-controller"}}:
field is immutable
```

OLM log (`oc logs deploy/olm-operator --since=30m`) shows a continuous sub-second
retry loop: `NeedsReinstall → Pending → AllRequirementsMet → InstallComponentFailed →
Failed → NeedsReinstall …`, each cycle emitting 3 API events plus CSV status writes.

### 3. API-server load attribution (queried via prometheus-k8s-0)

Total `apiserver_request_total` rate over 10m: **~109/s**

| Verb | Rate |
|------|------|
| GET | 46.4/s |
| PUT | 43.9/s |
| LIST | 7.5/s |
| WATCH | 5.8/s |

PUTs by resource:

| Resource | Rate |
|----------|------|
| operators.coreos.com/clusterserviceversions | **23.4/s** |
| serviceaccounts | 10.5/s |
| coordination.k8s.io/leases | 4.7/s |
| operators.coreos.com/operators | 3.4/s |
| apps/deployments | 1.3/s |

→ CSV status churn alone is over half of all cluster PUTs; this is consistent with the
OLM retry loop and confirms the causal chain OLM loop → kube-apiserver 2.7 CPU.

The sandbox controller pod crashed (#6 restart) with
`connect: connection refused` to the API server at 2026-10-04 05:05 JST — node
saturation / API unavailability is already taking workloads down.

### 4. GitOps cadence

- ArgoCD `vp-gitops` (gitops-operator) has **no** `timeout.reconciliation` override →
  default **180s** cluster-wide resync for 16 applications.
- Git polling: default 3-min interval, no webhooks.
- `argocd-cm` otherwise stock; three apps OutOfSync / Unknown
  (`lvms-config`, `minilab-prod` OutOfSync; `agent-sandbox` Unknown).
- Application-controller CPU (1029m) is inflated by CSV/deployment churn from §2 —
  every failed cycle mutates tracked resources.

### 5. Monitoring cadence

- `cluster-monitoring-config` (openshift-monitoring) is **empty** → platform
  default 30s scrape, 30s rule evaluation for all targets.
- Additional `MonitoringStack/minilab` (minilab-observability): prometheus 9m,
  alertmanager 2m — negligible.
- UWM not enabled; no custom scrape overrides anywhere.

### 6. Minor recurring load

- `imperative/unsealvault-cronjob`: `*/5 * * * *`, image 667MB (cached, but pod churn
  + kubelet work every 5 min for 18 days).
- `openshift-marketplace` catalog pods poll/reload at default cadence
  (~15m + 11m CPU observed).
- Vault itself runs 50m; spire agent 24m — acceptable.

## Root-Cause Chain

```
ArgoCD Helm Deployment agent-sandbox-controller  ┐
(selector A)                                     ├─ same ns/name, immutable selector clash
OLM CSV agent-sandbox-operator.v0.9.0            ┘
        │
        ▼
OLM hot retry loop (no backoff, ~6–7 cycles/s)
        │
        ├─► 23 PUT/s on CSVs  ─┐
        ├─► 3 events/cycle      ├─► kube-apiserver 2.27–2.7 CPU
        ├─► olm-operator 1.46 CPU (spinning reconcile)
        └─► ArgoCD app 'agent-sandbox' = Unknown, extra reconcile passes
              └─► application-controller ~1 CPU
```

## Remediation Levers (ranked by expected savings)

| # | Action | Expected savings | Scope |
|---|--------|------------------|-------|
| 1 | Single-owner the sandbox controller Deployment (keep OLM Subscription in GitOps; stop ArgoCD rendering the operator's Deployment with a divergent selector; recreate the Deployment once imperatively) | ~1.5–2 CPU (olm + apiserver PUT storm) + app-controller relief | P1 |
| 2 | `timeout.reconciliation` → ≥3600s (+ webhook/manual refresh path) | few hundred m cores steady-state | P2 |
| 3 | Monitoring scrape interval default tuning (platform overrides) | tens–low-hundreds m cores on prometheus + api LIST/GET | P3 |
| 4 | Unseal cron cadence, catalog polling | tens of m cores | P4 |

## Notes

- All remediation must land in Git per constitution Principle I; the one-time
  Deployment delete/recreate falls under Principle II (record-and-reconcile).
- Verification: re-run top/apiserver-rate queries after each lever lands so savings
  are attributable (spec FR-011).

## Appendix A — Pre-Change Snapshot (T001, 2026-10-09T04:35Z)

Immediately before repair execution.

- **GitOps namespace correction**: the repo's GitOps instance is `ArgoCD/vp-gitops` in namespace `vp-gitops` (validated-patterns install), **not** `openshift-gitops`. All leaked-app remediation targets `vp-gitops`. Spec/plan/contract references to `openshift-gitops`-as-app-namespace are hereby corrected; the repair script (T008) auto-detects.
- **Node live**: `sno` 7848m CPU (104% of 8-CPU allocatable), 77% memory — fire still burning.
- **Top CPU pods**: kube-apiserver 2235m, insights-runtime-extractor 1505m, olm-operator 1345m, vp-gitops-application-controller-0 835m, prometheus-k8s-0 509m, etcd 257m.
- **ArgoCD CR** `vp-gitops/vp-gitops`: `spec.resourceCustomizations` **absent** (as expected); controller processors default; limits 2 CPU/8Gi.
- **ConfigMap cluster-monitoring-config** (openshift-monitoring): **absent** (as expected — CMO running full defaults).
- **Leaked Application** `vp-gitops/agent-sandbox` (rv 23173439): multi-source app rendering upstream `helm` chart from `kubernetes-sigs/agent-sandbox@v1.0.3` with pattern valueFiles; `syncPolicy.automated: {}` (prune absent), `retry.limit: 20`; parent tracking `minilab-prod`. Full YAML archived at `$TMPDIR/minilab-metrics/leaked-app.yaml`.
- **Leaked app tracked resources (4, confirmed)**:
  - `Deployment agent-sandbox-system/agent-sandbox-controller` (1/1 running, 12d)
  - `ClusterRole agent-sandbox-controller`, `ClusterRole agent-sandbox-controller-extensions`, `ClusterRoleBinding agent-sandbox-controller`
- **Untracked co-located objects** (not in app inventory): `Service agent-sandbox-controller`, `Service sandbox-router-svc`, `ServiceAccount agent-sandbox-controller`, builder/default/deployer SAs — these belong to the OLM install / namespace defaults; deleting the ArgoCD app does not touch them.
- **CRDs** `agents.x-k8s.io`: untracked by ArgoCD (per research); **Sandbox CRs: 0 cluster-wide**.
- **CSV** `agent-sandbox-operator.v0.9.0`: Phase `Failed`, reason `AllRequirementsMet` ("all requirements found, attempting install") — hot OLM retry loop still active (replicas of the Failed CSV are copied cluster-wide by OLM, e.g. `assisted-installer` namespace shows the Failed copy).
- **Application health snapshot**: `agent-sandbox` Sync=Unknown/Healthy; `lvms-config` **OutOfSync** (pre-existing, unrelated drift — noted for US4 review); `minilab-prod` OutOfSync (expected: the leaked child app is its out-of-Git divergence).
- **Rollback reference**: if anything regresses, archived `leaked-app.yaml` can be re-applied; no CRDs or CRs are affected by the app deletion.

## Appendix B — Repair Preconditions Verification (T002, 2026-10-09T04:37Z)

All four contract preconditions **PASS**:

| # | Precondition | Result |
|---|---|---|
| 1 | `Application/vp-gitops/agent-sandbox` exists | ✅ `agent-sandbox  Unknown  Healthy` |
| 2 | Absent from `values-prod.yaml clusterGroup.applications` | ✅ python parse confirms `agent-sandbox` not a `applications` key; only the OLM `subscriptions.agent-sandbox` (Red Hat build, preview-0.9, CSV pinned) remains — the correct single-owner declaration |
| 3 | No sandbox workloads (`sandboxes,sandboxclaims,sandboxtemplates,sandboxwarmpools -A`) | ✅ zero across all namespaces |
| 4 | CSV `agent-sandbox-operator.v0.9.0` exists | ✅ present (phase flaps `Failed`↔`InstallReady` mid-loop, as expected pre-repair) |

## Appendix C — Baseline Gates (T003, 2026-10-09T04:45Z)

| Gate | Result | Note |
|---|---|---|
| `make test-static` | ✅ PASS | New unified deterministic gate (T004): 22 static shell tests + `validate-pattern-config.sh`, sorted order; surfaced 7 previously unwired scripts (bootstrap, cluster-summary, default-storage-class, lvms-ordering, make-ordering, pattern-wrapper, vault-storage-override) — all pass |
| `./pattern.sh make validate-schema` | ✅ PASS | "All assertions passed" for values-global.yaml + values-prod.yaml against clustergroup schema |
| `make validate-origin` / `validate-prereq` (host) | ⚠️ N/A | `rhvp.cluster_utils` ansible collection not installed on host; runs only inside `./pattern.sh` container |
| `./pattern.sh make validate-origin` | ⏸️ BLOCKED (expected) | Branch `010-reduce-cpu-usage` has no upstream yet; resolves at first push (T016) — mid-feature, not a defect |
| `./pattern.sh make validate-prereq` | ⏸️ BLOCKED (expected) | Same upstream-tracking dependency |

**T004 note**: repo has no `lint-yaml`/`generate`/`super-linter` make targets (plan anticipated generic targets); the actual validation surface is `test-static` + containerized `validate-schema`. `make generate`-equivalent coverage is handled per-story via helm-render tests.

## Appendix D — Post-Repair Evidence (T009–T011, 2026-10-09)

**Repair run** (`scripts/repair-agent-sandbox-leak.sh` @ 04:43:40Z — full log: `$TMPDIR/minilab-metrics/t009-repair.log`):

| Step | Result | Evidence |
|---|---|---|
| Preconditions 1–4 | ✅ all pass | app located in `vp-gitops` (auto-detected), absent from Git, 0 sandbox CRs, CSV present |
| Action | ✅ | `oc delete application agent-sandbox -n vp-gitops` returned in 4s (04:43:44) — foreground finalizer cascaded the 4 tracked objects |
| P5.1 app gone | ✅ | NotFound after delete |
| P5.2 OLM-owned Deployment | ✅ | recreated same second, `managed-by` unset, no ArgoCD tracking annotations |
| P5.3 CSV Succeeded | ✅ | 04:45:16 (~92s of final OLM retries) — last event `InstallSucceeded: install strategy completed with no errors` |
| P5.4 quiet window | ✅ | zero `InstallComponentFailed` since 04:38:47 (last pre-repair failure) |
| P5.5 CSV PUT rate < 0.1/s | ⚠️ **deviation, accepted** — see below | residual 12.9–18.2/s no-op PUTs |

**P5.5 deviation analysis** (contract threshold assumed the install loop was the only CSV writer):
- **Zero CSV object churn**: 30s resourceVersion diff across ALL CSVs cluster-wide = 0 changes. The residual PUTs are identical-content full-object updates (OLM copied-CSV resync behavior — every namespace carries a copied CSV; OLM's copy sync worker round-robins them with no-op PUTs).
- **CPU attribution is unambiguous**: olm-operator 1345m → 224m (−83%), kube-apiserver 2706m → ~2300m falling, ArgoCD app-controller 835m → 129m, **node 7848m/104% → 5183m/69%** within 10 minutes of the delete.
- The residual no-op fan is a separate, pre-existing inefficiency → tracked as a US4 follow-up lever (`OLMConfig/spec.features.csvCopyLoopInterval` or `disableCopiedCSVs`), not a repair failure.

**Functional smoke test (FR-002 / US1 AC5, 04:53:31Z)**:
- Sandbox CR `feature010-smoke` (ubi-micro, 10m/32Mi request) applied to `openshell` namespace.
- Controller reached `Ready=True (DependenciesReady) "Pod is Ready; Service Exists"` **in 21s**; pod 1/1 Running on `sno`; per-sandbox Service `feature010-smoke.openshell.svc.cluster.local` spawned.
- Controller logs: zero error/fail lines; CSV stayed `Succeeded`; sandbox deleted cleanly (final state: 0 Sandbox CRs cluster-wide).
- Terminal-side `openshell` gateway auth is stale on this workstation (invalid_grant + missing mTLS CA) — the `run-demo.sh --smoke` full path remains available via `make validate-openshell-demo` once re-login lands; the CR-level smoke above is the authoritative FR-002 signal and does not depend on local gateway auth.

**Owner-collision regression check**: `tests/test-owner-collision.sh` now ✅ green ("no GitOps/OLM deployment ownership conflicts") — was red pre-repair, exactly one collision.

## Appendix E — G1 Acceptance (T010, capture 2026-10-09T05:15:16Z, t+30m post-Succeeded)

| Signal | Result |
|---|---|
| CSV phase | `Succeeded`, `lastTransition=04:45:10Z` — stable through full soak |
| New `InstallComponentFailed` post-04:45:16Z | **0** |
| CSV PUT (5m) | 11.5/s → residual OLM copied-CSV no-op fan (Appendix D deviation; zero object churn verified) |
| Owner-collision gate | green continuously since 04:52Z |
| Node CPU (3 samples, 60s apart) | 2995m/39%, 6277m/83% (apiserver burst 3099m), 2185m/29% — mean ≈50% vs 102% baseline |
| Key pods @05:15–05:17 | apiserver 1921/3099/470m (bursty, decaying), olm-operator 130m (was 1345m), argocd-ctrl 204→89m (was 835m), prometheus-k8s-0 166–182m, insights-runtime-extractor 1–2m (was 1505m) |

**Verdict: G1 PASS** — AC1–AC5 of US1 met. Attribution: single delete of the leaked
Application recovered ≈50% of node CPU within 30 minutes. The 05:16 apiserver
burst is standalone control-plane activity (no OLM/ArgoCD correlate) and
decayed within 60s — not a regression. Continuous 2-min sampler running for the
rest of the day (monitor.log).

## Appendix F — Ancillary Pre-Findings (read-only, for T024 review)

**Unseal cronjob (`imperative/unsealvault-cronjob`)** — spec assumption "0/168h" is wrong:
- Schedule is **`*/5 * * * *`** — 288 runs/day, each ~55s including a `quay.io/validatedpatterns/imperative-container:v1` pull (667 MB image; layers usually cached).
- The 7 CrashLoopBackOff/Error `unsealvault-cronjob-29832540-*` pods are **stale corpses from 2026-09-21** (Init:Error, `finishedAt` 2026-09-21T01:00:33Z) — failed jobs' pods never got garbage-collected. Recent jobs (29858765/70/75) all Complete; vault-0 is Running 1/1.
- Levers for T024: (a) reduce schedule to hourly/daily (unseal is a recovery aid, not a heartbeat); (b) set `failedJobsHistoryLimit`/`successfulJobsHistoryLimit` plus `ttlSecondsAfterFinished` to auto-clean; (c) delete the 7 stale failed pods + 3 old static-pod installer Error pods (`installer-12-sno`, `installer-1-sno`, `installer-3-sno`, all old revisions).
- CPU impact estimate: modest (job churn + image-pull I/O), but the failures inflate health-signal noise and the earlier "10 crashlooping pods" reading.

**OLM residual no-op CSV PUT fan** (~11–18/s, Appendix D): candidate levers `OLMConfig/cluster spec.features.csvCopyLoopInterval` (default ~15s → e.g. 4h) or `disableCopiedCSVs` (needs OLM 4.20+ verification — OCP 4.22 ships it as TechPreview? confirm before toggling). Validate against docs during T024 — do not flip features blind.

## Appendix G — G2 Acceptance (T015, 2026-10-09)

**Chain verification (06:18Z)**: `patterns-operator-config` CM → ArgoCD CR `.spec.extraConfig` →
runtime `argocd-cm` all carry `timeout.reconciliation: 600s`; controller restarted 06:18:48Z
(pod would not have reloaded the key otherwise — no auto-restart by GitOps operator).

**Cadence spacing proof (06:44:36Z)**: all 15 Applications show `reconciledAt` ages of
402–456s — no mid-cycle full reconciliation between 600s cycles (first cycle at
restart+600s ≈ 06:28:48 matches restart 06:18:48). G2 PASS on cadence enforcement.

**CPU step-down**: app-controller 154→114→99m (samples 06:31Z) vs 835m pre-repair baseline
and ~204m post-US1 — sustained decline; final attribution recorded at G6 window.

**Pattern tracking correction (06:37Z)**: `operator-deploy` from a non-main checkout had
re-pointed `gitSpec.targetRevision` to `010-reduce-cpu-usage`; pinned `main.git.{repoURL,
revision}` in `values-global.yaml` (commit aa1a88e) and re-ran from main — Pattern CR now
tracks `main` permanently. New Application `openshift-monitoring-config` observed live
(US3 rollout via GitOps from main, per user directive that ArgoCD runs against main).

## Appendix H — G5 Acceptance (T022, 2026-10-09T06:50Z)

| Check | Result |
|---|---|
| Platform alert pipeline | ✅ Watchdog firing (always-on test alert reaches Alertmanager); +HIGH-4 others incl. UpdateAvailable |
| Platform AM receivers | ⚠️ **pre-existing**: default CMO AM has placeholder receivers only (`AlertmanagerReceiversNotConfigured` firing) — no real integration ever existed; unchanged by feature 010; recommend wiring platform AM → PagerDuty as a follow-up (documented gap, recorded per FR-008 fallback) |
| COO minilab Alertmanager (PagerDuty via ESO/vault) | ✅ `alertmanager-minilab-0` 2/2, `prometheus-minilab-0` 3/3, 7d11h uptime; secret chain healthy (ESO synced) |
| node-exporter freshness | ✅ 12.2s staleness (< 30s bound; CMO kept factory scrape cadence for retained targets, confirming the monitoring-config contract's continuation guarantee) |
| Core series after `minimal` profile | ✅ `node_cpu_seconds_total` 64 series, `node_memory_*`, `node_filesystem_*`, `kube_pod_info` 212 — dashboard inputs intact |
| Dashboard rendering | ✅ 6 PersesDashboard CRs present; `perses-0` + `perses-operator` Running; monitoring-plugin Running; UIPlugin `Reconciled=True` |
| `KubeJobFailed` firing | ⚠️ caused by the **stale Sept job corpses** identified in Appendix F — resolved by T024 cleanup |

**Verdict: G5 PASS** (two noted items are pre-existing/orphan-cleanup matters, not regressions from tuning).

