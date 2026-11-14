# Contract: Acceptance Suite

**Feature**: 014-ocp501-openshell-upgrade | **System under test**: OpenShell 0.1.8 on the 5.0.1-aligned operator layer | **Consumer**: `/speckit.tasks`, implementation, `/speckit.converge`

The acceptance suite is the behavior contract for "behaviour is as expected" (user story 3, FR-007/FR-008, SC-004). Each stage MUST be executed and recorded as an `AcceptanceStageResult` (see [data-model.md](../data-model.md)); no stage may be skipped or weakened — the demo target's built-in skip conditions (cluster unreachable, gateway auth missing) count as a FAIL during acceptance, not a skip.

## Stages

| # | Stage | Command | Pass criteria |
|---|---|---|---|
| 1 | `static-suite` | `make test-static && make validate-openshell` | exit 0 — all shell tests incl. updated lvms + openshell pin assertions |
| 2 | `schema` | `./pattern.sh make validate-schema` | exit 0 |
| 3 | `cli-tie` | `make check-openshell-cli` | exit 0; CLI reports 0.1.8 == chart pin (check unmodified) |
| 4 | `convergence` | `make argo-healthcheck && make validate-cluster` | all Argo CD applications Synced+Healthy within 15 min of final push; zero OutOfSync applications; OLM no-op copy-status PUT posture unchanged from the 010 baseline (<1/s, measured 0.21/s) |
| 5 | `auth-smoke` | `make validate-openshell-live` | Keycloak OIDC login + gateway status succeed end-to-end |
| 6 | `demo-smoke` | `DEMO_PROMPT="Reply with exactly: OPENSHELL_VDEMO_OK" make validate-openshell-demo` | sandbox created, expected prompt exchange succeeds, teardown clean — with **no skip message emitted** |
| 7 | `sandbox-lifecycle` | manual: create sandbox (policy at create), verify policy effect (allowlisted egress succeeds / non-allowlisted denied), `openshell sandbox list` → delete → re-list | policy active from first operation; zero sandboxes/forwards after teardown |

## 0.1.8 behavior deltas the suite MUST account for

From [research.md](../research.md) §3 — these are the "expected behavior" changes acceptance verifies against:

1. OCSF events are 1.8.0-only; sandbox attribution uses `device.container.*` (supervisor) / `resources[]` (gateway) — any evidence parsing updated accordingly.
2. Filesystem policy paths that traverse a symlink inside a writable workspace now fail sandbox launch — demo policies audited and rewritten to target paths BEFORE the run.
3. IPv4-mapped IPv6 endpoint rules (`::ffff:a.b.c.d`) are invalid — demo policies use plain IPv4/hosts.
4. HTTP upgrade requests over REST get 403 — only relevant if a flow uses WebSockets (none known; verify).
5. `openshell status --gateway <name>` exits non-zero for unregistered gateways — scripts using it as preflight expect the new semantics.
6. `openshell gateway login` run once after upgrade replaces older SDK/CLI token files (also mitigates minilab#9 expiry).
7. Faster sandbox teardown on Kubernetes (no 30s grace wait) — lifecycle timings tighten; teardown verification must not assume the old delay.

## Recording

Each stage's result goes into `review-log.md` (acceptance-evidence section) as: stage, command, outcome (`pass` | `fail→fixed→pass` | `fail→documented`), and evidence (output capture or pointer). A `fail` MUST become `fail→fixed→pass` (Git fix + re-run) or `fail→documented` (root cause + upstream reference) before the feature completes; the pin-revert threshold is the decided rollback policy (platform unusable: auth or sandbox lifecycle broken).
