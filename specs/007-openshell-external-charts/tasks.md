# Tasks: Reference External Charts Instead of Vendoring

**Input**: Design documents from `/specs/007-openshell-external-charts/`

**Prerequisites**: plan.md, spec.md, research.md (D1–D8), data-model.md, contracts/ (external-chart registry, values-layout), quickstart.md

**Tests**: Included — refactor acceptance is suite-proven (spec US2); test-first where suites define the refactor's guardrails (T001 pins, T015–T019 updates must FAIL pre-refactor expectations where applicable).

**Organization**: 2 user stories (US1 P1, US2 P1), both required for an atomic refactor; branch is `006-openshell-gitops-install` (explicit user direction).

## Phase 1: Setup (Acceptance Machinery)

**Purpose**: Define the new guardrails before moving anything

- [x] T001 Write tests/test-external-refs.sh implementing SC-001/SC-002 proofs from specs/007-openshell-external-charts/quickstart.md V-SRC: (a) no upstream chart content under charts/ (no *.tgz, no crds/ dirs, no upstream template signatures), (b) the four ExternalChartRef entries (openshell, agent-sandbox, cert-manager, ztwim) in values-prod.yaml carry EXACT chartVersion pins matching specs/007-openshell-external-charts/contracts/external-chart-contract.md, (c) agent-sandbox pin regex matches immutable tag form (^v\d+\.\d+\.\d+$), (d) each referenced override file in overrides/ exists
- [x] T002 Gate tests/test-external-refs.sh into the Makefile validate-openshell target

---

## Phase 2: Foundational (Values Relocation)

**Purpose**: Move all upstream-chart values into per-app override files — blocks source switching

**⚠️ CRITICAL**: No app-entry rewrite until values files exist

- [x] T003 Create overrides/values-openshell-gateway.yaml with NVIDIA chart ROOT keys (no `openshell.` alias), ported from charts/openshell/values.yaml static pins and the passthrough block in overrides/values-openshell.yaml: image.tag 0.0.116, supervisor (tag 0.0.116, sideloadMethod init-container, topology combined), server (telemetryEnabled false, appArmorProfile Unconfined, disableTls false, credentialStorage.existingSecret openshell-kek, sandboxImage digest pin), agentSandbox.preflight.enabled false, podSecurityContext.fsGroup null, securityContext.runAsUser null, openshiftRoute/certManager + server.oidc + server.providerTokenGrants.spiffe dials from the overrides passthrough (per research.md D4)
- [x] T004 [P] Create overrides/values-agent-sandbox.yaml from charts/agent-sandbox/values.yaml customizations: image.tag v1.0.3, namespace.create false, resources 10m/64Mi req + 500m/128Mi lim, containerSecurityContext seccompProfile RuntimeDefault, controller.extensions false
- [x] T005 [P] Create overrides/values-ztwim.yaml with spire.* per research.md D6: trustDomain from openshell.trustDomain||global.dnsZone (literal placeholder per dial), bundleConfigMap spire-bundle, spire.server CA subject (minilab SPIRE CA / minilab / AU), persistence 2Gi RWO empty storageClass, datastore sqlite3 default, federation disabled, defaultDenyNetworkPolicy.enabled false
- [x] T006 [P] Create overrides/values-certmanager.yaml with certmgrOperator.operatorChannel stable-v1 and a single `acme` ClusterIssuer (email=global.acmeEmail value, server derived from openshell.issuer=staging → acme-staging-v02 URL + letsencrypt-staging-account-key privateKeySecretRef, solvers[0].dns01.cloudflare.apiTokenSecretRef {cloudflare-api-token, api-token}, selector.dnsZones[global.dnsZone value]) per research.md D5 and contracts/values-layout-contract.md
- [x] T007 Remove the top-level `openshell:` passthrough block from overrides/values-openshell.yaml (keep global.openshell.* dials only)

---

## Phase 3: User Story 1 - Upstream Charts Referenced, Not Copied (P1) 🎯 MVP

**Goal**: Application entries reference pinned external sources; zero upstream chart content remains in the repo

**Independent Test**: quickstart V-SRC steps 1–2 (charts/ census + exact pins) pass on the refactored tree

