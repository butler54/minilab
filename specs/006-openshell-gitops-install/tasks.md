# Tasks: OpenShell Agent Sandbox Platform via GitOps

**Input**: Design documents from `/specs/006-openshell-gitops-install/`

**Prerequisites**: plan.md, spec.md, research.md (D1–D10), data-model.md, contracts/, quickstart.md (gates G0–G4, validations V-*)

**Tests**: Included — repo convention (existing `tests/test-*.sh`, `Makefile` validate targets) and plan.md commit to `tests/test-openshell-*.sh` static suites; runtime validations live in quickstart V-* referenced by runtime tasks.

**Organization**: 5 user stories from spec.md (US1, US2 P1 → US3 P2 → US4, US5 P3). Cluster-runtime tasks are marked *(runtime)* and follow quickstart.md.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Values contract surface, chart scaffolding, test harness

- [x] T001 Add values contract keys: `global.dnsZone`, `global.acmeEmail` in values-global.yaml; `openshell.*` block (enabled, gatewayHostname, issuer=staging, trustDomain, sandbox.maxConcurrent=3, demo.enabled=false) in values-prod.yaml per specs/006-openshell-gitops-install/contracts/values-contract.md
- [x] T002 [P] Extend schema/assert validation for the new values keys (hostname ends with dnsZone; issuer∈{staging,prod}; 1≤maxConcurrent≤5) in the values schema used by `make validate-schema` and/or tests/validate-pattern-config.sh
- [x] T003 [P] Vendor kubernetes-sigs/agent-sandbox `helm/` chart directory at tag v1.0.3 into charts/agent-sandbox/ (record provenance + version in charts/agent-sandbox/README.md: source URL, tag, date) per research.md D5
- [x] T004 Add `validate-openshell` target to Makefile running tests/test-openshell-*.sh, mirroring the existing `validate-observability` target

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Namespace security posture, capacity guardrails, and secret plumbing every story depends on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Create charts/openshell-platform/ (Chart.yaml, values.yaml, values.schema.json following charts/observability-config pattern) with: RoleBinding granting `system:openshift:scc:privileged` to SA `openshell-sandbox` in ns `openshell` (FR-004 declarative SCC), ResourceQuota and LimitRange in ns `openshell` sized from `openshell.sandbox.maxConcurrent` per research.md D9/FR-012
- [x] T006 Create ExternalSecret templates/openshell-kek-es.yaml in charts/openshell-platform/ mapping vault path `secret/data/hub/openshell-gateway-kek` → Secret `openshell-kek` (key `kek`) in ns `openshell` per contracts/secrets-contract.md (research D4 requires pre-existing KEK for GitOps rendering)
- [x] T007 Wire into values-prod.yaml clusterGroup: namespace `openshell` (with cluster-monitoring label per env precedent), application `openshell-platform` (path charts/openshell-platform, sync wave `-3`, gated on openshell.enabled)
- [x] T008 [P] Write tests/test-openshell-quota.sh: `helm template charts/openshell-platform` asserts ResourceQuota CPU/mem/pods ceilings match maxConcurrent=3 arithmetic and LimitRange default+max entries exist
- [x] T009 [P] Write tests/test-openshell-secrets.sh: assert every ExternalSecret's vault path/key exactly matches contracts/secrets-contract.md, and grep-prove no `stringData`/literal secret values anywhere under charts/ and values-*.yaml

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 - GitOps-Managed OpenShell Platform (P1) 🎯 MVP

**Goal**: Pattern reconciliation alone delivers a healthy OpenShell gateway with operator-visible metrics — zero manual cluster steps

**Independent Test**: `openshell.enabled=true` reconciled → agent-sandbox controller Running, gateway Ready, metrics queryable, `make argo-healthcheck` green (quickstart G4, V-ORDER, V-METRICS)

### Tests for User Story 1 (write first, confirm they FAIL)

