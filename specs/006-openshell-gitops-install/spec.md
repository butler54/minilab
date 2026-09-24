# Feature Specification: OpenShell Agent Sandbox Platform via GitOps

**Feature Branch**: `006-openshell-gitops-install`

**Created**: 2026-09-23

**Status**: Draft

**Input**: User description: "Install and configure openshell on this openshift cluster using the gitops pattern. Use the Red Hat blog on kernel-level agent security in OpenShift AI 3.5 and the NVIDIA OpenShell OpenShift documentation to install via gitops. Where possible include within the scope SPIFFE/SPIRE via openshift ZTWIM if it is possible / ready."

## Clarifications

### Session 2026-09-23

- Q: How should the gateway be exposed and secured (FR-007)? -> A: cert-manager with Let's Encrypt via DNS-01 on Cloudflare (operator owns the FQDN); DNS-01 only; wildcard `*.apps` certificate or a dedicated hostname certificate both acceptable.
- Q: How should SPIFFE/SPIRE via OpenShift ZTWIM be scoped (FR-011)? -> A: Deploy ZTWIM now via GitOps and integrate what OpenShell supports today; document the remainder as follow-up.
- Q: How far beyond platform install should the feature go (FR-014)? -> A: Include a demonstration coding-agent sandbox wired to an external LLM provider, credentials via vault/external-secrets; in-cluster inference out of scope.
- Q: Which external LLM provider should the demonstration coding agent use? -> A: OpenAI (egress allow rule for `api.openai.com`, API key via vault/external-secrets). The operator will bring their own OpenShell policy configuration; the feature provides the GitOps policy-management mechanism and a deny-by-default baseline, not the policy content.
- Q: Should OpenShell's operational signals integrate with the pattern's observability stack? -> A: Metrics only — scrape gateway/supervisor metrics into the pattern's monitoring stack; OCSF security events remain CLI/live-inspection only (no event shipping or dashboards in scope).
- Q: How many sandboxes should the platform be sized and soak-tested to run concurrently? -> A: 3 concurrent sandboxes (demonstration agent plus experiment headroom); sandbox capacity must carry explicit resource guardrails so platform components are never starved.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - GitOps-Managed OpenShell Platform (Priority: P1)

As a pattern operator, I can declare OpenShell in the pattern's values files and have Argo CD reconcile the entire platform — namespace, security bindings, prerequisite sandbox controller, and the OpenShell gateway — so that the capability is rebuilt deterministically from Git with no manual cluster steps.

**Why this priority**: The constitution mandates GitOps-first; an OpenShell install that requires imperative commands on the cluster violates the project's core principle and cannot survive a cluster rebuild.

**Independent Test**: Commit the OpenShell configuration to Git, reconcile the pattern, and confirm the gateway reaches a healthy, ready state without any manual `oc`/`kubectl` action against the cluster.

**Acceptance Scenarios**:

1. **Given** a cluster without OpenShell, **When** the pattern is reconciled with OpenShell enabled, **Then** the prerequisite sandbox controller and the OpenShell gateway are installed in the correct order and reach a healthy state.
2. **Given** the platform is deployed, **When** the GitOps applications are deleted and re-synced, **Then** the platform is restored to a working state from Git alone.
3. **Given** the deployment completes, **When** cluster admission evaluates sandbox pods, **Then** OpenShift's security constraints are satisfied through declarative, Git-managed bindings rather than imperative grants.
4. **Given** the gateway is running, **When** the operator queries the pattern's monitoring stack, **Then** gateway and supervisor metrics are available without any additional manual setup.

---

### User Story 2 - Verified Kernel-Enforced Sandboxing (Priority: P1)

As a pattern operator, I can create a sandbox through the gateway and observe that egress is denied by default and that allow/deny decisions produce structured security events, so that I have confidence agent workloads are contained by kernel-level controls rather than best-effort guardrails.

**Why this priority**: A gateway that is installed but cannot run a policy-governed sandbox delivers no security value; this proves the platform is functional, not merely present.

**Independent Test**: Register the CLI against the gateway, create a sandbox, attempt a non-allowlisted outbound connection from inside it, and confirm the attempt is denied and recorded as a structured security event.

**Acceptance Scenarios**:

1. **Given** a healthy gateway, **When** an operator creates a sandbox, **Then** the sandbox starts and reports ready through the gateway.
2. **Given** a running sandbox with default policy, **When** a process inside the sandbox attempts a non-allowlisted network connection, **Then** the connection is denied and a structured denial event is emitted.
3. **Given** policy is managed as code, **When** an allow rule for a specific destination is added through Git-managed configuration and reconciled, **Then** traffic to that destination is permitted and all other egress remains denied.

---

### User Story 3 - Reachable, Publicly-Trusted Gateway Access (Priority: P2)

