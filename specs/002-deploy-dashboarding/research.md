# Research: Deploy Dashboarding Tools

## Decision: Use the Cluster Observability Operator with the Red Hat build of Perses

**Rationale**: The user directed this implementation to use the Cluster Observability Operator (COO) together with Perses, with Perses dashboards managed as code in the same repository as the validated pattern. COO is an OpenShift meta-operator that installs and manages standalone monitoring stacks (Prometheus, Alertmanager, Thanos Querier) and the observability UI plugins. COO 1.4 introduced Red Hat build of Perses as a technology preview; COO 1.5 made it generally available on OpenShift 4.15+. This lab targets OpenShift 4.22, so the GA Perses path is available.

Perses provides:
- Dashboard management directly in the OpenShift console under `Observe > Dashboards (Perses)` — this is the single cluster-route/OAuth-protected access point the spec requires, without a separate application or its own auth.
- Dashboards, datasources, and global datasources as namespaced/cluster-scoped Kubernetes resources (`PersesDashboard`, `PersesDatasource`, `PersesGlobalDatasource`) — enabling Dashboards-as-Code via GitOps, exactly as the user requested.
- Native Kubernetes RBAC via the operator-deployed ClusterRoles (`persesdashboard-viewer-role`, `persesdashboard-editor-role`, `persesdatasource-viewer-role`, `persesdatasource-editor-role`, `persesglobaldatasource-viewer-role`, `persesglobaldatasource-editor-role`), which satisfies the cluster-OAuth/RBAC access-control requirement.
- Datasource plugins for Prometheus, Thanos, Loki, and Tempo; panel plugins for time series, stat, gauge, markdown; PromQL queries — sufficient for all three monitoring domains (system, application, external).

**Alternatives considered**:

- Grafana as a standalone chart: rejected because the user explicitly directed COO + Perses and because a separate Grafana instance would need its own access point, OAuth wiring, and persistence rather than reusing the console.
- OpenShift's built-in (CMO) monitoring alone: cannot scrape external components and provides no user-managed dashboarding-as-code; rejected.
- A second full platform-monitoring stack via COO for system workloads: rejected as redundant — the existing in-cluster Thanos Querier already holds platform and user-workload metrics, so Perses datasources point at it.

## Decision: Enable Perses through the monitoring `UIPlugin`

**Rationale**: The COO installs the Perses Operator and its CRDs automatically with the subscription. The `UIPlugin` custom resource with `spec.type: monitoring` and `spec.monitoring.perses.enabled: true` is what installs the Perses UI plugin and creates the Perses server instance, adding the `Observe > Dashboards (Perses)` menu to the console. Without the plugin, the CRDs exist but no Perses server is deployed.

```yaml
apiVersion: monitoring.rhobs/v1alpha2
kind: UIPlugin
metadata:
  name: monitoring
spec:
  type: monitoring
  monitoring:
    perses:
      enabled: true
```

Namespaces map to Perses projects; a `PersesDashboard` or `PersesDatasource` created in a namespace is synchronized into the corresponding Perses project across Perses servers, which provides namespace-scoped RBAC.

**Alternatives considered**:

- Deploying a standalone Perses server via the Perses Operator CR directly: rejected because COO's `UIPlugin` is the supported, integrated path that wires Perses into the console.
- Dashboarding without Perses in the console: rejected; the console integration is the intended single access point.

## Decision: One lightweight `MonitoringStack` for external-component metrics and alerting

**Rationale**: External components expose Prometheus-style exporters over HTTP/HTTPS that are outside the cluster's platform monitoring. A COO `MonitoringStack` provides Prometheus (single replica for the SNO budget), optional Thanos Querier, and Alertmanager. Its `namespaceSelector`/`resourceSelector` selects the `ServiceMonitor`/`ScrapeConfig`/`PrometheusRule` resources that describe external endpoints and their alert rules. Retention is set to `30d` on the stack to satisfy the spec's 30-day retention requirement. `ScrapeConfig` (monitoring.coreos.com/v1alpha1) supports static targets for external hosts, which is the mechanism for external HTTP/HTTPS exporters; `ServiceMonitor` covers in-cluster application workloads.

For OCP system and application workload dashboards, a `PersesGlobalDatasource` (or namespaced `PersesDatasource`) points at the in-cluster Thanos Querier (`openshift-monitoring`) so platform and user-workload metrics are visualized without a second stack. A separate datasource points at the COO stack's Prometheus/Thanos for external metrics.

**Alternatives considered**:

- Adding external scrape targets to the platform stack via CMO configuration: rejected — CMO configuration is centralized, not GitOps-application-owned, and mixing external scraping into platform monitoring is not the supported extension path.
- A separate Prometheus chart outside COO: rejected — duplicates operator-managed lifecycle management COO already provides and adds a second Prometheus to a single-node budget.

## Decision: Alerting to PagerDuty via COO Alertmanager

