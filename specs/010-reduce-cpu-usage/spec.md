# Feature Specification: Reduce Minilab CPU Usage

**Feature Branch**: `010-reduce-cpu-usage`

**Created**: 2026-10-09

**Status**: Draft

**Input**: User description: "Remediation: Observations on the minilab reveal very high CPU usage with the kubeapi server using 2.27/8 CPUs. The agent sandbox operator appears to be going in and out of error states as well. Do a thorough analysis of the issues. Build a plan to cut CPU usage. Methods can include: 1. Decreasing argocd sync frequency (potentially as low as once per hour or longer) 2. Decreasing frequency of metrics collection from the k8s api 3. Any other suggestions. Thorough analysis is key first and foremost to come up with a root cause."

## Clarifications

### Session 2026-10-09

- Q: Does Story 1's acceptance require a functional sandbox smoke test, or is loop-stop (CSV Succeeded + soak) enough? → A: Functional smoke test required — one sandbox must be instantiated successfully post-repair before Story 1 closes.
- Q: How broadly should FR-001's single-owner rule be verified for other hidden conflicts? → A: Slim regression check added to the pattern's validation gates comparing GitOps-tracked resources against lifecycle-manager-owned deployments; no heavyweight one-off audit.
- Q: What minimum sustained CPU reduction counts as success for the monitoring-tuning story (SC-006, G4)? → A: ≥30% below the ~280m `prometheus-k8s-0` baseline (≈200m or lower) over a 30m window.
- Q: How should the 24-hour zero-sandbox-install-failure window (FR-002/SC-003) be verified? → A: Excluded — user's priority is stabilizing the system first; the 24h sandbox-health tail is dropped. Verification is a 1-hour soak only; long-horizon sandbox-operator stability is explicitly out of scope for this feature.

## Root-Cause Analysis Summary

On-cluster diagnostics (2026-10-09, evidence in `ANALYSIS.md` in this directory) established:

1. **Primary root cause — dual-ownership reconciliation war**: The `agent-sandbox-controller` Deployment in `agent-sandbox-system` is claimed by two controllers:
   - the GitOps application `agent-sandbox` (delivers it as a Helm-managed Deployment, selector `app.kubernetes.io/instance/name=agent-sandbox`), and
   - the Operator Lifecycle Manager (CSV `agent-sandbox-operator.v0.9.0`, which expects selector `app=agent-sandbox-controller`).

   The names match but the immutable `spec.selector` fields differ, so every OLM install attempt fails with `spec.selector: field is immutable`. OLM retries continuously with **no backoff** (observed 6+ attempts/second), generating ~23 `PUT`s/second on `clusterserviceversions`, 3 event writes per cycle, and constant object churn. This is why:
   - `olm-operator` consumes ~1458m CPU (the 2nd-worst pod on the node),
   - `kube-apiserver` consumes ~2706m CPU (~110 requests/second sustained, ~44 PUT/s),
   - the sandbox operator "appears to go in and out of error states" (CSV cycles Failed → NeedsReinstall → Pending → Failed, and the controller pod has restarted 6 times),
   - the GitOps `agent-sandbox` application reports sync status `Unknown`, adding churn to the application controller (~1029m CPU).

2. **Secondary contributor — default GitOps cadence**: The single Argo CD instance reconciles every 180s (default) and polls Git for 16 applications with no interval override. Constant OLM loop churn makes every reconciliation cycle expensive.

3. **Tertiary contributor — default metrics cadence**: Cluster monitoring runs with an entirely default configuration (empty override config) — 30s scrape intervals across all targets. The additional MonitoringStack (`minilab`) is cheap (~11m) and not the issue.

4. **Minor contributors**: a vault-unseal recurring job every 5 minutes (pulling a ~667MB image, though cached), marketplace catalog polling/reload at default cadence.

Observed cluster state: node `sno` at 7652m CPU (102% of allocatable) and 77% memory. The cluster is capped at 8 CPUs.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stop the Reconciliation War (Priority: P1)

