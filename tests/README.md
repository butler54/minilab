# Tests

Shell-based validation harness for the pattern. Every static test runs exactly
once, in sorted order, via:

```sh
make test-static
```

The gate auto-discovers `tests/test-*.sh` and `tests/validate-pattern-config.sh`,
excluding live probes and environment-dependent checks (listed below).
Domain subsets remain available: `make validate-observability`,
`make validate-openshell`, plus `make validate-schema` (containerized via
`./pattern.sh`).

## Live probes (excluded from test-static)

Run against a reachable cluster via `make test-live` (skips gracefully when the
cluster is unreachable):

- `test-owner-collision.sh` — FR-001 regression check (feature 010): fails if any
  GitOps-tracked Deployment collides with an OLM CSV-owned Deployment. Live-only;
  reads CSVs and Deployments via `oc`, never mutates.
- `test-openshell-auth-smoke.sh` — Keycloak OIDC + gateway auth smoke (also:
  `make validate-openshell-live`).

## Environment-dependent (excluded)

- `check-openshell-cli.sh` — asserts the installed openshell CLI matches the
  chart-pinned version (use `make check-openshell-cli` / `install-openshell-cli`).

## Feature 010 additions

- `test-owner-collision.sh` (live, above)
- `test-argocd-cadence.sh` — asserts `values-global.yaml` pins
  `main.gitops.customArgoYaml` with `timeout.reconciliation: 600s` and preserves
  the gitops channel/operatorSource baseline.
- `test-monitoring-config.sh` — asserts the `openshift-monitoring-config` chart is
  registered, renders exactly one scoped ConfigMap
  (`prometheusK8s.collectionProfile: minimal` and nothing else), and that
  `global.observability.scrapeInterval: 60s` lands on external ServiceMonitors.

## Conventions

- Tests are executable bash, `set -euo pipefail`, one line of output on success,
  exit non-zero with a specific message on failure.
- Static tests use helm template / yq / python3-yaml assertions; they must not
  require a cluster or cloud credentials.
- Makefile enumerates tests via `STATIC_TESTS := $(filter-out …)` in `Makefile`;
  add a new test file and it joins `make test-static` automatically unless it
  needs a cluster (add to `LIVE_TESTS`) or a local tool (add to `ENV_TESTS`).
