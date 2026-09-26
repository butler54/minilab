# Contract: Values Layout & Drift Guards

**Feature**: `007-openshell-external-charts` | **Phase 1 artifact**

## Layer rules

1. **Feature dials** (`overrides/values-openshell.yaml`, `global.openshell.*` + `global.dnsZone/acmeEmail`) — the ONLY operator-facing knobs; unchanged contract from 006 (plus `ztwim.enabled`).
2. **App override files** (`overrides/values-{openshell-gateway,agent-sandbox,ztwim,certmanager}.yaml`) — upstream-chart-native values, one file per external chart, consumed via each app's `extraValueFiles`. Operator-editable but dial-derived values inside them MUST BE PROVEN CONSISTENT with feature dials (below).
3. **Chart-internal defaults** — anything not listed above comes from the upstream chart's own defaults and is NOT restated anywhere in this repo.

## Dial ⇄ override consistency map (test-asserted)

| Feature dial | Asserted against | Rule |
|--------------|------------------|------|
| `openshell.gatewayHostname` | gateway override `openshiftRoute.host`, `certManager.serverDnsNames[0]` | equal |
| `openshell.issuer` | certmanager override `certmgrOperator.issuers[0].acme.server` AND `.privateKeySecretRef.name` | staging⇔staging URL + `letsencrypt-staging-account-key`; prod⇔prod URL + `letsencrypt-prod-account-key` |
| `openshell.ztwim.enabled` | gateway override `server.providerTokenGrants.spiffe.enabled` | `ztwim.enabled=false` ⇒ spiffe `false`; `true` ⇒ `true` |
| `openshell.trustDomain` (default `dnsZone`) | ztwim override `spire.trustDomain` | equal to dial-or-`dnsZone` |
| `global.dnsZone` | certmanager override `acme.solvers[0].selector.dnsZones[0]` | equal |
| `global.acmeEmail` | certmanager override `acme.email` | equal |
| `openshell.demo.enabled` | unchanged (demo is a local chart) | n/a |

## Deprecated / removed

- `overrides/values-openshell.yaml`'s top-level `openshell:` passthrough block (006) — **removed**; upstream keys moved into `values-openshell-gateway.yaml` at values root. Any leftover `openshell.openshiftRoute`/`openshell.server` keys in this file fail the values test.
- `charts/openshell/` wrapper chart with vendored OCI dependency and its `README.md` update procedure — superseded by this contract; `make validate-openshell` suites no longer reference it.
