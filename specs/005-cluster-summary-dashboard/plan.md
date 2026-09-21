# Implementation Plan: Cluster Summary Dashboard

**Branch**: `005-cluster-summary-dashboard` | **Date**: 2026-09-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-cluster-summary-dashboard/spec.md`

## Summary

Add a Perses dashboard managed in `charts/observability-config` that summarizes the single-node OpenShift lab: explicit SNO context, node readiness, cluster operator health, CPU/memory capacity, and LVMS disk/thin-pool utilization. Enable the existing LVMS-generated ServiceMonitor for platform monitoring by adding the documented `openshift.io/cluster-monitoring: "true"` label to `openshift-storage`; the dashboard reads these metrics through the existing platform Thanos global datasource. No duplicate COO scrape target is added.

## Technical Context

**Language/Version**: YAML, Helm, PromQL, and shell; versions supplied by the Validated Patterns utility container and OpenShift 4.22.

**Primary Dependencies**: Cluster Observability Operator + Perses, platform Thanos Querier, LVM Storage Operator's existing `lvms-operator-metrics-monitor` ServiceMonitor, and the cluster monitoring namespace-label discovery mechanism.

**Storage**: N/A — dashboard and monitoring configuration only.

**Testing**: Helm render tests; shell assertions for namespace label, dashboard panels and datasource; target-cluster query checks for LVMS metrics and dashboard availability.

**Target Platform**: Connected single-node OpenShift 4.22 lab with LVMS (`lvms-loopback`).

**Project Type**: Validated Pattern repository (GitOps configuration).

**Performance Goals**: Dashboard shows current cluster and LVMS state using standard scrape/evaluation intervals; no new runtime components are deployed.

**Constraints**: Git-declared and Argo CD reconciled; Helm only; reuse existing platform monitoring and LVMS ServiceMonitor; no manual scrape configuration or credentials; must fit the SNO resource budget.

**Scale/Scope**: One namespace label, one PersesDashboard, and render/target-cluster validation. LVMS metric names are discovered from the existing LVMS metrics service after platform monitoring begins scraping it.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Plan response | Status |
|-----------|---------------|--------|
| GitOps-First | Namespace label and dashboard are versioned Helm/values configuration reconciled by Argo CD. | Pass |
| Imperative Only Second | No imperative action is needed; use the existing LVMS ServiceMonitor declaratively. | Pass |
| Helm Only, No Kustomize | Values and chart templates only. | Pass |
| Simplicity First | Reuse platform monitoring's LVMS ServiceMonitor and existing Thanos datasource; no duplicate ServiceMonitor, Prometheus, or metrics proxy. | Pass |

**Post-design re-check**: Pass. The design adds only the configuration needed to expose existing LVMS metrics and a single dashboard resource; no new runtime component, secret, or imperative path.

## Project Structure

### Documentation (this feature)

```text
specs/005-cluster-summary-dashboard/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/cluster-summary-dashboard.md
└── tasks.md                 # Created by /speckit.tasks
```

### Source Code (repository root)

```text
values-prod.yaml                                      # Add platform-monitoring namespace label to openshift-storage
charts/observability-config/templates/
└── perses-dashboards.yaml                            # Add single-node cluster summary PersesDashboard
tests/test-cluster-summary-dashboard.sh               # NEW: render + datasource/panel assertions
README.md                                             # Document cluster summary dashboard and LVMS metric prerequisite
```

**Structure Decision**: Add the summary dashboard beside the existing static Perses dashboards in `perses-dashboards.yaml`. Set the documented platform-monitoring label on the existing `openshift-storage` namespace through the cluster-group values map. The existing LVMS ServiceMonitor performs the authenticated scrape; Perses queries its metrics through the existing global platform Thanos datasource.

## Complexity Tracking

No constitution violations. No exceptions required.
