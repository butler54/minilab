# Implementation Plan: Deploy Dashboarding Tools

**Branch**: `002-deploy-dashboarding` | **Date**: 2026-09-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-deploy-dashboarding/spec.md`

## Summary

Provide unified dashboarding and alerting for OpenShift system workloads, application workloads, and external components on the single-node lab. The Cluster Observability Operator (COO) is installed as a `clusterGroup` subscription and deploys the Red Hat build of Perses (via the monitoring `UIPlugin`), a single lightweight `MonitoringStack` (Prometheus, Thanos Querier, Alertmanager) for external-component metrics, and the Perses RBAC roles. Perses dashboards and datasources are managed as code in this repository: `PersesDashboard`, `PersesDatasource`, and `PersesGlobalDatasource` resources are declared in a local Helm chart and reconciled by Argo CD. Dashboards surface in the OpenShift console under `Observe > Dashboards (Perses)` — the single access point protected by cluster OAuth. Alerts fire from the COO monitoring stack (external components and application workloads) and are delivered to PagerDuty through Alertmanager. OCP system- and application-workload dashboards query the existing in-cluster Thanos Querier so no second full platform-monitoring stack is deployed.

## Technical Context

**Language/Version**: YAML, Helm, and shell; versions supplied by the Validated Patterns utility container and OpenShift 4.22.

**Primary Dependencies**: Cluster Observability Operator (channel `stable`, namespace `openshift-cluster-observability-operator`), its `UIPlugin`, `MonitoringStack`, and Perses CRDs (`PersesDashboard`, `PersesDatasource`, `PersesGlobalDatasource`), the OpenShift console, in-cluster Thanos Querier, and the pattern's vault/external-secrets mechanism for the PagerDuty routing key.

**Storage**: Metrics and alert state from the COO `MonitoringStack` persist on the pattern's LVMS storage class; 30-day retention is configured on the stack. Perses itself stores dashboard/datasource definitions as CRs (no dedicated database).

**Testing**: Helm render tests; `oc`/kubectl CRD readiness checks; OpenShift console verification of Perses dashboards per domain; Alertmanager route tests driving a threshold breach per domain; PagerDuty delivery check; RBAC viewer/editor checks; failure-injection checks (stack unavailable, external target unreachable, invalid dashboard declaration).

**Target Platform**: Connected, supported single-node OpenShift 4.22 lab; COO requires OpenShift 4.15+.

**Project Type**: Validated Pattern repository with Helm/Argo CD GitOps configuration; no new application runtime beyond the operator-managed observability components.

**Performance Goals**: Dashboards usable for all three domains from one console entry point; a fired alert is recorded and delivered to PagerDuty within the alert evaluation interval; 30 days of metrics retained within the lab storage budget.

**Constraints**: Must remain within the single-node lab resource budget (one lightweight stack, single Prometheus replica, Alertmanager, no duplication of platform monitoring). All configuration is Git-declared and Argo CD-reconciled. The PagerDuty routing key must never appear in Git. Perses dashboards must be managed as code in this repository. OAuth/RBAC from OpenShift governs access.

**Scale/Scope**: One SNO cluster, one monitoring stack, one Perses instance, one PagerDuty service. Dashboards and alert rules are versioned definitions; the operator authors domain-specific thresholds.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Plan response | Status |
|-----------|---------------|--------|
| GitOps-First | The COO subscription, `UIPlugin`, `MonitoringStack`, `PersesDashboard`/`PersesDatasource`/`PersesGlobalDatasource` resources, alert rules, and RBAC bindings are all declared in Git and reconciled by Argo CD. Dashboards are managed as code in this repository. | Pass |
| Imperative Only Second | No imperative cluster mutation is required. The PagerDuty routing key is injected through the pattern's existing vault/external-secrets mechanism, never edited on-cluster. | Pass |
| Helm Only, No Kustomize | All declarative resources live in one local Helm chart and cluster values; no Kustomize artifacts are introduced. | Pass |
| Simplicity First | One COO subscription, one `MonitoringStack` (single Prometheus replica) used only for what the existing platform stack cannot cover (external-component scraping plus a PagerDuty-routed Alertmanager). System- and app-workload dashboards reuse the existing in-cluster Thanos Querier rather than duplicating platform monitoring. | Pass |

**Post-design re-check**: Pass. The design adds only the operator-managed observability stack required by the objective; it reuses existing monitoring, storage, secret, and authentication mechanisms and introduces no committed secret or unmanaged runtime resource.

## Project Structure

### Documentation (this feature)

```text
specs/002-deploy-dashboarding/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── observability-config.md
│   └── perses-dashboards.md
└── tasks.md                 # Created by /speckit.tasks
```

### Source Code (repository root)

```text
values-global.yaml                            # Global observability defaults (namespace, retention, exporter references)
values-prod.yaml                              # COO namespace, subscription, and observability-config application
charts/observability-config/                  # Local Helm chart: UIPlugin, MonitoringStack, Alertmanager
│   ├── Chart.yaml
│   ├── values.yaml                           # Stubs for all .Values.global.* / .Values.clusterGroup.* references
│   └── templates/
│       ├── uiplugin.yaml                     # Monitoring UIPlugin with perses.enabled: true
│       ├── monitoring-stack.yaml             # Prometheus + Thanos + Alertmanager, retention 30d
│       ├── perses-datasources.yaml           # Platform thanos-querier + stack Prometheus datasources
│       ├── perses-dashboards.yaml            # System / application / external dashboard templates
│       ├── prometheus-rules.yaml             # Alert rules per domain
│       ├── scrape-configs.yaml               # ServiceMonitor/ScrapeConfig for external exporters
│       ├── rbac.yaml                         # Perses viewer/editor role bindings to OpenShift groups
│       └── external-secret.yaml              # Alertmanager config Secret (PagerDuty routing key from vault)
overrides/                                    # Provider-selected values (external exporter endpoints)
values-secret.yaml.template                   # PagerDuty routing key definition (no real secret material)
tests/                                        # Render and validation coverage for observability config
```

**Structure Decision**: Follow the repository's established local-chart pattern (`charts/lvms-config`) and cluster values ownership. All observability configuration lives in one `charts/observability-config` chart wired through `clusterGroup.applications`, with provider-selected exporter endpoints expressed through the `sharedValueFiles` override model. Dashboards-as-code means the `PersesDashboard` resources are versioned YAML in this chart.

## Complexity Tracking

No constitution violations require an exception. One deliberate scope decision is tracked: OCP **system-workload alerting** is limited to targets the COO stack can scrape through its own `ServiceMonitor`/`ScrapeConfig` selection, because routing the platform's built-in alerts to PagerDuty requires overriding the CMO-managed `alertmanager-main` secret (imperative, counter to GitOps-First). Platform-level alert routing to PagerDuty is documented as a follow-up rather than implemented in v1.

**Post-implementation review (2026-09-21)**: Offline validation passes (`make validate-observability`, `helm lint`, `validate-pattern-config.sh`, all existing repo tests). The implementation adds the COO subscription, one `MonitoringStack` (with `resourceSelector` correctly at the top level of `spec`), Perses datasources/dashboards-as-code, PagerDuty-routed Alertmanager via the operator-native `alertmanager-<stack>` config Secret, and RBAC — all Git-declared with no committed secrets. Target-cluster verification of COO channel/CSV, CRD versions, and the generated Alertmanager name (so the config Secret name matches) remains outstanding per research.md.