As the minilab operator, I want every cluster resource to have exactly one reconciliation owner so that the operator-lifecycle manager and the GitOps driver stop fighting over the sandbox operator's controller, and the cluster's control plane stops burning CPU on a failed install loop.

**Why this priority**: This conflict is the root cause of the majority of the observed CPU burn (API server + OLM operator + GitOps churn) and of the sandbox operator's flapping error state. All further tuning is noise if the loop keeps running. Fixing it alone is expected to recover the largest share of CPU.

**Independent Test**: Can be tested by applying the ownership fix, then observing over 30 minutes that the operator install object reaches a stable Succeeded state, no further "field is immutable" install failures occur, control-plane CPU shows a sustained step-change reduction, and one test sandbox instantiates successfully through the repaired controller.

**Acceptance Scenarios**:

1. **Given** the conflicting dual-ownership state, **When** the fix is applied, **Then** the agent-sandbox operator install reaches a stable Succeeded state and stays there through the 1-hour post-fix soak.
2. **Given** the fix is applied, **When** 30 minutes elapse, **Then** no new `InstallComponentFailed` / "field is immutable" events are emitted for the sandbox operator.
3. **Given** the fix is applied, **When** the GitOps application is inspected, **Then** its sync status returns to a known state (`Synced`/`OutOfSync`, never `Unknown`).
4. **Given** the fix is applied, **When** Git history is inspected, **Then** the ownership decision (which system owns which resource) is declared and auditable in Git, including any one-time imperative repair needed to reach it.
5. **Given** the fix is applied and the CSV is Succeeded, **When** a test sandbox is requested, **Then** the repaired controller instantiates it successfully (functional smoke test).

---

### User Story 2 - Slow Down GitOps Reconciliation (Priority: P2)

As the minilab operator, I want GitOps reconciliation and repository polling to run at a deliberately reduced, configurable cadence (600 seconds by default, one hour as upper bound) so that the GitOps driver stops re-evaluating the full cluster state every few minutes, without losing the ability to sync immediately when I make an intentional change.

**Why this priority**: Cutting the reconcile cadence reduces baseline CPU of the GitOps controller and reduces API-server read load. On a single-operator home lab, sub-hour staleness is an acceptable trade-off, and manual sync covers urgent changes. Independent of Story 1: even after the loop is fixed, this further trims baseline load.

**Independent Test**: Can be tested by setting the reduced cadence, verifying application sync status ages up to 600 seconds before refresh, confirming CPU step-down of the GitOps controller, and confirming a manual sync still applies a change within minutes.

**Acceptance Scenarios**:

1. **Given** the reduced cadence is configured, **When** a full reconcile period passes, **Then** applications refresh at most once per the configured interval (default: 600 seconds).
2. **Given** Git drift is introduced, **When** the operator triggers a manual refresh/sync, **Then** the drift is detected and corrected within 5 minutes.
3. **Given** the reduced cadence is in place, **When** a health-degrading event occurs on an application between cycles, **Then** the degradation is visible within one reconcile interval plus 5 minutes.

---

### User Story 3 - Reduce Metrics Collection Load (Priority: P3)

As the minilab operator, I want metrics scraping and collection frequency tuned down to a level appropriate for a homelab so that monitoring consumes less CPU, while alerts and dashboards remain useful for capacity and failure awareness.

**Why this priority**: Monitoring is a meaningful but smaller share of CPU (~280m for the cluster Prometheus stack plus a light MonitoringStack). Tuning it is independent value and is safe to apply after the loop fix, when measurements isolate its effect.

**Independent Test**: Can be tested by applying tuning, verifying monitoring stack CPU drops, and confirming dashboards still refresh and alert rules still evaluate within their new (documented) evaluation cadence.

**Acceptance Scenarios**:

1. **Given** tuned scrape configuration, **When** monitoring CPU is observed over 30 minutes, **Then** the cluster monitoring stack's CPU is at least 30% lower than the ~280m `prometheus-k8s-0` pre-tuning baseline (≈200m or lower, sustained).
2. **Given** tuned configuration, **When** a user opens existing dashboards, **Then** all panels still render data (staleness no worse than the documented new cadence).
3. **Given** tuned configuration, **When** the documentation is reviewed, **Then** any metrics or targets that were removed are listed with rationale, so coverage loss is an explicit decision rather than drift.