- [x] T008 [US1] Rewrite the `openshell` application entry in values-prod.yaml: `chart: helm-chart`, `chartVersion: "0.0.116"`, `repoURL: ghcr.io/nvidia/openshell`, `path` removed, `extraValueFiles: ['/overrides/values-openshell-gateway.yaml']`, keep namespace openshell and sync wave "0" (per research.md D2/D7)
- [x] T009 [US1] Rewrite the `agent-sandbox` application entry in values-prod.yaml: `repoURL: https://github.com/kubernetes-sigs/agent-sandbox`, `path: helm`, `chartVersion: v1.0.3`, `extraValueFiles: ['/overrides/values-agent-sandbox.yaml']`, keep wave "-5"
- [x] T010 [US1] Rewrite cert-manager composition in values-prod.yaml + charts/cert-manager-config/: application `cert-manager` with `chart: ocp-certmanager`, `chartVersion: "0.2.0"`, `extraValueFiles: ['/overrides/values-certmanager.yaml']` at wave "-6"; strip charts/cert-manager-config/templates/clusterissuers.yaml (issuers now from VP chart) leaving ONLY cloudflare-token-es.yaml, and move the app's wave to "-7"
- [x] T011 [US1] Rewrite the `ztwim` composition: application `ztwim` with `chart: ztwim`, `chartVersion: "0.1.1"`, `extraValueFiles: ['/overrides/values-ztwim.yaml']` at wave "-4" in values-prod.yaml; move charts/ztwim-config/templates/cluster-spiffe-id.yaml into charts/openshell-platform/templates/ (it is pattern-owned workload registration)
- [x] T012 [US1] Create charts/openshell-extras/ (Chart.yaml v0.1.0, templates/oauthclient.yaml + router-ca-rbac.yaml + router-ca-fetch-job.yaml moved verbatim from charts/openshell/templates/, values.yaml with global.openshell.enabled=false lint default) and wire application `openshell-extras` in values-prod.yaml (path charts/openshell-extras, wave "-1")
- [x] T013 [US1] `git rm -r charts/openshell charts/agent-sandbox charts/ztwim-config` (all vendored upstream content; FR-001)
- [x] T014 [US1] Update ztwim ClusterSPIFFEID ztwim-toggle gating in charts/openshell-platform/templates/ to keep the `and openshell.enabled ztwim.enabled` guard, and confirm charts/cert-manager-config templates still gated on openshell.enabled

**Checkpoint**: V-SRC steps 1–2 green; repository contains only pattern-owned charts

---

## Phase 4: User Story 2 - Framework-Native Composition Preserves Behavior (P1)

**Goal**: All previously-proven static properties hold under the new source model

**Independent Test**: `make validate-openshell`, `tests/validate-pattern-config.sh`, `./pattern.sh make validate-schema` all green (quickstart G1)

- [x] T015 [US2] Rewrite tests/test-openshell-render.sh as merged-values assertions per contracts/values-layout-contract.md (dial⇄override map): yq/py merge of values-global.yaml + each override file; assert dial consistency (gatewayHostname⇔route.host+serverDnsNames[0], issuer⇔acme.server+account key name, ztwim.enabled⇔spiffe.enabled, trustDomain⇔spire.trustDomain, dnsZone⇔dnsZones[0], acmeEmail⇔acme.email) and NVIDIA static pins present in overrides/values-openshell-gateway.yaml (telemetry off, preflight off, sideload pinned, KEK secret name, SCC nulls)
- [x] T016 [P] [US2] Update tests/test-openshell-values.sh: keep dial validators; add failure assertion when a top-level `openshell:` passthrough key reappears in overrides/values-openshell.yaml (superseded layout, per contract)
- [x] T017 [P] [US2] Rewrite tests/test-openshell-pins.sh: floating-tag scan across overrides/values-*.yaml and values-prod.yaml; assert the four ExternalChartRef chartVersion fields are exact (no `*`, no `latest`); drop Chart.lock/tgz checks (no vendored charts remain)
- [x] T018 [P] [US2] Downscope tests/test-openshell-ztwim.sh: retain ClusterSPIFFEID shape asserts (k8sServiceAccount openshell/openshell-sandbox, integer ttl, no workloadSelector.namespace) and the ztwim.enabled=false → zero ztwim-namespaced renders guard for charts/openshell-platform; drop upstream-CR schema asserts now owned by the VP chart
- [x] T019 [P] [US2] Update tests/test-openshell-secrets.sh (paths unchanged; verify renders reference the new chart set), tests/test-openshell-quota.sh (unchanged expectations), tests/test-openshell-ordering.sh (expected wave list: cert-manager-config -7, cert-manager -6, agent-sandbox -5, ztwim -4, openshell-platform -3, openshell-extras -1, openshell 0, openshell-policy +1, openshell-demo +2), and tests/validate-pattern-config.sh chart lint list (swap charts/openshell→charts/openshell-extras, drop charts/agent-sandbox and charts/ztwim-config)
- [x] T020 [US2] Run the full gate set: `make validate-openshell`, `tests/validate-pattern-config.sh`, `./pattern.sh make validate-schema` — all green
- [x] T021 [P] [US2] Run the optional online smoke: `helm template openshell oci://ghcr.io/nvidia/openshell/helm-chart --version 0.0.116 -f overrides/values-openshell-gateway.yaml` renders gateway StatefulSet + passthrough Route (records quickstart V-SRC step 4 as executed)

