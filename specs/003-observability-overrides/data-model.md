# Data Model: Observability Overrides

## Observability Override File

| Field | Meaning | Validation |
|-------|---------|------------|
| `global.observability.enabled` | Enable/disable the whole observability configuration | boolean |
| `global.observability.cooNamespace` | COO operator namespace | string |
| `global.observability.stackNamespace` | Namespace hosting the stack, dashboards, alert resources | string |
| `global.observability.retention` | Time-series retention for the stack | duration string, e.g. `30d` |
| `global.observability.storageClass` | PVC class for stack persistence | string |
| `global.observability.externalTargets` | External HTTP/HTTPS exporter endpoints | list of `{url, labels?}` |
| `global.observability.dashboards` | Additional `PersesDashboard` definitions | list of `{name, title, panels[]}` |
| `global.observability.alertRules` | Additional `PrometheusRule` definitions | list of `{name, rules[]}` |
| `global.observability.rbac.viewerGroup` / `editorGroup` | OpenShift groups granted Perses roles | string (empty = no binding) |

**Lifecycle**: Declared in `overrides/values-observability.yaml` -> applied via `sharedValueFiles` at install -> merged over chart defaults -> reconciled by Argo CD. An operator-explicit `extraValueFiles` entry later in the list overrides it.

## Configuration Location Model

| File | Role |
|------|------|
| `charts/observability-config/values.yaml` | Chart defaults (baseline for standalone render) |
| `overrides/values-observability.yaml` | Operator-facing observability settings (this feature's addition) |
| `values-global.yaml` | Pattern-wide defaults only; no observability settings after this feature |
| `values-prod.yaml` | `clusterGroup.sharedValueFiles` wiring that applies the override |

**Relationship**: One override file holds one concern (observability), applied by the same mechanism as the storage override. The chart defaults, the override file, and any operator `extraValueFiles` merge with later entries taking precedence.