---

### User Story 4 - Trim Recurring Ancillary Load (Priority: P4)

As the minilab operator, I want ancillary recurring workloads (vault-unseal cadence, catalog polling, operator images) reviewed and reduced where safe so that small, constant load sources are removed rather than tolerated.

**Why this priority**: Each item is minor individually, but the constitution's "Simplicity First" resource-budget principle requires them to fit the single-node budget. These are quick wins after the larger stories land.

**Independent Test**: Can be tested by reviewing each identified recurring workload, reducing its frequency (or removing it if redundant), and confirming the failure mode it protects against is still covered (e.g., vault still auto-unseals after node reboot).

**Acceptance Scenarios**:

1. **Given** the vault-unseal job frequency is reduced, **When** a node or vault pod restart occurs, **Then** the vault is automatically unsealed within an acceptable window (≤ 30 minutes) without manual intervention.
2. **Given** catalog polling intervals are increased, **When** operator updates are published, **Then** they become visible within the documented (longer) window rather than hours at default cadence.

---

### Edge Cases

- **Reconciliation conflict repair implies a one-time destructive step**: the reconciler war can only be broken by removing one owner's copy of the deployment, which per project principles must be recorded as a documented, idempotent imperative step and reconciled back to Git — the spec must not assume a purely declarative path exists.
- **Reduced reconciliation delays failure detection**: operator failures (like the sandbox CSV loop) may go unnoticed for up to one full reconcile cycle (600s by default) — alerting coverage must not depend on GitOps health responsiveness alone.
- **Longer scrape intervals also lengthen alert evaluation**: critical control-plane alerts (node, etcd, API availability) must remain timely enough to warn of node saturation; tuning must preserve a tight cadence for these.
- **Vault unseal trade-off**: slowing the unseal job increases post-restart dark time; if the cluster reboots, dependent workloads may error until unseal runs — the window must be bounded and documented.
- **Stale GitOps state after emergency changes**: manual cluster edits are already drift (per constitution); longer cycles mean it persists longer — users must know to trigger a manual sync.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every cluster resource delivered by the pattern MUST have exactly one declared reconciliation owner (GitOps-managed or operator-lifecycler-managed), and that ownership decision MUST be recorded in Git. Compliance MUST be enforced permanently by a slim regression check in the pattern's validation gates that flags any GitOps-tracked resource colliding with a lifecycle-manager-owned deployment.
- **FR-002**: The remediation MUST break the OLM/GitOps conflict on the agent-sandbox controller such that the operator installation reaches a stable Succeeded state with zero recurring install-failure events over a 1-hour post-fix soak window, and the repaired controller MUST successfully instantiate one test sandbox (functional smoke test) before the stabilization story closes.
- **FR-003**: Any one-time imperative repair steps required to reach the conflict-free state MUST be automated, idempotent, documented in Git with rationale before execution, and their result reconciled back under GitOps afterwards (per project Principle II).
- **FR-004**: GitOps reconciliation and Git polling cadence MUST be configurable pattern-wide. The delivered default MUST be **600s** (per user direction, 2026-10-09, superseding the original once-per-hour suggestion), with the option to raise it to hourly or longer from that baseline.
- **FR-005**: Users MUST retain a fast-path to force immediate GitOps refresh/sync of a single application within 5 minutes, so urgent changes are not held back by the reduced cadence.
- **FR-006**: Metrics scrape and rule-evaluation intervals MUST be tunable as an explicit pattern setting, and delivered defaults MUST demonstrably reduce monitoring CPU versus the current all-default configuration.
- **FR-007**: Monitoring tuning MUST preserve useful alerting for node saturation, control-plane availability, cluster-wide component health, and storage; any metric/target/practice that is removed or slowed MUST be documented with rationale.
- **FR-008**: Dashboards supplied by the observability feature MUST remain functional after tuning (all panels render data with documented staleness bounds).
- **FR-009**: Ancillary recurring workloads (vault-unseal job, operator catalog polling) MUST be reviewed, and their frequency reduced where the protective purpose they serve remains tolerably covered; the resulting cadences MUST be documented in Git.
- **FR-010**: All changes MUST land through Git (no direct cluster mutation), follow Helm-only configuration, and pass the pattern's validation gates (`validate-schema`, `validate-cluster`, `argo-healthcheck`) before being considered complete.
- **FR-011**: Before/after evidence MUST be captured: for each remediated source, baseline and post-change CPU (and API request rates where relevant) MUST be recorded in the feature directory so the reduction is verifiable, not anecdotal.

