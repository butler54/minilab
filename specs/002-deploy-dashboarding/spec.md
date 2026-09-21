# Feature Specification: Deploy Dashboarding Tools

**Feature Branch**: `002-deploy-dashboarding`

**Created**: 2026-09-21

**Status**: Draft

**Input**: User description: "I want to use the validated pattern to deploy dashboarding tools. The objective is to provide dashboarding and alerting for openshift system workloads, application workloads and external components."

## Clarifications

### Session 2026-09-21

- Q: How should operators authenticate to the dashboarding platform and its alert-management functions? -> A: Reuse the cluster's built-in OAuth/identity provider (OpenShift users and groups).
- Q: How should operators reach the dashboarding access point - inside the cluster network only, or through an externally reachable entry point? -> A: Cluster route, reachable within the lab network, protected by cluster OAuth.
- Q: How long should the dashboarding platform retain its time-series metrics history? -> A: 30 days.
- Q: Should PagerDuty be the only alert notification destination, or should there be a secondary fallback channel? -> A: PagerDuty only; no secondary channel in v1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unified Dashboarding for All Workload Domains (Priority: P1)

As a pattern operator, I can view dashboards that cover OpenShift system workloads, application workloads, and external components from a single place so that I can assess the health of the whole environment without switching between tools.

**Why this priority**: The core objective is consolidated visibility across the three monitoring domains; without it the feature delivers no value.

**Independent Test**: Deploy the pattern with dashboarding enabled and confirm that each of the three domains (OpenShift system workloads, application workloads, external components) has at least one populated dashboard reachable through a single access point.

**Acceptance Scenarios**:

1. **Given** the pattern is installed with dashboarding enabled, **When** an operator opens the dashboarding access point, **Then** they can reach a dashboard showing OpenShift system workload health (cluster, nodes, capacity).
2. **Given** the pattern is installed with dashboarding enabled, **When** an operator opens the dashboarding access point, **Then** they can reach a dashboard showing application workload health for namespaces and workloads on the cluster.
3. **Given** the pattern is installed with dashboarding enabled, **When** an operator opens the dashboarding access point, **Then** they can reach a dashboard showing health of configured external components.

---

### User Story 2 - Alerting Across All Workload Domains (Priority: P1)

As a pattern operator, I can receive alerts when OpenShift system workloads, application workloads, or external components breach configured thresholds so that I can react before user impact.

**Why this priority**: Alerting is an explicit objective; dashboards alone are insufficient for operational response on a single-node lab.

**Independent Test**: Configure a threshold on one metric per domain, drive the metric over the threshold, and confirm an alert fires and is delivered to the configured notification channel.

**Acceptance Scenarios**:

1. **Given** an alert threshold is configured for a metric, **When** the metric exceeds the threshold, **Then** an alert fires for the affected domain.
2. **Given** an alert has fired, **When** the condition clears, **Then** the alert resolves automatically.
3. **Given** alerts are configured, **When** an alert fires, **Then** the notification is delivered to the configured PagerDuty service.

---

### User Story 3 - Configurable Dashboards and Alerts (Priority: P2)

As a pattern operator, I can add data sources, dashboards, and alert rules through the pattern's configuration files so that the environment stays GitOps-declared and reproducible.

**Why this priority**: The pattern constitution requires all desired state to be declared in Git and reconciled; configurability is what keeps dashboards and alerts from becoming manual drift.

**Independent Test**: Add a new data source and a new dashboard definition through the pattern values, apply the change, and confirm the new dashboard appears without any manual cluster-side action.

**Acceptance Scenarios**:

1. **Given** a new data source is declared in the pattern configuration, **When** the pattern is reconciled, **Then** the data source becomes available to the dashboarding platform.
2. **Given** a new dashboard is declared in the pattern configuration, **When** the pattern is reconciled, **Then** the dashboard appears in the dashboarding access point.
3. **Given** a new alert rule is declared in the pattern configuration, **When** the pattern is reconciled, **Then** the alert rule is active and testable.

---

### User Story 4 - Controlled Access to Dashboards and Alerts (Priority: P2)

As a pattern operator, I can control who can view dashboards and who can manage alerts through cluster-backed identities so that dashboarding and alerting are not exposed to unauthorized users.

**Why this priority**: The dashboarding platform may expose sensitive cluster telemetry; access control is required to keep that data private.

**Independent Test**: Configure restricted access, then verify that an unauthenticated or unauthorized user cannot reach the dashboards or alter alert configuration.

**Acceptance Scenarios**:

1. **Given** access control is enabled, **When** an unauthenticated user attempts to open the dashboarding access point, **Then** access is denied.
2. **Given** access control is enabled, **When** an operator with the appropriate role manages alert rules, **Then** the change is accepted and reconciled.
3. **Given** access control is enabled, **When** a user without the appropriate role attempts to manage alert rules, **Then** the change is rejected.

---

### Edge Cases