- [x] T010 [P] [US1] Write tests/test-openshell-render.sh: `helm template` every new chart; assert rendered OpenShell values data (agentSandbox.preflight.enabled=false, server.telemetryEnabled=false, supervisor.sideloadMethod=init-container, podSecurityContext.fsGroup null, securityContext.runAsUser null) and that charts/agent-sandbox renders its CRDs
- [x] T011 [P] [US1] Write tests/test-openshell-ordering.sh: assert sync-wave annotations in values-prod.yaml satisfy plan.md ordering (agent-sandbox `-5` < openshell-platform `-3` < KEK ES ≤ `-2` < openshell `0`) and openshell app is gated on openshell.enabled
- [x] T012 [P] [US1] Write tests/test-openshell-pins.sh: no `latest`/empty tag floating images in new charts+values files; charts/openshell vendored .tgz digest matches Chart.lock; agent-sandbox image pinned to v1.0.3 (FR-005)

### Implementation for User Story 1

- [x] T013 [US1] Configure charts/agent-sandbox/values.yaml per research D5: `controller.extensions=false`, `image.tag=v1.0.3`, resources 10m/64Mi req 500m/128Mi lim, containerSecurityContext seccompProfile RuntimeDefault
- [x] T014 [US1] Wire `agent-sandbox` application into values-prod.yaml clusterGroup (path charts/agent-sandbox, sync wave `-5`)
- [x] T015 [US1] Create charts/openshell/ wrapper per research D1: Chart.yaml with dependencies entry `oci://ghcr.io/nvidia/openshell/helm-chart` version `0.0.116` + digest pin; run `helm dependency build`; commit vendored charts/openshell/charts/openshell-0.0.116.tgz and Chart.lock
- [x] T016 [US1] Author charts/openshell/values.yaml core values per research D4/D10: replicaCount 1, image.tag `0.0.116`, supervisor.image tag explicit, supervisor.sideloadMethod `init-container`, supervisor.topology `combined`, server.telemetryEnabled `false`, server.sandboxImage pinned concrete tag, server.appArmorProfile `Unconfined`, agentSandbox.preflight.enabled `false`, server.credentialStorage.existingSecret `openshell-kek`, podSecurityContext.fsGroup `null`, securityContext.runAsUser `null`
- [x] T017 [US1] Add user authentication per research D3: server.oidc.issuer/audience targeting OpenShift OAuth discovery endpoint, server.oidc.caConfigMapName with ingress CA ConfigMap template, and an OAuthClient manifest (CLI callback redirect) in charts/openshell/templates/; document the port-forward fallback in charts/openshell/README.md
- [x] T018 [US1] Wire `openshell` application into values-prod.yaml (path charts/openshell, sync wave `0`, gated on openshell.enabled)
- [x] T019 [US1] Add ServiceMonitor in charts/openshell-platform/templates/ scraping gateway+supervisor metrics into the pattern monitoring stack (FR-009, SC-005a); label per minilab-observability convention
- [x] T020 [US1] *(runtime)* Cluster bring-up per quickstart G4/V-ORDER: seed vault keys per contracts/secrets-contract.md (G0), apply pattern with openshell.enabled=true, confirm ordered reconciliation, `oc -n agent-sandbox-system get deploy` Running, `oc -n openshell rollout status statefulset/openshell`, `make argo-healthcheck` green — no manual cluster mutation
- [x] T021 [US1] *(runtime)* Verify V-AUTH and V-METRICS: `openshell gateway add/login` via configured OIDC then `openshell status` succeeds (record fallback if OpenShift OAuth is unsatisfiable, per research D3); platform monitoring answers `up{service=~".*openshell.*"}==1` within one scrape interval

**Checkpoint**: US1 fully functional — platform present, healthy, observable, CLI-authenticated

---

## Phase 4: User Story 2 - Verified Kernel-Enforced Sandboxing (P1)

**Goal**: Prove deny-by-default egress and structured security events on a live sandbox; policy-managed-as-code mechanism in place

**Independent Test**: quickstart V-EGRESS — unauthorized connection denied with OCSF event; allow-listed destination permitted after Git-managed policy reconcile

