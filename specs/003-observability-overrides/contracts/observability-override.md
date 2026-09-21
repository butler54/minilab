# Observability Override Contract

## Values Interface

| Value | Contract |
|-------|----------|
| `overrides/values-observability.yaml` | Holds the complete `global.observability` block; the single operator-facing location for observability settings. |
| `values-global.yaml` | Must NOT contain `global.observability` after this feature. |
| `values-prod.yaml` `clusterGroup.sharedValueFiles` | Must list `/overrides/values-observability.yaml` so it applies automatically at install. |

## Precedence Contract

| Layer (later wins) | Source |
|--------------------|--------|
| Chart defaults | `charts/observability-config/values.yaml` |
| Observability override | `overrides/values-observability.yaml` (via `sharedValueFiles`) |
| Operator-explicit | a later `extraValueFiles` entry selected by the operator |

## Relocation Invariants

| Invariant | Verification |
|-----------|--------------|
| Rendered observability resources are byte-equivalent before and after | `helm template observability-config charts/observability-config -f values-global.yaml` before vs. after relocation |
| `values-global.yaml` has no `global.observability` key | `yq e '.global.observability' values-global.yaml` returns null |
| The override file is listed in `sharedValueFiles` | `yq e '.clusterGroup.sharedValueFiles' values-prod.yaml` contains `/overrides/values-observability.yaml` |
| Existing validation passes unchanged | `tests/validate-pattern-config.sh` and `tests/test-observability-*.sh` |