As a pattern operator, I can reach the gateway through a stable, cluster-native entry point presenting a publicly trusted certificate issued via automated DNS validation against my own public domain, so that I am not dependent on ad-hoc port-forward sessions or local trust-store hacks for regular use.

**Why this priority**: The upstream evaluation path (plaintext, port-forward) is explicitly evaluation-only; a lab that other services and repeated CLI use depend on needs a stable, encrypted endpoint, but the platform remains usable (P1 stories) without it.

**Independent Test**: From a workstation off-cluster with no custom CA installed, register the CLI against the gateway's external hostname and successfully query gateway status over a connection that passes standard public TLS verification.

**Acceptance Scenarios**:

1. **Given** the platform is installed, **When** an operator connects to the gateway's public hostname, **Then** the gateway terminates TLS with a publicly trusted certificate issued automatically through the domain owner's DNS provider.
2. **Given** certificate issuance, **When** the certificate approaches expiry, **Then** it is renewed automatically without operator action or gateway rebuild.
3. **Given** DNS validation is the only allowed challenge type, **When** issuance is configured, **Then** no HTTP-01 challenge surface is required or exposed.

---

### User Story 4 - Workload Identity via SPIFFE/SPIRE (Priority: P3)

As a security-conscious operator, I have OpenShift's zero-trust workload identity capability (SPIFFE/SPIRE via ZTWIM) deployed through the same GitOps machinery, integrated with OpenShell wherever the installed release actually supports it, so that agent identity can be grounded in platform-issued workload identities as upstream support lands — and I have a Git-managed record of what is and is not consumable today.

**Why this priority**: The user explicitly requested ZTWIM deployment now with integration where possible; upstream signals indicate SPIFFE-based agent identity is on the OpenShell roadmap rather than shipped, so the identity groundwork is valuable but not the core deliverable.

**Independent Test**: Reconcile the pattern and verify ZTWIM/SPIRE components deploy and issue identities; separately verify a Git-managed record exists stating exactly which OpenShell integration points (if any) consume SPIFFE identities today, and what upstream milestones would unlock more.

**Acceptance Scenarios**:

1. **Given** the pattern is reconciled with the feature enabled, **When** ZTWIM components are declared, **Then** SPIRE server and agent deploy via GitOps and become healthy on the single-node cluster.
2. **Given** ZTWIM is healthy, **When** the operator reviews the feature's documentation, **Then** it records with evidence which OpenShell surfaces consume SPIFFE identities today and which are deferred to upstream releases.
3. **Given** a consumable integration point exists, **When** the pattern is reconciled, **Then** that integration is configured through Git-managed resources and identities are issued to the relevant workloads.
4. **Given** the ZTWIM operator is unavailable or unsupported for the cluster's OpenShift version, **When** the assessment is recorded, **Then** the feature continues without the identity components and records the blocker instead of failing the platform deployment.

---

### User Story 5 - Governed Coding-Agent Demonstration (Priority: P3)

As a pattern operator, I can launch a sample coding agent inside a sandbox that reaches the OpenAI API through policy-approved egress, with the API key delivered through the pattern's secrets mechanism, so that the platform's governance story is demonstrated end-to-end on a real agent workload rather than a synthetic smoke test.

**Why this priority**: The user's chosen demonstration scope; it proves credential handling and policy-governed egress on a realistic workload, but the platform is fully functional without it.

**Independent Test**: Create the demonstration sandbox from Git-managed configuration, run the coding agent, and confirm it can reach only the OpenAI API endpoint (and any other allow-listed destinations) while all other egress is denied and recorded.

**Acceptance Scenarios**:

1. **Given** the platform is installed and the OpenAI API key exists in the pattern's secrets store, **When** the demonstration sandbox is created, **Then** the credential is delivered through the vault/external-secrets mechanism and is never committed to Git.
2. **Given** the demonstration agent is running, **When** it calls the OpenAI API, **Then** the traffic is permitted by Git-managed egress policy and the call succeeds.
3. **Given** the demonstration agent is running, **When** it attempts any non-allow-listed egress, **Then** the attempt is denied and recorded as a structured security event.

---

### Edge Cases