- [x] T022 [US2] Create charts/openshell-policy/: deny-all egress baseline + operator drop-in mechanism for operator-supplied policy documents (research D9 surface; spec FR-008), wired as application at sync wave `+1` in values-prod.yaml
- [x] T023 [US2] Add a sample allow document (destination `api.openai.com:443`) to the operator drop-in location in charts/openshell-policy/ clearly marked SAMPLE (operator brings real policy per spec clarification); add render assertion for the baseline to tests/test-openshell-render.sh
- [ ] T024 [US2] *(runtime)* Run quickstart V-EGRESS: sandbox created and command executed < 5 min (SC-002); `curl https://example.com` from inside denied with OCSF DENIED event in `openshell term`; after policy reconcile `https://api.openai.com` permitted while other egress stays denied (SC-003); verify required nftables proxy-bypass reject rules are in effect on the node (upstream OpenShift caveat, research risks)
- [ ] T025 [US2] Document evidence (commands + observed DENIED/ALLOWED events, nftables check) in specs/006-openshell-gitops-install/ as implementation notes or docs/ runbook

**Checkpoint**: US1 AND US2 independently functional — sandboxing is provably enforced

---

## Phase 5: User Story 3 - Reachable, Publicly-Trusted Gateway Access (P2)

**Goal**: Gateway reachable on public FQDN with Let's Encrypt cert via cert-manager DNS-01 (Cloudflare); staging→prod issuer flip proven

**Independent Test**: quickstart V-TLS — workstation with default trust store verifies the gateway certificate at its public hostname

- [x] T026 [US3] Add to values-prod.yaml: namespaces `cert-manager-operator` (operatorGroup) and `cert-manager`, subscription `openshift-cert-manager-operator` (channel stable-v1, redhat-operators) per research D6
- [x] T027 [US3] Create charts/cert-manager-config/: operator-readiness gate (mirror charts/lvms-operator-readiness), ExternalSecret `cloudflare-api-token` (vault `secret/data/hub/openshell-cloudflare` → ns `cert-manager`, key `api-token`) and ClusterIssuers `letsencrypt-staging` + `letsencrypt-prod` (ACME dns01.cloudflare.apiTokenSecretRef, selector dnsZones from global.dnsZone, email from global.acmeEmail) in same wave per secrets-contract rule 5; wire application at wave `-6`
- [ ] T028 [US3] *(runtime, one-time)* G0: seed Cloudflare API token (Zone:DNS:Edit + Zone:Zone:Read on the zone) into vault path `secret/data/hub/openshell-cloudflare` per contracts/secrets-contract.md
- [x] T029 [US3] Enable in charts/openshell/values.yaml per research D2: openshiftRoute.enabled=true, openshiftRoute.host=openshell.gatewayHostname, certManager.enabled=true, certManager.serverIssuerRef={kind: ClusterIssuer, name: from `openshell.issuer` value}, certManager.serverDnsNames[0]=openshell.gatewayHostname; assert hostname consistency in tests/test-openshell-render.sh
- [ ] T030 [US3] *(runtime)* Run quickstart V-TLS with `openshell.issuer: staging`: issuers Ready, Certificate Ready with correct SAN; staging cert fails public trust as expected; internal supervisor path unaffected (SNI split — sandboxes still start)
- [ ] T031 [US3] *(runtime)* Flip `openshell.issuer: prod`, verify prod issuance and stock-workstation verification via quickstart V-TLS step 3 (SC-008); force one renewal to prove the loop; record DNS-01-only posture (no HTTP-01 anywhere)

**Checkpoint**: Public, publicly-trusted gateway access works end-to-end

---

## Phase 6: User Story 4 - Workload Identity via SPIFFE/SPIRE (P3)

**Goal**: ZTWIM deployed via GitOps; OpenShell SPIFFE integration enabled where chart 0.0.116 supports; living readiness record in Git