### Key Entities

- **Reconciliation Owner**: the single component accountable for a resource's lifecycle; attributes: owner type (GitOps application vs. operator installer), resource identity, declaration location in Git. A resource has exactly one.
- **Operator Installation (CSV)**: the installed operator claim tracked by the lifecycle manager; attributes: name, phase/health, install-failure event stream. Health of this object signals whether a reconciliation conflict exists.
- **GitOps Reconcile Cadence**: pattern-wide schedule governing how often desired state is re-evaluated; attributes: reconciliation interval, refresh interval, manual-override path.
- **Scrape Configuration**: monitoring schedule and target set; attributes: scrape/evaluation intervals, included/excluded targets, documentation of dropped coverage.
- **CPU Budget**: the node's allocatable CPU and per-sustained-workload consumption profile; attributes: node capacity (8 cores), per-component sustained usage, satiation threshold.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Sustained node CPU utilization drops from ~102% of allocatable to below 70%, over a 1-hour observation window at idle cluster workload.
- **SC-002**: Control-plane API-server CPU drops by at least 60% versus the 2.27-core baseline, over the same window.
- **SC-003**: API request rate on operator-installation objects drops from ~23 writes/second to fewer than 1 per minute sustained; zero install-failure events regarding immutable selectors recur during the 1-hour post-fix soak.
- **SC-004**: Lifecycle-manager operator CPU drops from ~1458m to under 100m sustained.
- **SC-005**: All GitOps applications report a known sync/health state (none show `Unknown`) and the reconciliation interval is verifiably at least 600s, with manual sync proven to apply drift within 5 minutes.
- **SC-006**: Monitoring stack CPU drops by at least 30% versus the ~280m `prometheus-k8s-0` baseline (≈200m or lower, sustained 30m), and 100% of pre-existing dashboard panels continue to render data with documented staleness bounds.
- **SC-007**: Total cluster CPU at idle drops by at least 30% versus the pre-remediation baseline.
- **SC-008**: Every change plus its rationale and every one-time repair step is visible in Git history, and pattern validation gates pass.

## Assumptions

- The cluster is a disposable single-node homelab projection of Git; rebuilding baseline state from Git remains acceptable and longer reconciliation staleness (up to hours) is tolerable for non-alerted drift.
- The sandbox operator's workload capability (sandbox CRDs and queue) must keep working after the fix; instantiating the controller itself is in-scope only as far as resolving ownership.
- The agent-sandbox operator lifecycle subscription is the desired ownership model for the operator itself (per GitOps-first subscription pattern) unless analysis during planning finds it technically impossible.
- Monitoring coverage requirements are laissez-faire homelab grade: no SLA-bound alerting; control-plane failure alerts stay timely. User direction (2026-10-09): platform-monitoring CPU reduction is delivered via the CMO's supported profile mechanism, and a 60s scrape cadence on pattern-owned scrape configs (OCP 4.22's CMO exposes no platform scrape-interval setting).
- The vault-unseal job exists to make the disposable cluster self-healing after restarts; near-instantaneous unseal is not a business requirement.
- Baseline metrics captured during this specification's diagnostics (in `ANALYSIS.md`) are valid as the "before" reference point.
- Stabilizing cluster CPU takes precedence over long-horizon sandbox health (user direction, 2026-10-09): the sandbox-operator fix proves itself with a 1-hour soak; persistent long-tail sandbox instability beyond that window is out of scope for this feature.
- CPU targets are evaluated at idle cluster workload (no sandbox demo runs, no deploys in flight).
