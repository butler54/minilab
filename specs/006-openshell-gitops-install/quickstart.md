# Quickstart: Validation Guide — OpenShell GitOps Platform

**Feature**: `006-openshell-gitops-install` | Run on the minilab SNO cluster (OCP 4.22)

Runnable validation proving the feature end-to-end, mapped to the spec's Success Criteria. This is a **runbook, not implementation docs** — tasks.md owns build steps. Commands are indicative; exact names solidify during implementation.

## Gates (ordered)

| Gate | Action | Proves |
|------|--------|--------|
| G0 Seed | Create vault keys from `contracts/secrets-contract.md` (`secret/data/hub/openshell-{cloudflare,gateway-kek,openai}`) | FR-010 prerequisites exist |
| G1 Lint | `make validate-schema` | values contract validity |
| G2 Static tests | `tests/test-openshell-*.sh` (render, ordering, pin checks) | chart correctness, wave ordering |
| G3 Cluster checks | `make validate-cluster` | cluster-side preconditions |
| G4 Sync | Apply pattern with `openshell.enabled=true`, `openshell.issuer=staging`; `make argo-healthcheck` | SC-001, SC-005 |

## V-ORDER — dependency ordering (SC-001)

1. Fresh cluster (or `openshell` namespace absent) → apply pattern → **no manual `oc`/`kubectl` mutation**.
2. Expect, in order: agent-sandbox controller `Running` (`oc -n agent-sandbox-system get deploy`), cert-manager CSV `Succeeded`, ZTWIM CSV `Succeeded`, then OpenShell applications `Healthy/Synced`.
3. Record any wave breach (e.g. gateway rendered before CRDs served) as a test failure.

## V-TLS — certificate path (SC-008)

1. `oc get clusterissuer letsencrypt-staging -o jsonpath='{.status.conditions}'` → `Ready=True`; repeat for `letsencrypt-prod`.
2. `oc -n openshell get certificate` → external cert `Ready=True`, SAN = `<openshell.gatewayHostname>`.
3. From a stock workstation (no custom CA): `openssl s_client -connect <hostname>:443 -servername <hostname>` → verified chain. **With `issuer=staging` this MUST fail validation (expected — staging CA is untrusted); with `issuer=prod` it MUST verify.**
4. Flip `openshell.issuer: prod` → cert reissues → workstation verification passes. Renewal: force-renew (`cmctl renew` or delete Certificate → recreated Ready) once to prove the loop.
5. Gateway serves INTERNAL cert to supervisors meanwhile: sandbox startup working during external staging phase proves the SNI split (research D2).

## V-AUTH — user authentication ✅ DONE 2026-09-27 (Keycloak + device flow)

Implemented via RHBK Keycloak (rh-keycloak app) federating GitHub login; OpenShift
OAuth was disqualified (OAuth2-only, no OIDC discovery/JWKS). Flow:
`OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` (device flow — RHBK 26.6
rejects all redirect URIs; known-issue probe in tests/test-openshell-auth-smoke.sh
flips loud once fixed). Post-first-login: operator grants `openshell-admin` to the
operator account manually (admin REST or KC console). Encoded offline in
tests/test-keycloak-realm.sh and live in tests/test-openshell-auth-smoke.sh.

## V-EGRESS — kernel-enforced policy (SC-002, SC-003) ✅ DONE 2026-09-27 (openshell 0.1.1)

1. Time G4 → first sandbox running a command: `openshell sandbox create --name v1 && openshell sandbox exec ...` → must be **< 5 min** using docs steps only.
   Note (0.1.1): a policy-less sandbox never leaves `Provisioning` — submit any policy to flip it Ready.
2. In the sandbox: `openshell sandbox exec -n v1 -- curl https://example.com` → connection refused (rc 7); supervisor OCSF logs show `NET:OPEN DENIED` for the attempt (`oc -n openshell logs <os-supervisor-pod>`).
3. Apply the policy from Git: `openshell policy set v1 --policy charts/openshell-policy/policies/sample-openai-only.yaml --wait` → `curl https://api.openai.com` returns upstream HTTP (421 observed at the OpenAI edge = transport+TLS reached upstream), `example.com` still DENIED.
   PROVEN 0.1.1 facts (differ from upstream docs):
   - Every egress rule needs a non-empty `binaries` list — the supervisor OPA runs `require_binary_identity: true`; missing binaries = silent deny-all for that rule.
   - `binaries[].path` is the kernel-resolved /proc/<pid>/exe path, not a symlink, never argv[0].
   - `--add-endpoint` bare `host:port` shorthand does NOT produce a usable rule on 0.1.1; use a full policy YAML via `policy set`.