**Independent Test**: quickstart V-SPIFFE — ZTWIM CRs Ready, SVID delivered to a selected pod, spiffe provider token grant accepted by gateway (or documented fallback per research D8)

- [x] T032 [US4] Add to values-prod.yaml: namespace `zero-trust-workload-identity-manager` (operatorGroup), subscription `openshift-zero-trust-workload-identity-manager` (channel stable-v1) per research D7
- [x] T033 [US4] Create charts/ztwim-config/: operator-readiness gate, singleton CRs named `cluster` — ZeroTrustWorkloadIdentityManager (trustDomain from `openshell.trustDomain`, bundleConfigMap), SpireServer (sqlite3, 2Gi PVC default SC, explicit resources), SpireAgent (k8sPSAT + k8s workload attestors, resources), SpiffeCSIDriver (default plugin csi.spiffe.io) per research D7; wire application at wave `-4`
- [x] T034 [US4] Create ClusterSPIFFEID `openshell-sandbox-workloads` (selector ns `openshell` + SA `openshell-sandbox`, template `/openshell/sandbox`) in charts/ztwim-config/
- [x] T035 [US4] Enable server.providerTokenGrants.spiffe (+workloadApiSocketPath) in charts/openshell/values.yaml ONLY after verifying the values exist in chart 0.0.116 (`helm show values`, research D8 verification); if absent, keep ZTWIM standalone, use gateway-side provider credential without SPIFFE exchange, and record the gap per research D8 fallback
- [ ] T036 [US4] *(runtime)* Run quickstart V-SPIFFE: all ZTWIM CRs Ready; SVID issuance proven for a selected pod (socket mount + identity fetch); if T035 enabled, sandbox reaches OpenAI with no key in sandbox env/mounts
- [x] T037 [US4] Instantiate docs/openshell-spiffe-assessment.md from contracts/ztwim-assessment.md with verified evidence, deferred rows, and re-evaluation triggers (FR-011, SC-006)

**Checkpoint**: Identity groundwork live and honestly recorded; integration state evidenced in Git

---

## Phase 7: User Story 5 - Governed Coding-Agent Demonstration (P3)

**Goal**: Demonstration coding agent reaches OpenAI through policy-approved egress with credentials delivered via vault; key never enters the sandbox

**Independent Test**: quickstart V-DEMO — task completes via OpenAI; non-allow-listed egress denied+recorded; key absent from sandbox

- [x] T038 [US5] Create charts/openshell-demo/ gated on `openshell.demo.enabled`: demo sandbox definition (name, harness image from quay.io/aipcc/base-images/agentic/ pinned by tag/digest per FR-005, model/endpoint config references) as application at wave `+2` in values-prod.yaml
- [ ] T039 [US5] *(runtime, one-time)* G0: seed OpenAI API key into vault path `secret/data/hub/openshell-openai`; confirm ExternalSecret `openai-api-key` (ns `openshell`, key `api-key`) syncs and is referenced only by gateway-side provider credential configuration, never sandbox env/mounts per research D8
- [ ] T040 [US5] *(runtime)* Run quickstart V-DEMO: coding task completes using OpenAI through approved egress (SC-009); non-allow-listed egress denied+recorded; proof-of-absence evidence (`openshell sandbox exec -- env`, mounts listing) captured without printing the key

**Checkpoint**: Full governance story demonstrated on a real agent workload

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Envelope proof, rebuild determinism, validation gates, docs

