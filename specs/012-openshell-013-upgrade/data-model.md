# Data Model: OpenShell 0.1.3 Upgrade

Infrastructure feature (no data structures persisted). The "entities" are
Git-declared pin values plus the three runtime-facing files that reference them.

## Entity: VersionPinSet

| Field | Type | Where | Valid values |
|---|---|---|---|
| chartVersion | semver string | `values-prod.yaml` → `clusterGroup.applications.openshell.chartVersion` | exact version, must equal image tags |
| gateway.image.tag | semver string | `overrides/values-openshell-gateway.yaml` | == chartVersion (drift-asserted by tests) |
| sandboxRuntime.image.tag | semver string | `overrides/values-openshell-gateway.yaml` | == chartVersion |
| supervisor.image.tag | semver string | `overrides/values-openshell-gateway.yaml` | == chartVersion |
| CLI version | semver string | workstation binary (PATH-resolved) | == chartVersion (enforced by `tests/check-openshell-cli.sh`) |

**Invariants**: all five values identical; updates are atomic in one commit;
nothing floats (no `latest`, no minor-version ranges) — asserted by
`tests/test-openshell-pins.sh` and `tests/test-external-refs.sh`

## Entity: ArgoCDConvergence

| Field | Type | Notes |
|---|---|---|
| applications | list | `openshell` (+ deps: `openshell-keycloak-config`, `openshell-policy`, `openshell-platform`, `openshell-demo`) in ns `vp-gitops` |
| sync trigger | event | `argocd.argoproj.io/refresh=hard` annotation + spec.operation sync patch (oc, recorded) |
| terminal state | enum | `Synced` + `Healthy` (all openshell apps) within <= 15 min |
| failure rollback | action | revert pin commit on `main`, re-sync |

## Entity: PolicyAtCreateProof (US3 evidence)

| Field | Type | Notes |
|---|---|---|
| create command | string | `openshell sandbox create --policy <zen-demo.yaml> --from ghcr.io/butler54/openshell-sandbox:latest --detach` |
| admission | enum | `accepted` from birth (never `rejected`) — key assertion |
| policy_version | int | `>= 1` from birth (from `openshell sandbox get -o json`) |
| first_op_behavior | string | first exec honors policy (e.g., github.com sinkhole deny, opencode.ai allowed-or-denied per policy) — evidence of policy-active-from-birth |
| teardown | boolean | sandbox deleted; `openshell sandbox list` empty |

## Entity: TrackingArtifact (Git)

| Field | Type | Notes |
|---|---|---|
| issue | URL | butler54/minilab#8 |
| evidence log | path | `specs/012-openshell-013-upgrade/demo-log.md` |
| runbook updates | path | `docs/openshell-demo-opencode.md` |

## Relationships

VersionPinSet → ArgoCDConvergence (chart triggers rollout);
CLI version ←version-tie→ chartVersion;
PolicyAtCreateProof depends on ArgoCDConvergence terminal state + CLI 0.1.3;
all evidence accumulated into TrackingArtifact (main-branch commits).