**Checkpoint**: All previously-proven properties still hold; refactor is behavior-preserving

---

## Phase 5: Polish & Cross-Cutting

**Purpose**: Docs truthfulness and PR hygiene

- [x] T022 [P] Update README.md openshell section: external chart sourcing model (+ link to contracts/external-chart-contract.md bump runbook), remove wrapper-chart/vendoring references, `acme` issuer flip semantics
- [x] T023 [P] Update docs/openshell-spiffe-assessment.md pointers: ZTWIM operand config now via VP `ztwim` chart 0.1.1 (registry row), workload registration in charts/openshell-platform
- [x] T024 Update specs/006-openshell-gitops-install/tasks.md implementation-status note: superseded approach recorded (vendored wrapper copied upstream charts → replaced by 007 external sourcing); no other 006 artifact edits
- [x] T025 Final re-run of all gates from T020, commit refactor to 006-openshell-gitops-install, and update PR #6 body summarizing the external-sourcing refactor

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: immediate
- **Foundational (Phase 2)**: after Setup — BLOCKS US1
- **US1 (Phase 3)**: after Foundational — values-prod edits in ONE file are SEQUENCED (T008→T009→T010→T011); T013 deletions only after T008–T012 land (suites/media must not break mid-way less critically but keeps tree sane)
- **US2 (Phase 4)**: after US1 — suites rewritten against the new tree
- **Polish (Phase 5)**: after US2 — final docs and PR update

### Parallel Opportunities

- T004+T005+T006 (independent override files) in parallel
- T016–T019 (independent test files) in parallel after T015 defines the assertion style
- T022+T023 (independent docs) in parallel

## Implementation Strategy

### MVP

Phases 1–2 alone are not shippable (tree half-referenced); the true atomic MVP is **US1 complete + quickstart V-SRC 1–2 green**. US2 then proves equivalence; ship after Phase 4 gates all green.

### Incremental Delivery

1. Setup machinery → 2. Values relocated (tree still renders identically: old sources remain) → 3. Switch sources + delete vendored content → 4. Prove equivalence → 5. Docs + PR refresh

## Notes

- All work lands on branch `006-openshell-gitops-install` per user direction; commits append to the existing PR #6
- The 006 chart `openshell-extras` (T012) is pattern-owned (our OAuth/CA integration), NOT an upstream copy — same for openshell-platform/policy/demo and the slimmed cert-manager-config: FR-001 is satisfied even though local charts remain
- VP community charts are external upstreams under FR-003; their own CI covers internal correctness — our suites assert OUR values wiring, not their templates
- Offline `helm template` of external sources is NOT a gate (would force local fetches); online smoke row in V-SRC step 4 covers render sanity pre-testing-phase

---

## Phase 6: Convergence (2026-09-26)

- [x] T026 Add hermetic `global.openshell.ztwim.enabled=false` default to charts/openshell-platform/values.yaml so the chart renders safely on its own dials (enabled=true without the toggle set must no-op, not nil-pointer) per FR-002 / data-model PatternOwnedChart hermeticity (partial)
- [x] T027 Clean the dead typo condition (`agent-sandbox-rc`) in the charts census of tests/test-external-refs.sh — the predicate should flag any crds/ directory (or upstream CRD content) without the vestigial branch per SC-003 (partial)