**Rationale**: The COO `MonitoringStack` deploys Alertmanager. Alerts are defined as `PrometheusRule` resources selected by the stack's `resourceSelector`. Alertmanager routing and receivers are declared through the operator-native config Secret (`alertmanager-<stack>` with an `alertmanager.yaml` key), because the COO `MonitoringStack.spec.alertmanagerConfig` only exposes `disabled` and `webTLSConfig` — it does not expose an `AlertmanagerConfig` selector. That Secret is rendered by the ExternalSecret, which templates the PagerDuty routing key from Vault (constitution: no committed secrets). A default route sends all stack alerts to PagerDuty; `send_resolved` is enabled so alert resolution is also delivered (FR-010 auto-resolve).

Alert-state recording: Alertmanager retains the firing/resolved state and the Perses dashboard views expose it; even if PagerDuty is unreachable the alert state remains visible (FR-009). Grouping (`group_by: [alertname, namespace]`), group-wait, and repeat intervals are set to reasonable defaults, with inhibition of `warning`/`info` while a `critical` is firing for the same alertname to avoid flood noise (edge case: alert floods).

**Alternatives considered**:

- Configuring the platform `alertmanager-main` secret in `openshift-monitoring` for PagerDuty: rejected for system alerts in v1 because it is a CMO-managed secret override (imperative, contrary to GitOps-First); noted as a follow-up for platform-alert routing. See Complexity Tracking in plan.md.
- A webhook-based shim instead of native PagerDuty: rejected — native `pagerduty_configs` is the direct, supported integration.

## Decision: Dashboards as code in this repository

**Rationale**: The user explicitly required Perses dashboards to be managed as code in the same repository as the validated pattern. `PersesDashboard` resources are versioned YAML in `charts/observability-config/templates/`, one per domain (OCP system, application, external), so they are reviewed, versioned, and reconciled by Argo CD exactly like every other GitOps resource. Dashboard content uses the Perses schema (`perses.dev/v1alpha2`): display metadata, optional variables, `TimeSeriesChart`/`StatChart` panels, and `PrometheusTimeSeriesQuery` queries referencing the appropriate datasource. This satisfies FR-006/FR-013 and the Dashboards-as-Code requirement.

**Alternatives considered**:

- Authoring dashboards only in the console UI: rejected — not Git-declared, not reproducible, creates drift (violates GitOps-First).
- Storing dashboards in a separate repository: rejected — the user asked for the same repo as the validated pattern.

## Decision: RBAC via Perses ClusterRoles bound to OpenShift groups

**Rationale**: COO deploys Perses ClusterRoles. Bindings choose which OpenShift users/groups can view (`persesdashboard-viewer-role`, `persesdatasource-viewer-role`) and manage (`persesdashboard-editor-role`, `persesdatasource-editor-role`) dashboards and datasources. `RoleBinding` grants namespace-scoped access (Perses project); `ClusterRoleBinding` grants cluster-wide access. The pattern declares viewer bindings for lab operators and editor bindings for admins, integrated with OpenShift's built-in OAuth identity, satisfying FR-012/SC-006 with no separate identity provider. A `PersesGlobalDatasource` is cluster-scoped; its access is governed by the globaldatasource roles.

**Alternatives considered**:

- Perses-native (Perses Roles/RoleBindings) separate from OpenShift RBAC: rejected — COO integrates Perses with OpenShift RBAC; native Perses roles add a second permission model.

## Decision: Persist stack metrics and alert state on the pattern storage class

**Rationale**: The COO `MonitoringStack` Prometheus requires persistent storage for its time-series database to satisfy the 30-day retention and the across-restart persistence requirement (FR-011/FR-011a). The stack's PVCs use the pattern's `lvms-loopback` storage class via a values override, reusing existing local storage (assumption: reuses pattern storage). Alertmanager nflog/silences use an `emptyDir` or small PVC depending on the stack configuration; dashboard definitions themselves live in CRs and are recreated by Argo CD.

**Alternatives considered**:

- No persistence (ephemeral metrics): rejected — loses history on restart, violates FR-011a.
- A separate object-store backed remote-write: rejected — disproportionate for a single-node lab.

## Implementation Verification Required

- Confirm the exact COO catalog channel and CSV available for OpenShift 4.22 on the target `redhat-operators` catalog (research used `stable`; assert against the target).
- Confirm the exact `UIPlugin`, `MonitoringStack`, and Perses CRD API versions accepted by the target COO release (research used `monitoring.rhobs/v1alpha2`, `monitoring.rhobs/v1alpha1`, `perses.dev/v1alpha2`).
- Confirm the `ScrapeConfig` CRD version and that the COO stack's `resourceSelector` selects it for external static targets.
- Confirm the generated names for COO stack Prometheus/Alertmanager services and the in-cluster Thanos Querier endpoint for datasource URLs.
- Confirm the generated name of the COO Alertmanager (so the `alertmanager-<stack>` config Secret name matches) and that the stack's Prometheus is wired to it.
- Confirm `PersesGlobalDatasource` vs namespaced `PersesDatasource` behavior on the target release for cross-project (system + app) dashboards.
- Confirm the exact default `PersesDatasource`/datasource URL values COO provides for the platform Thanos Querier.
- Confirm OpenShift 4.22 console `Observe > Dashboards (Perses)` availability once the `UIPlugin` is reconciled.