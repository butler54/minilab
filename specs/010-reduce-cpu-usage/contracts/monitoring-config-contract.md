# Contract: Platform Monitoring Configuration

Home of truth: `charts/openshift-monitoring-config/` (new local chart, own
application entry in `values-prod.yaml`).

## Rendered-object contract

Exactly one object — ConfigMap `cluster-monitoring-config`, `openshift-monitoring`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      collectionProfile: minimal
```

## Validation

- `tests/test-monitoring-config.sh`: `helm template` of the chart renders the
  ConfigMap above byte-for-byte modulo YAML ordering; asserts
  `prometheusK8s.collectionProfile == minimal` is set and no other CMO key is
  present (scope discipline — do not accidentally claim ownership of
  `enableUserWorkload` or `telemeterClient`).
- CMO field support verified against `release-4.22` CMO `Documentation/api.md`
  (`PrometheusK8sConfig.collectionProfile`; research.md D3).

## Continuation guarantees (what "minimal" preserves per CMO contract)

- Default platform alert rules remain evaluated and firing-capable.
- Recording rules and telemetry keep flowing.
- Console dashboards (Observe → Overview etc.) continue to render.
- Scrape cadence of retained metrics stays at factory 30s (control-plane
  alerts remain timely — spec edge case).

## Related cadence contract (pattern-owned stack)

`global.observability.scrapeInterval: 60s` renders into each external-target
`ServiceMonitor` endpoint by `charts/observability-config`. The user-requested
"60s" applies here exactly; platform Prometheus uses the profile switch above
because OCP 4.22's CMO exposes no platform scrape-interval field (research.md D3).
