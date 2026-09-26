# Contract: Secrets (vault ↔ in-cluster)

**Feature**: `006-openshell-gitops-install` | **Phase 1 artifact**

All secret VALUES live in the pattern's vault. Git contains only ExternalSecret definitions and vault key paths (per Constitution: no secret material in Git).

| Vault path (operator seeds) | ExternalSecret (Git) | Cluster Secret | Namespace | Keys | Consumer |
|-----------------------------|----------------------|----------------|-----------|------|----------|
| `secret/data/hub/openshell-cloudflare` | `cloudflare-api-token-es` | `cloudflare-api-token` | `cert-manager` | `api-token` | ACME DNS-01 solver (the `acme` ClusterIssuer) |
| `secret/data/hub/openshell-gateway-kek` | `openshell-kek-es` | `openshell-kek` | `openshell` | `key-encryption-key` (data key required by upstream chart helper; vault field is `kek`) | Gateway credential storage (`server.credentialStorage.existingSecret`, D4) |
| `secret/data/hub/openshell-openai` | `openai-api-key-es` | `openai-api-key` | `openshell` | `api-key` | Gateway-side provider credential (D8); never mounted into sandbox pods |

(Vault paths follow the rule from PR review: the path prefix MUST equal the `vaultPrefixes` entry of the same secret in `values-secret.yaml.template` — `hub` here because this deployment is the hub cluster and that is the valid prefix for it. `tests/test-openshell-secrets.sh` derives expected paths from the seed template so drift is caught when either side moves. KEK via `onMissingValue: generate`, the other two via `prompt`.)

## Rules

1. **Seed-before-sync**: the three vault keys above MUST exist before the pattern is applied with `openshell.enabled=true`; quickstart gate G0 verifies them. External Secrets surfaces a `SecretSyncedError` otherwise — acceptable, self-healing once seeded, but noisy.
2. **Cloudflare token scope**: API Token with `Zone:DNS:Edit` + `Zone:Zone:Read` on `global.dnsZone` only (research D6). Axiom: never commit, never print, never mount outside `cert-manager` ns.
3. **KEK rotation**: rotating `gateway-kek` invalidates provider credentials stored in the gateway DB — re-register the OpenAI credential after rotation (documented in quickstart runbook).
4. **OpenAI key**: consumed only at the gateway/provider layer (research D8). Sandbox pods and CI logs must never contain it; the demo's acceptance evidence (SC-009) must not print it.
5. **Sync ordering**: `cloudflare-api-token-es` and the two ClusterIssuers share a sync wave (Secret first) to avoid cert-manager operand ≤1.21.0 solver-validation staleness (research D6); `openshell-kek-es` precedes the openshell application wave so the chart's GitOps rendering never generates a transient KEK (research D4).