- The gateway chart's preflight check fails if the prerequisite sandbox controller/CRDs are absent; GitOps sync ordering must enforce the dependency or the platform enters a persistent failed state.
- Certificate material is bootstrapped by install-time jobs; re-running those jobs on upgrade may rotate trust roots and break previously registered CLI clients — regeneration behavior must be understood and controlled.
- The external endpoint's DNS name must appear in the gateway server certificate's SANs, or clients fail TLS verification after everything else succeeds.
- Granting sandbox pods the privileged security context constraint weakens node-level isolation; on a single-node cluster sandboxes share the control plane node, so this trade-off must be explicit and accepted.
- Upstream documents that on OpenShift nodes, optional network-rule expressions can fail silently without rolling back the required enforcement rules; verification must confirm the required proxy-bypass reject rules are actually in effect, not just requested.
- The upstream chart is experimental and its values schema may change between versions; version pins must be deliberate and upgrades treated as reviewed changes.
- Sandbox and gateway workloads add resource pressure to a single-node cluster budget; eviction or starvation of platform components must not occur.
- The ZTWIM operator may be unavailable or unsupported for the cluster's OpenShift version; the readiness assessment must detect this rather than fail mid-reconcile.
- The Cloudflare API credential used for DNS-01 challenges is a high-value secret; compromise allows DNS manipulation for the operator's domain, so it must never be rendered into Git-visible manifests.
- Let's Encrypt rate limits and DNS propagation delays can stall first issuance; the platform must tolerate a pending-certificate window without leaving the gateway in a misleading "healthy but unreachable" state.
- The OpenAI API endpoint or surface may change over time; the demonstration's Git-managed egress policy must be easy to locate and update.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Every OpenShell-related resource — namespace, RBAC, security-context-constraint bindings, prerequisite controller, CRDs, and the gateway itself — MUST be declared in Git and reconciled by Argo CD. No resource may reach the cluster through imperative commands.
- **FR-002**: Installation MUST be expressed through Helm charts only (upstream chart consumed as a version-pinned dependency or referenced chart), consistent with the pattern's Helm-only principle; cluster/environment variation MUST be expressed through values files.
- **FR-003**: The Kubernetes Agent Sandbox controller and its CRDs MUST be deployed declaratively and become healthy before the OpenShell gateway is reconciled (explicit sync ordering).
- **FR-004**: The OpenShift-mandated security exceptions (privileged security context constraint for the sandbox service account; SCC-assigned UID and fsGroup via chart overrides) MUST be expressed declaratively in Git, with the security trade-off documented in the repository.
- **FR-005**: The OpenShell chart and all container images MUST come from trusted, version-pinned sources; floating tags (e.g., `latest`) are prohibited.
- **FR-006**: The gateway MUST persist its state on cluster storage so it survives pod restarts and node drains.
- **FR-007**: The gateway MUST be exposed via an OpenShift Route at a hostname under the operator-owned public domain, terminating TLS at the gateway with a publicly trusted certificate issued by Let's Encrypt through cert-manager using DNS-01 challenges solved via Cloudflare. No HTTP-01 challenge surface may be required.
- **FR-007a**: cert-manager and its ClusterIssuer configuration MUST be deployed and managed as part of the pattern through GitOps; the Cloudflare API credential MUST be delivered via the pattern's vault/external-secrets mechanism and never committed to Git.
- **FR-008**: Sandbox egress MUST be deny-by-default, and sandbox network policy MUST be managed as declarative configuration in Git and reconciled like any other pattern configuration. The feature provides the GitOps policy-management mechanism and a deny-by-default baseline; actual policy content beyond the baseline is operator-supplied.
- **FR-009**: Sandbox security events (allow/deny decisions) MUST be emitted in the platform's structured event format and be observable by the operator via live inspection from a workstation, without modifying the cluster; event shipping into cluster logging or a SIEM is out of scope. Separately, gateway and supervisor operational metrics MUST be scraped by the pattern's existing monitoring stack so gateway health is visible alongside other pattern workloads.
- **FR-010**: Any secret material the feature requires (e.g., model-provider credentials for a demonstration workload) MUST be delivered through the pattern's vault/external-secrets mechanism; no secret values may be committed to Git.
- **FR-011**: The feature MUST deploy OpenShift ZTWIM (SPIFFE/SPIRE) through GitOps alongside OpenShell, subject to operator availability for the cluster's OpenShift version. The feature MUST record in Git a readiness assessment covering which OpenShell integration points can consume SPIFFE identities at the installed version, MUST configure every integration point that is consumable today, and MUST record the remaining gaps with named upstream triggers for re-evaluation. If the ZTWIM operator is unavailable for the cluster version, the feature MUST record the blocker and the platform MUST still deploy successfully without the identity components.
- **FR-012**: The total resource footprint of the feature (gateway, prerequisite controller, identity components, and capacity for up to 3 concurrent sandboxes) MUST fit the single-node cluster budget alongside existing pattern workloads, with explicit resource guardrails on sandbox capacity so platform components cannot be starved or evicted by sandbox consumption.
- **FR-013**: The feature MUST pass the pattern's validation gates (schema validation, cluster validation, and Argo CD health checks) before being considered complete.
- **FR-014**: The feature MUST include a demonstration coding-agent sandbox connecting to the OpenAI API, defined through Git-managed configuration. The OpenAI API key MUST be delivered via the pattern's vault/external-secrets mechanism, and the egress allow rule for the provider's endpoint MUST be expressed in Git-managed sandbox policy (expected within the operator-supplied policy configuration rather than authored by the feature). In-cluster inference serving is out of scope.

