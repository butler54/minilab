# Quickstart: Validate Observability Overrides

## Prerequisites

- The repository with the observability feature (`charts/observability-config`) present.
- `helm` and `yq` on `PATH`.

## Relocation Validation

1. Record the current rendered output before any change:
   ```bash
   helm template observability-config charts/observability-config -f values-global.yaml > /tmp/before.yaml
   ```
2. Confirm `values-global.yaml` no longer contains the observability block:
   ```bash
   yq e '.global.observability' values-global.yaml   # expect: null
   ```
3. Confirm the override file exists and holds the observability surface:
   ```bash
   yq e '.global.observability' overrides/values-observability.yaml
   ```
4. Confirm the override is wired through shared-value-files:
   ```bash
   yq e '.clusterGroup.sharedValueFiles' values-prod.yaml   # must list /overrides/values-observability.yaml
   ```
5. Re-render and diff against the baseline (rendered output must be equivalent):
   ```bash
   helm template observability-config charts/observability-config -f values-global.yaml > /tmp/after.yaml
   ```
   The chart defaults supply the same values, so the rendered observability resources are unchanged.

## Precedence Validation

1. Render with an operator-explicit value overriding an observability setting and confirm it takes precedence (mirrors `tests/test-vault-storage-override.sh`).
2. Run the dedicated relocation/precedence test:
   ```bash
   tests/test-observability-override.sh
   ```

## Regression Validation

1. Run the existing validation and observability suites:
   ```bash
   tests/validate-pattern-config.sh
   tests/test-observability-dashboards.sh
   tests/test-observability-alerts.sh
   tests/test-observability-configurability.sh
   tests/test-observability-rbac.sh
   ```

For the override file fields and precedence model, see [data-model.md](data-model.md) and [observability-override.md](contracts/observability-override.md).

## Target-Cluster Results

Unchecked: target-cluster validation has not been run from this workspace. Confirm on the target OpenShift 4.22 cluster that `make install` applies the observability override via `sharedValueFiles` and the `Observe > Dashboards (Perses)` experience is unchanged from the pre-relocation configuration.
