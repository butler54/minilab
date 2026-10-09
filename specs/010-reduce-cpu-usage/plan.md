# Implementation Plan: Reduce Minilab CPU Usage

**Branch**: `010-reduce-cpu-usage` | **Date**: 2026-10-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-reduce-cpu-usage/spec.md`, plus root-cause evidence in [ANALYSIS.md](./ANALYSIS.md) and user direction: *"Implement fixes for agent sandbox aligned with best practices for a validated pattern. Ensure to iteratively test as part of the plan. Adjust ArgoCD to every 600s and 60s for cluster monitoring config. Once implemented monitor and incrementally adjust from there."*

## Summary

Break the OLM↔ArgoCD reconciliation war on `agent-sandbox-controller` by removing the **leaked ArgoCD Application** (`agent-sandbox`, no longer in Git since commit `e750ac1`, but never pruned because the app-of-apps `minilab-prod` has `prune: false`) via a recorded, idempotent imperative repair — Git state is already correct, the cluster simply never converged. Then deliver cadence tuning through **officially supported seams**: ArgoCD reconciliation 600s via the patterns-operator `gitops.customArgoYaml` overlay, and platform monitoring CPU reduction via the Cluster Monitoring Operator's `prometheusK8s.collectionProfile: minimal` (OCP 4.22's CMO exposes **no** platform scrape-interval knob) plus 60s intervals on pattern-owned scrape configs. Validation is staged and iterative with live-cluster gates at every step, followed by a monitoring loop that allocates further reductions only if targets are unmet.

## Technical Context

**Language/Version**: YAML / Helm (clustergroup chart `0.9.*`), POSIX shell + Python 3 (test suites)

**Primary Dependencies**: OpenShift 4.22.13 (K8s 1.35.6) SNO, 8 CPU · Validated Patterns `patterns-operator` + `pattern-install` chart 0.0.18 (`main.gitops.customArgoYaml`) · openshift-gitops operator 1.21 (ArgoCD CR `vp-gitops`, `extraConfig`) · OLM (`agent-sandbox-operator.v0.9.0`, channel `preview-0.9`) · Cluster Monitoring Operator (`cluster-monitoring-config` → `PrometheusK8sConfig`) · Cluster Observability Operator MonitoringStack (`minilab`)

**Storage**: N/A (configuration-only changes; monitoring keeps existing PVs)

**Testing**: static suites `tests/*.sh` (python-driven) + live probes from `ANALYSIS.md` (`oc adm top`, prometheus `apiserver_request_total` rates) + pattern gates `make validate-schema` / `make validate-cluster` / `make argo-healthcheck`

**Target Platform**: Single-node OpenShift `sno` (control-plane + worker, 8 CPU, appliance-capped)

**Project Type**: Validated Patterns GitOps repository (values files + local Helm charts)

**Performance Goals**: sustained node CPU < 70% (from 102%); kube-apiserver < ~1.1 cores (from 2.27–2.71); total idle CPU −30%; CSV PUT rate < 1/min (from 23.4/s)

**Constraints**: GitOps-first — no permanent out-of-band mutation (Principle I); imperative steps must be automated, idempotent, Git-recorded, and reconciled (Principle II); Helm-only (Principle III); changes must fit the single-node budget (Principle IV); operator-managed CRs must be configured only through their owner operator's supported overlay mechanisms.

**Scale/Scope**: 4 change units — (1) agent-sandbox ownership repair, (2) ArgoCD 600s cadence, (3) monitoring profile + scrape cadence, (4) iterative monitor-and-adjust loop; ~6 repo files touched/added; 1 imperative repair script.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. GitOps-First | PASS (one sanctioned exception) | All persistent config lands in Git (`values-global.yaml`, new chart, values-prod). The one imperatively-run operation is the **repair script** + re-run of `make operator-deploy` — see Principle II row. No permanent out-of-band resource. |
| II. Imperative Only Second | PASS with recorded exception | Breakage was caused *by* a missing prune (Git is ahead of the cluster). The repair is: scripted (`scripts/repair-agent-sandbox-leak.sh`), idempotent (no-op when leak absent), Git-recorded before execution (`docs/agent-sandbox-repair.md`), result reconciled back under GitOps (ArgoCD converges to Git, which already omits the app). The bootstrap tool (`make operator-deploy`) is the framework's own idempotent path for `pattern-install` values — the explicitly-sanctioned bootstrap escape hatch. |
| III. Helm Only, No Kustomize | PASS | New manifest is a local Helm chart (`charts/openshift-monitoring-config`) added as clustergroup `applications` entry. |
| IV. Simplicity First | PASS | Rejected heavier alternatives: User Workload Monitoring (whole extra stack), per-resource ServiceMonitors for platform (CMO-managed, unsupported), deleting & reinstalling operator subscriptions (bigger blast radius than deleting 4 leaked resources). `collectionProfile: minimal` is one line. |

Re-evaluated after Phase 1 design: unchanged — design introduces no new imperative or heavyweight components beyond the sanctioned repair script.

## Project Structure

### Documentation (this feature)

```text
specs/010-reduce-cpu-usage/
├── plan.md              # This file
├── research.md          # Phase 0: delivery-path findings (prune leak, customArgoYaml, CMO limits)
├── data-model.md        # Phase 1: configuration entities & state transitions
├── contracts/           # Phase 1: cadence + monitoring config contracts, repair runbook contract
├── quickstart.md        # Phase 1: staged live-cluster validation gates (G0–G6)
├── ANALYSIS.md          # Root-cause evidence; post-change evidence appended in place
├── spec.md
└── checklists/requirements.md
```

### Source Code (repository root)

```text
values-global.yaml                       # EDIT: main.gitops.customArgoYaml (timeout.reconciliation: 600s)
values-prod.yaml                         # EDIT: add application entry openshift-monitoring-config
overrides/values-observability.yaml      # EDIT: global.observability.scrapeInterval: 60s (external targets)
charts/
├── openshift-monitoring-config/         # NEW local chart: cluster-monitoring-config ConfigMap
│   ├── Chart.yaml
│   ├── values.yaml                      # stubs global.* for standalone helm template
│   ├── values.schema.json
│   └── templates/configmap.yaml         # namespace openshift-monitoring, from values
scripts/
└── repair-agent-sandbox-leak.sh         # NEW idempotent, Git-recorded repair (Principle II)
docs/
└── agent-sandbox-repair.md              # rationale + runbook for the repair
tests/
├── test-argocd-cadence.sh               # NEW: values contract proofs for 600s knob (suite-local)
├── test-monitoring-config.sh            # NEW: rendered CM equals contract (collectionProfile: minimal)
└── (existing suites unchanged — no upstream chart returns, no vendoring)
```

**Structure Decision**: Follows existing repo pattern (local charts under `charts/`, application wiring in `values-prod.yaml`, config surface in `values-global.yaml`/`overrides/`, evidence in the feature directory). The repair script follows the same Git-recorded pattern used for bootstrap (`scripts/bootstrap-storage` precedent), not the imperative-namespace jobs — it is designed to become a no-op once run.

## Complexity Tracking

> No unjustified principles violations. The single Principle-II exception (repair script) is recorded as the constitution prescribes and is contained in `docs/agent-sandbox-repair.md`.
