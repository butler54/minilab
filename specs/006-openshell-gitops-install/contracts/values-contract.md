# Contract: Operator-Facing Values Surface

**Feature**: `006-openshell-gitops-install` | **Phase 1 artifact**

The complete configuration surface this feature adds to the pattern. Everything not listed here is defaulted inside the feature's charts and is NOT operator-tunable (per Constitution IV — keep the dial count minimal).

## `values-global.yaml` additions

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `global.dnsZone` | string (DNS zone) | yes | — | Operator-owned public zone hosted at Cloudflare (e.g. `example.com`). Used for issuer zone selector and trust domain default. |
| `global.acmeEmail` | string (email) | yes | — | Let's Encrypt registration contact. |

## `values-prod.yaml` additions (`clusterGroup` level)

| Key | Type | Required | Default | Description |
|-----|------|----------|---------|-------------|
| `openshell.enabled` | bool | yes | `false` | Master switch: when true, renders all feature subscriptions/applications (agent-sandbox, cert-manager, ZTWIM, openshell platform, demo). |
| `openshell.gatewayHostname` | string (FQDN) | yes | — | Public gateway hostname. MUST end with `global.dnsZone`. Rendered into `openshiftRoute.host` and `certManager.serverDnsNames[0]`. |
| `openshell.issuer` | `staging` \| `prod` | no | `staging` | Which ClusterIssuer the gateway's external certificate uses. Flip to `prod` only after staging issuance is proven (see quickstart V-TLS). |
| `openshell.trustDomain` | string | no | value of `global.dnsZone` | ZTWIM SPIFFE trust domain. **Immutable after first reconcile** — changing it requires the recreation runbook in quickstart. |
| `openshell.sandbox.maxConcurrent` | int (1–5) | no | `3` | Sandbox capacity envelope. Sizes the `openshell` namespace ResourceQuota (SC-007). |
| `openshell.ztwim.enabled` | bool | no | `true` | Deploy SPIFFE identity components. Set `false` (FR-011 fallback) to skip them: also comment out the `ztwim` subscription + namespace in `values-prod.yaml` and set passthrough `openshell.server.providerTokenGrants.spiffe.enabled: false` (drift asserted by `tests/test-openshell-values.sh`). |
| `openshell.demo.enabled` | bool | no | `false` | Render the demonstration coding-agent assets (FR-014). |

## Validation rules (enforced by `make validate-schema` + chart asserts)

1. `openshell.enabled=true` ⇒ `openshell.gatewayHostname` is set and ends with `global.dnsZone` — otherwise the chart fails template rendering with a clear message.
2. `openshell.sandbox.maxConcurrent` must be an integer between 1 and 5 inclusive.
3. `openshell.issuer` accepts exactly `staging` or `prod`.
4. Vault keys per `contracts/secrets-contract.md` must exist before the pattern is applied (checked by quickstart gate, not schema).

## Non-contract (deliberately not exposed)

- Chart version pins, image tags/digests, supervisor topology/sideload, telemetry, AppArmor, storage sizes — fixed in the wrapper chart per `research.md` D1/D10. Changes are a code change to `charts/openshell/`, reviewed like any other dependency bump.
- Sandbox policy content — operator-supplied documents in the Git location defined by `charts/openshell-policy/` (mechanism shipped; content is the operator's).