### Key Entities

- **Gateway**: The OpenShell control plane; owns policy decisions, sandbox lifecycle, and structured security-event emission. Stateful (holds its control-plane database), reconciled as a pattern application.
- **Sandbox**: An ephemeral, kernel-isolated execution environment for an agent workload; created via the gateway, constrained by Landlock/seccomp/network isolation, with deny-by-default egress.
- **Sandbox Policy**: Declarative allow rules (destinations, methods, binaries) extending a deny-by-default baseline; managed as code under GitOps. The feature supplies the baseline and management mechanism; substantive rule content is operator-supplied.
- **Workload Identity**: A SPIFFE identity issued by the pattern-managed SPIRE deployment (via ZTWIM); consumable by sandboxes only where the installed OpenShell version supports it.
- **Security Event**: A structured (OCSF-format) allow/deny record emitted by sandbox enforcement points; the audit trail for agent behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From a cluster with no OpenShell present, platform reconciliation alone produces a healthy gateway and prerequisite controller — zero manual cluster commands required after the pattern is applied.
- **SC-002**: An operator can go from "gateway healthy" to "first sandbox running a command" in under 5 minutes using only documented steps and Git-managed configuration.
- **SC-003**: 100% of non-allowlisted egress attempts from a sandbox are denied, and every attempt produces a corresponding structured denial event observable by the operator.
- **SC-004**: After deleting all OpenShell GitOps applications and re-syncing, the platform returns to a fully working state (gateway ready, sandbox creation succeeds) with no manual repair.
- **SC-005**: The pattern's validation gates pass with the feature enabled, and all GitOps applications report Healthy and Synced.
- **SC-005a**: Gateway and supervisor metrics are queryable in the pattern's monitoring stack within one scrape interval of the gateway becoming ready.
- **SC-006**: The SPIFFE/SPIRE readiness assessment is recorded in Git with a definitive consume/defer conclusion and, if deferred, named upstream triggers for re-evaluation.
- **SC-007**: The feature adds no acceptance-test-breaking resource pressure to the single-node cluster: during a soak running 3 concurrent sandboxes, no platform component (GitOps control plane, secrets, monitoring, or the OpenShell gateway itself) is evicted, unschedulable, or left pending due to resource exhaustion.
- **SC-008**: A workstation with a default public trust store (no custom CA installed) can establish a verified TLS session to the gateway's public hostname, and issued certificates renew automatically before expiry with no operator action.
- **SC-009**: The demonstration coding agent completes a task requiring OpenAI API calls through policy-approved egress, while 100% of its non-allow-listed egress attempts are denied and recorded.

## Assumptions

- The target is the existing minilab single-node OpenShift cluster; the upstream NVIDIA OpenShell Helm chart is installed directly. The Red Hat OpenShift AI 3.5 integrated Developer Preview is **not** assumed to be present or required.
- The deployment posture is lab/evaluation on a private network, matching upstream's explicit "experimental, not for production" status.
- The operator owns a public domain whose DNS is hosted at Cloudflare, and DNS-01 is the sole permitted ACME challenge type. A dedicated certificate for the gateway's hostname is the default; reuse of a domain wildcard certificate is an acceptable implementation choice at planning time.
- The certificate for the gateway hostname is publicly trusted (Let's Encrypt), so CLI workstations need no custom CA trust configuration.
- The cluster has outbound internet access to the upstream chart and image registries (GHCR, registry.k8s.io); air-gap mirroring is out of scope.
- The operator runs the OpenShell CLI from a workstation. (Updated during planning:) upstream does not support mTLS client certificates for user authentication on Kubernetes gateways — a Kubernetes-mode gateway requires OIDC for remote users. The plan therefore uses OpenShift's built-in OAuth server as the OIDC issuer (verified during implementation), with port-forwarded local access as the documented fallback; no separate identity provider is deployed.
- Gateway persistence uses the cluster's default storage class (pattern-managed LVMS); no external database is deployed.
- Granting the privileged security context constraint to sandbox pods is accepted as an upstream OpenShift requirement for this evaluation deployment; the risk and its single-node implications are documented in the repository.
- The operator has (or will create) an OpenAI account and API key for the demonstration workload, and will supply their own OpenShell sandbox policy configuration; the feature delivers only the deny-by-default baseline and the GitOps mechanism to reconcile operator-supplied policy.
- English is the working language for all configuration, documentation, and gap records produced by this feature.
