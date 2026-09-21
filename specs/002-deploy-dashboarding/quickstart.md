# Quickstart: Validate Deploy Dashboarding Tools

## Prerequisites

- A supported connected single-node OpenShift 4.22 lab and an authenticated `oc` context.
- Pattern installed with the LVMS storage class available (see `specs/001-bootstrap-local-storage`).
- Pattern vault/external-secrets configured and the PagerDuty routing key loaded into vault (never in Git).
- External Prometheus exporters reachable over HTTP/HTTPS from the cluster, with endpoints declared in `global.observability.externalTargets`.

## Default Validation

1. Add COO subscription and the `observability-config` application to the cluster values; declare the PagerDuty key in `values-secret.yaml.template`.
2. Run `./pattern.sh make install`.
3. Run `./pattern.sh make validate-schema` and `./pattern.sh make argo-healthcheck`.
4. Confirm COO, the Perses Operator, and the `UIPlugin` are reconciled and Available.
5. Open the OpenShift console `Observe > Dashboards (Perses)`; confirm the dashboard list loads under cluster OAuth.
6. Confirm dashboards for all three domains are present and populated:
   - OCP system workloads (nodes, cluster capacity) via the platform Thanos Querier datasource.
   - Application workloads (namespaces/workloads) via the user-workload or stack datasource.
   - External components via the COO stack datasource scraping the declared exporter endpoints.
7. Confirm a viewer user without a binding sees no dashboards and an authorized user sees the managed dashboards (SC-006).
8. Drive one metric per domain over a configured threshold; confirm the alert fires, appears in the dashboarding platform, resolves when the condition clears, and is delivered to PagerDuty (SC-002/003/004).

## Configurable Datasource and Dashboard Validation

1. Add a new external exporter endpoint via `global.observability.externalTargets`; reconcile and confirm its metrics appear in the external-components dashboard.
2. Add a new `PersesDashboard` definition to `charts/observability-config/templates/`; commit and reconcile; confirm it appears in the console without manual cluster-side action (SC-005).
3. Add a new `PrometheusRule`; confirm it is selected by the stack and testable.

## Failure and Recovery Validation

1. Point an external target at an unreachable endpoint; confirm only that target loses data while system/application dashboards keep working (edge case).
2. Temporarily use an invalid PagerDuty routing key or an unreachable PagerDuty endpoint; confirm alert state remains visible in the dashboarding platform and delivery retries.
3. Apply an intentionally invalid `PersesDashboard`; confirm an actionable validation error and that existing dashboards remain reconciled (FR-014).
4. Restart the SNO node; confirm dashboards, datasources, alert rules, and retained metrics are restored (FR-011/011a).

For design fields and state transitions, see [data-model.md](data-model.md). For configuration interfaces, see [observability-config.md](contracts/observability-config.md). For dashboard-as-code authoring and RBAC, see [perses-dashboards.md](contracts/perses-dashboards.md).

## Target-Cluster Results

Unchecked: target-cluster validation has not been run from this workspace. Offline validation (render, lint, and shell tests) passes via `make validate-observability`. Before marking this feature complete, run the validations above against the target cluster and record the target OpenShift release, COO catalog channel/CSV, exact CRD API versions, generated Prometheus/Alertmanager/Thanos service names, the platform Thanos Querier datasource URL used, Perses project/namespace mapping, and the results of every validation above.