- The dashboarding platform is unavailable or its persistent storage cannot be satisfied; existing cluster workloads must remain unaffected.
- A configured external component is unreachable or stops exposing metrics; dashboarding and alerting for other domains must continue to work.
- A notification channel is unreachable when an alert fires; the alert state must still be recorded and visible in the dashboarding platform.
- An operator declares a data source, dashboard, or alert rule that is invalid or references missing components; the change must fail validation with an actionable message and not break reconciliation of existing resources.
- Configuration changes overlap or conflict with defaults; the operator's explicit configuration must take precedence and the outcome must be deterministic.
- Alert floods (many alerts firing at once) must not overwhelm the notification channel or hide the underlying incident.
- Node or cluster restart of the single-node lab must not lose configured dashboards or alert rules.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The pattern MUST provide a dashboarding capability for OpenShift system workloads, application workloads, and external components, all reachable through a single cluster route protected by cluster OAuth within the lab network.
- **FR-002**: The pattern MUST include dashboards that report the health and capacity of OpenShift system workloads (cluster, nodes, storage, and system namespaces).
- **FR-003**: The pattern MUST include dashboards that report the health of application workloads deployed on the cluster.
- **FR-004**: The pattern MUST include dashboards that report the health of configured external components exposing metrics over HTTP/HTTPS (Prometheus-style exporters).
- **FR-005**: The pattern MUST allow operators to add data sources for external components exposing metrics over HTTP/HTTPS (Prometheus-style exporters) through pattern configuration.
- **FR-006**: The pattern MUST allow operators to add, modify, and remove dashboards through pattern configuration.
- **FR-007**: The pattern MUST provide alerting for OpenShift system workloads, application workloads, and external components based on configurable thresholds.
- **FR-008**: The pattern MUST allow operators to add, modify, and remove alert rules through pattern configuration.
- **FR-009**: The pattern MUST deliver alert notifications to PagerDuty (the sole destination) and MUST record alert state so it remains visible even if the channel is unreachable.
- **FR-010**: The pattern MUST resolve fired alerts automatically when the underlying condition clears.
- **FR-011**: The pattern MUST persist dashboard configuration and alert rules across node restarts.
- **FR-011a**: The pattern MUST retain 30 days of time-series metrics history for dashboards and alerts.
- **FR-012**: The pattern MUST enforce access control using the cluster's built-in OAuth/identity provider (OpenShift users and groups) so that unauthorized users cannot view dashboards or manage alert configuration.
- **FR-013**: All dashboarding, alerting, and data-source configuration MUST be declared in Git and reconciled by the pattern's GitOps mechanism; no manual cluster-side configuration is required for the supported flows.
- **FR-014**: Invalid data-source, dashboard, or alert-rule declarations MUST fail validation with an actionable message and MUST NOT prevent reconciliation of existing valid resources.
- **FR-015**: The pattern MUST document the dashboarding scope, configuration surface, supported external-component types, alerting configuration, access control, and verification steps.
- **FR-016**: The dashboarding capability MUST fit within the resource budget of the pattern's supported single-node cluster and MUST NOT degrade existing pattern workloads when it is unavailable.

### Key Entities

- **Dashboarding platform**: The deployed capability that presents dashboards and alerts across all three domains through a single cluster route protected by cluster OAuth.
- **Data source**: A configured source of metrics for a monitoring domain, including sources for external components.
- **Dashboard**: A defined, versioned view of metrics for a monitoring domain, declaratively configured.
- **Alert rule**: A declared threshold-and-condition definition that fires when breached, tied to a monitoring domain.
- **Notification channel**: The PagerDuty integration to which alert notifications are delivered.
- **Access control scope**: The set of roles, sourced from the cluster's built-in OAuth/identity provider, governing who can view dashboards and who can manage alert configuration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a supported cluster, an operator can deploy the pattern with dashboarding enabled and reach populated dashboards for OpenShift system workloads, application workloads, and external components from a single access point without manual cluster-side configuration.
- **SC-002**: In 100% of validation runs, a threshold breach on any of the three domains produces a fired alert that is recorded in the dashboarding platform.
- **SC-003**: In 100% of validation runs with PagerDuty configured, a fired alert is delivered to PagerDuty within the alert evaluation interval.
- **SC-004**: In 100% of validation runs, a fired alert resolves automatically once the underlying condition clears.
- **SC-005**: In 100% of validation runs, a dashboard, data source, or alert rule added solely through the pattern's Git-based configuration appears and becomes active after reconciliation without manual cluster-side action.
- **SC-006**: In 100% of validation runs, unauthorized users cannot view dashboards or modify alert configuration.
- **SC-007**: In 100% of validation runs where the dashboarding platform is unavailable, existing pattern workloads continue to operate normally.

## Assumptions

- A single unified dashboarding platform is sufficient to cover all three monitoring domains; multiple dashboarding tools are not required.
- OpenShift system workload telemetry is available from the cluster's platform monitoring; application workload telemetry is available from user workloads that expose metrics.
- External components expose their metrics over HTTP/HTTPS as Prometheus-style exporters; no SNMP, power, or other proprietary acquisition is assumed for v1.
- Alert notifications are delivered to PagerDuty as the sole destination; the PagerDuty integration (e.g., a service integration key) is configured through the pattern's secret-management mechanism.
- The dashboarding capability is an application within the pattern and reuses the pattern's existing storage and secret-management mechanisms; no additional infrastructure is assumed.
- Time-series metrics history is retained for 30 days by default, sized within the pattern's storage budget.
- Dashboards and alert rules are maintained as declarative, versioned definitions; the operator is responsible for authoring domain-specific thresholds.
- Access control uses the cluster's built-in OAuth/identity provider (OpenShift users and groups); no new identity provider is assumed.
- The dashboarding access point is exposed as a cluster route within the lab network and is not intended for public internet exposure.