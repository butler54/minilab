# Quickstart Validation: Reduce Minilab CPU Usage

Staged, iterative validation. Every gate collects evidence and appends it to
`ANALYSIS.md`. No gate skips; each gates the next. Probes reuse the exact
commands/queries in [ANALYSIS.md](./ANALYSIS.md) §Evidence so numbers are
comparable to the baseline.

## G0 — Static checks (off-cluster, first)

```bash
make validate-schema          # values-global.yaml + values-prod.yaml stay schema-valid
./tests/test-argocd-cadence.sh        # 600s pin present (contracts/argocd-cadence-contract.md)
./tests/test-monitoring-config.sh     # chart renders contract CM (contracts/monitoring-config-contract.md)
./tests/test-external-refs.sh ./tests/test-openshell-render.sh ./tests/test-openshell-pins.sh
```

Expected: all pass. `helm template` of both new/modified charts succeeds
(chart `values.yaml` stubs rule).

## G1 — Repair agent-sandbox leak (biggest win, isolated measurement first)

1. `scripts/repair-agent-sandbox-leak.sh --dry-run` — prints the 4-resource
   delete set; aborts if any precondition in `contracts/repair-runbook-contract.md`
   fails.
2. `scripts/repair-agent-sandbox-leak.sh` — records post-repair probes into
   `ANALYSIS.md`.

Expected:
- `Application/agent-sandbox` gone; nothing else in `vp-gitops` changes.
- CSV `agent-sandbox-operator.v0.9.0` → `Succeeded` (≤ 10m).
- **Measure 30m**: `olm-operator` CPU < 100m; CSV PUT rate < 0.1/s → maps to SC-003/SC-004.

## G2 — Converge remaining Git drift

`minilab-prod selfHeal` finishes (or a single manual sync on the app-of-apps if
600s cadence hasn't landed yet): `minilab-prod` and `lvms-config` → `Synced`.
Verify no other resources disappeared besides the leak set.

Expected: no app reports sync status `Unknown` (SC-005 partial).

## G3 — ArgoCD cadence 600s

1. Commit `main.gitops.customArgoYaml` (see `contracts/argocd-cadence-contract.md`).
2. `make operator-deploy` (idempotent framework path) — ConfigMap
   `patterns-operator-config` gains `gitops.customArgoYaml`.
3. Watch ArgoCD CR `vp-gitops` gain `spec.extraConfig."timeout.reconciliation": "600s"`
   (patterns-operator merge, ~minutes); gitops operator updates argocd-cm.

Expected: `vp-gitops-application-controller-0` 30m CPU noticeably below
1029m-baseline; a deliberate values-only Git change propagates on a ≤600s
schedule; a manual `oc patch application … --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'`
refreshes on demand (fast-path, FR-005).

## G4 — Platform monitoring profile

1. Add app entry `openshift-monitoring-config` (values-prod) and the new chart;
   let ArgoCD reconcile (auto within 600s after G3, or manual refresh).
2. Confirm `cluster-monitoring-config` `data.config.yaml` == contract;
   `prometheus-k8s-0` restarts once.

Expected:
- Console Observe → Overview renders; default platform alert rules still listed
  (CMO contract for `collectionProfile: minimal`, see
  `contracts/monitoring-config-contract.md`).
- `prometheus-k8s-0` 30m CPU below 280m baseline ("measurably lower", SC-006);
  all panels in Perses dashboards still render (COO `minilab` stack untouched).

## G5 — Pattern-owned 60s scrape cadence

`overrides/values-observability.yaml` `global.observability.scrapeInterval: 60s`
reconciles into external-target ServiceMonitors of app `observability-config`.

Expected: ServiceMonitor endpoints `interval: 60s`; minilab stack still scrapes
targets (`up` series present when externalTargets configured).

## G6 — Steady-state soak + scoreboard (1h window)

Record side-by-side in `ANALYSIS.md`:

| Probe | Baseline | Post | SC target |
|-------|----------|------|-----------|
| node CPU (oc adm top) | 7652m / 102% | __ | < 70% (SC-001) |
| kube-apiserver | 2706m | __ | ≤ ~1080m (−60%, SC-002) |
| CSV PUT rate | 23.4/s | __ | < 1/min (SC-003) |
| olm-operator | 1458m | __ | < 100m (SC-004) |
| app `Unknown` statuses | 1 | 0 | 0 (SC-005) |
| prometheus-k8s-0 | 280m | __ | measurably lower (SC-006) |
| total idle CPU | (G6 baseline row) | __ | −30% (SC-007) |

## Incremental adjust loop (only if SC-001/SC-007 unmet after G6)

Delivered change-set size is intentionally minimal; run levers in order, 30m
measurement each, stop when SC met:

1. Unseal cronjob cadence `*/5 → */15` (notify: post-reboot unseal ≤ 30m).
2. Marketplace catalog poll intervals (OperatorHub `pollingInterval`/cron tuning).
3. `timeout.reconciliation: 600s → 1800s` re-run G3 mechanics only.
4. COO `minilab` stack resources/retention triage.

Each lever is its own commit with the same evidence-append discipline — no
batching, so attribution stays clean (FR-011).