4. Mediation is seccomp-notification based (agent relays connect(2) decisions to the supervisor); no nftables/route programming exists in the K8s driver — verification = supervisor OCSF `NET:OPEN DENIED/ALLOWED` events, not node-level iptables.
5. 100% denial rate for non-allow-listed destinations across the recorded attempts (example.com, google.com — rc 7).

## V-SPIFFE — ZTWIM integration (SC-006, FR-011)

1. `oc describe csv -n zero-trust-workload-identity-manager` → GA operator installed; `ZeroTrustWorkloadIdentityManager`, `SpireServer`, `SpireAgent`, `SpiffeCSIDriver` CRs Ready.
2. SVID issuance: pod matching the `ClusterSPIFFEID` mounts the `csi.spiffe.io` socket and can fetch an identity (per ZTWIM docs' workload example).
3. OpenShell consumable point: with `server.providerTokenGrants.spiffe` enabled, the demo sandbox calls OpenAI **with no API key anywhere in the sandbox** (env, files, args) — prove via `openshell sandbox exec -- env` and mounts listing.
4. Record results in `docs/openshell-spiffe-assessment.md` (contract: `contracts/ztwim-assessment.md`), including any verified-deferred rows + re-evaluation triggers.

## V-METRICS — monitoring integration (SC-005a, FR-009)

1. ServiceMonitor reconciled; within one scrape interval of gateway Ready, platform Prometheus answers `up{service=~".*openshell.*"}` → 1.
2. OCSF events remain CLI-served only: `openshell term` shows ALLOWED/DENIED; nothing ships into cluster logging (out of scope).

## V-DEMO — governed coding agent (SC-009)

1. `openshell.demo.enabled=true` synced; demo harness image pinned by tag/digest (FR-005).
2. Run a small coding task in the demo sandbox; OpenAI calls succeed (provider token injected gateway-side — key absent from sandbox per V-SPIFFE step 3).
3. Random non-allow-listed egress from the same sandbox → denied+recorded (V-EGRESS machinery).

## V-SOAK — capacity envelope (SC-007, FR-012)

1. Run **3 concurrent sandboxes** (quota ceiling = `openshell.sandbox.maxConcurrent`).
2. During steady state + churn (delete/recreate cycle): no Pending/evicted pods among: openshift-gitops, external-secrets, minilab-observability, cert-manager, ZTWIM, openshell (`oc get pods -A | grep -E 'Pending|Evicted'` must stay empty).
3. `oc describe quota -n openshell` shows enforcement active (4th sandbox must fail quota).

## V-REBUILD — determinism (SC-004)

1. `argocd app delete` the feature's applications (non-cascading on namespaces) → `argocd app sync` full → platform returns: gateway Ready (existing `openshell-data` PVC reattached; KEK from vault so stored credentials survive), sandboxes creatable, TLS valid.
2. ZTWIM trustDomain unchanged (immutable); SPIRE datastore PV persists identities.

## Documented imperative steps (Constitution II record)

| Step | Why imperative | Location recorded |
|------|----------------|-------------------|
| Seed vault keys (G0) | Secrets cannot originate in Git | this file, G0 |
| `openshell gateway add/login` | CLI registers against live gateway; local workstation state | V-AUTH |
| `openshell sandbox create/exec/term` | Runtime use of the platform, not configuration | V-*, V-DEMO |
| `openshell policy update <sandbox> --file <policy.yaml> --wait` | Upstream 0.0.116 has no declarative policy consumer (research F2); Git (`charts/openshell-policy/`) remains the source of truth | V-EGRESS, charts/openshell-policy/README.md |
| cert-manager controller restart IF issuer stale | operand ≤1.21.0 solver-validation caveat (research D6) | V-TLS note |

Each is idempotent, documented, and leaves cluster desired state unchanged (or, for vault seeding, feeds ExternalSecret-managed material).