- [ ] T041 *(runtime)* Run quickstart V-SOAK: 3 concurrent sandboxes, churn cycle, `oc get pods -A` shows zero Pending/Evicted platform pods; 4th sandbox rejected by ResourceQuota (SC-007, FR-012)
- [ ] T042 *(runtime)* Run quickstart V-REBUILD: non-cascading delete + full resync of feature applications; gateway Ready on existing PV, credential store intact via vault KEK, sandboxes creatable, ZTWIM trustDomain unchanged (SC-004)
- [ ] T043 Run full validation gates: `make validate-schema`, `make validate-cluster`, `make validate-openshell`, `make argo-healthcheck` — all green (FR-013)
- [x] T044 [P] Update README.md and/or pattern docs with the openshell feature: operator runbook (G0 vault seeding, issuer staging→prod flip, KEK rotation note, port-forward fallback), linking specs/006-openshell-gitops-install/quickstart.md
- [ ] T045 Final sweep of quickstart.md: confirm every V-* recorded as executed (or gap-recorded) and docs/openshell-spiffe-assessment.md is current (living record rule)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none — start immediately
- **Foundational (Phase 2)**: depends on Phase 1 — BLOCKS all stories
- **US1 (Phase 3)**: depends on Foundational — blocks US2 (needs healthy gateway); enables US3/US4/US5
- **US2 (Phase 4)**: depends on US1
- **US3 (Phase 5)**: depends on US1 (gateway exists); parallel-safe with US2/US4 (disjoint files: values-prod.yaml additions in distinct keys, separate charts)
- **US4 (Phase 6)**: depends on US1; parallel-safe with US3 except T035 (touches charts/openshell/values.yaml — sequence after T029 if US3 in flight)
- **US5 (Phase 7)**: depends on US1+US2 (demo runs on enforced sandbox); integrates US4 output when available
- **Polish (Phase 8)**: depends on all implemented stories

### Parallel Opportunities

- Setup: T002, T003, T004 in parallel (different files)
- Foundational tests: T008, T009 in parallel
- US1 tests: T010, T011, T012 in parallel, before implementation (must FAIL first)
- US3 ↔ US4 ↔ US2: independent charts/namespaces; only shared-file edits (values-prod.yaml distinct keys, charts/openshell/values.yaml) need sequencing
- G0 vault seeds (T028, T039) can be done together in one vault session

## Parallel Example: User Story 1

```bash
# Static tests first (parallel), confirm they fail:
test-openshell-render.sh, test-openshell-ordering.sh, test-openshell-pins.sh

# Then implementation sequence:
T013+T014 (agent-sandbox) → T015+T016 (wrapper chart) → T017 (OIDC) → T018 (wiring) → T019 (metrics) → T020/T021 runtime
```

## Implementation Strategy

### MVP First (User Story 1)

1. Phase 1 Setup + Phase 2 Foundational
2. Phase 3 (US1) → validate via G4/V-ORDER/V-AUTH/V-METRICS → **STOP**: platform live via GitOps (SC-001, SC-005, SC-005a)
3. Immediately continue to Phase 4 (US2) — sandboxing enforcement is the other P1

### Incremental Delivery

1. US1+US2 (P1 pair): enforced sandboxing platform, CLI-verifiable
2. US3 (P2): public trusted access — can ship before/without P3 stories
3. US4, US5 (P3): identity groundwork and demo; each independently mergeable
4. Polish: envelope + rebuild proof before calling the feature done

## Notes

**Supersession note 2026-09-24 (specs/007)**: the chart delivery mechanism agreed in this
feature's plan (vendored wrapper chart + copied upstream charts) was identified as fundamentally
flawed and **replaced** by external chart references via the framework's multi-source model
(specs/007-openshell-external-charts). The vendored charts (`charts/openshell`, `charts/agent-sandbox`,
`charts/ztwim-config`, issuers in `cert-manager-config`) were removed; see the 007 contracts for the
current external chart registry and values layout. Everything else in this file's runtime/testing-phase
deferral remains valid.

**Implementation status 2026-09-24**: all repository-side (static) work is complete and green
(`tests/validate-pattern-config.sh`, `make validate-openshell`, `./pattern.sh make validate-schema`).
Per operator direction the live cluster is **not yet designated** — every *(runtime)* task and G0
vault seeding moves to a **separate testing phase** against that cluster:

- Deferred runtime: T020, T021 (US1 bring-up), T024+T025 (US2 egress proof + evidence), T028, T030, T031
  (US3 cert path incl. G0 Cloudflare seed), T036 (US4 V-SPIFFE), T039, T040 (US5 demo), T041
  (V-SOAK), T042 (V-REBUILD), and the cluster-side halves of T043 (`validate-cluster`,
  `argo-healthcheck`; `validate-schema`/`validate-openshell` already green).
- Before the testing phase: replace placeholders in `values-global.yaml` (`dnsZone`, `acmeEmail`)
  and `overrides/values-openshell.yaml` (hostname, OIDC issuer), re-run `tests/test-openshell-values.sh`.
- FR-008 deviation (recorded as research.md F2): no declarative policy source in 0.0.116 —
  policy application is a documented imperative step.
- Readiness gating simplified vs plan: operator CRs converge by Argo CD retry (the
  `lvms-operator-readiness` precedent chart has no templates); sync-wave order unchanged.
- T019 note: gateway ServiceMonitor shipped; supervisor metrics need a stable-port check in
  V-METRICS before adding a PodMonitor (research.md F4).

---

## Phase 9: Convergence (2026-09-24, code-vs-intent assessment)

- [x] T046 CRITICAL Fix KEK secret key: upstream chart requires Secret key `key-encryption-key` (chart `_helpers.tpl`), but charts/openshell-platform renders `kek` — change the ExternalSecret `secretKey`, `kek.field` default, contracts/secrets-contract.md, and tests/test-openshell-secrets.sh expectations per research D4 (contradicts)
- [x] T047 Align ZTWIM CRs to verified operator schemas in charts/ztwim-config/templates/: SpireServer — set a valid `jwtIssuer` (required, https URL, e.g. derived `https://oidc.<trustDomain>`) and drop stray `trustDomain`/`clusterName`; SpireAgent — drop stray `trustDomain`/`clusterName`; ClusterSPIFFEID — drop `workloadSelector.namespace` (absent from Red Hat sample `config/samples/spire.spiffe.io_v1alpha1_clusterspiffeid.yaml`) and verify `spiffeIDTemplate` support in the RH fork per FR-011 (contradicts)
- [x] T048 Add `openshell.ztwim.enabled` toggle (default true) gating: ztwim-config templates, the ZTWIM subscription/namespace entries, and `server.providerTokenGrands.spiffe.enabled` in charts/openshell/values.yaml (computed from the toggle via overrides), so the platform deploys without identity components when ZTWIM is unavailable per FR-011 fallback and US4/AC4 (partial)
- [x] T049 Evaluate migrating policy application to a declarative source (research F2 deviation): if a supported OpenShell release ships declarative/ConfigMap-watched policy, wire charts/openshell-policy to it and remove the documented imperative step per FR-008 (partial)
- [ ] T050 Add a PodMonitor for supervisor metrics if V-METRICS confirms a stable supervisor metrics port on sandbox pods, satisfying the FR-009 "gateway and supervisor" coverage (partial)

---

## Phase 10: Convergence (2026-09-24, second pass)

- [x] T051 Align quickstart.md with the FR-008 imperative deviation (research F2): V-EGRESS step 3 must describe Git as source of truth plus the imperative apply step, and add a `openshell policy update <sandbox> --file ...` row to the Documented imperative steps table (partial)
- [ ] T052 Evaluate retry-based operator-CR convergence during V-ORDER on the designated cluster: if flapping/excessive degraded time is observed, add readiness-gate jobs mirroring the plan's lvms-operator-readiness approach; otherwise record the deviation as accepted (partial)

---

## Original Notes

- [P] tasks touch disjoint files; shared-file edits (values-prod.yaml, charts/openshell/values.yaml) must be sequenced even across stories
- Every *(runtime)* task maps to a quickstart gate/validation — evidence is recorded in Git where the contract demands it (SC-006, secrets-contract rules)
- Vault seeding (T028, T039) and CLI/login actions are the recorded imperative exceptions (Constitution II), enumerated in quickstart.md's imperative-steps table
- Chart 0.0.116 verification checkpoints: T035 (spiffe values existence) and T024 (nftables rule effect) are empirical gates with documented fallbacks — do not skip them
