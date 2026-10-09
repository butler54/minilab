# Data Model: Zen Sandbox Demo and Server Mode

**Date**: 2026-10-09 | **Feature**: `011-zen-sandbox-demo`

Entities are demo-domain concepts realized as Git-resident assets + runtime
openshell objects. No persistent application database exists (gateway DB is
ephemeral by design — research D6).

## Entity: DemoSandbox (runtime)

| Field | Type | Notes |
|---|---|---|
| name | string, ≤19 chars | `zen-<epoch>` shape (008 name-cap lesson) |
| image | string | 008 carrier image default (research D5) |
| provider | string | `zen` (profile-backed) |
| policy | ref → EgressPolicy | applied via `openshell policy set --wait` |
| state | enum | Provisioning → Ready → (fenced|deleted); fence window ~5 min |
| created_via | string | script name + run id (traceability) |

Lifecycle rules: must reach `Ready` before policy-dependent steps; must survive
past the bootstrap-fence window before acceptance timers start; teardown is
unconditional (`trap`-style cleanup, idempotent delete).

## Entity: EgressPolicyAllowlist (Git-resident)

| Field | Type | Notes |
|---|---|---|
| file | path | `charts/openshell-policy/policies/zen-demo.yaml` |
| version | int | openshell policy `version: 1` |
| network_policies | map<ruleName, Rule> | deny-all default; explicit allows only |
| filesystem_policy | object | carried from 008 sample (workdir include; RO/ RW sets) |

**Rule** fields: `endpoints[] {host, port, protocol: rest, access: full,
enforcement: enforce}`; `binaries[]` (mandatory, kernel-resolved paths);
inline `justification` comment per rule naming the motivating blocked-probe.

Validation rules (FR-002/003 → static tests):
- every rule has ≥1 `endpoints` entry AND ≥1 `binaries` entry (008 C6 guard)
- every credentialed/HTTP endpoint uses `protocol: rest`
- every rule carries a `# justification:` comment referencing a probe/observation
- no wildcard hosts; no duplicate host:port pairs (policy-lint discipline)

## Entity: ZenProviderProfile (Git-resident + gateway runtime mirror)

| Field | Type | Notes |
|---|---|---|
| file | path | `deploy/openshell/profiles/zen.yaml` |
| credential_ref | vault path | `secret/data/hub/openshell-zen` → env `ZEN_API_KEY` (only if keyless probe fails — D1) |
| gateway_objects | runtime | provider + profile records; recreate idempotently (ephemeral DB) |

## Entity: AgentConfigTemplate (Git-resident)

| Field | Type | Notes |
|---|---|---|
| file | path | `deploy/openshell/demo/zen/opencode-zen.json` |
| model | string `provider/id` | spike-resolved zen free model id (D2) |
| provider | object | OpenAI-compatible provider block; baseURL from spike probe |
| apiKey | string or absent | absent in keyless mode; `{env:ZEN_API_KEY}` placeholder in key mode — never a real secret |

Contract C1 (008) applies: strict JSON, zero secret material, single logical
host reference, lint-gated.

## Entity: DemoEvidenceLog (Git-resident)

| Field | Type | Notes |
|---|---|---|
| file | path | `specs/011-zen-sandbox-demo/demo-log.md` |
| runs[] | list | each: timestamps, mode (smoke/interactive/server), policy iterations (probe → rule), query transcripts (prompt + response), deny-proof counts, teardown proof |

## Relationships

- DemoSandbox **applies** EgressPolicyAllowlist (1:1 at a time; iterations
  append rules, Git is the sequence-of-record).
- AgentConfigTemplate **targets** ZenProviderProfile's provider object (name
  must match the gateway provider name).
- DemoEvidenceLog **records** every DemoSandbox run and every EgressPolicyAllowlist
  iteration (FR-003 traceability chain).
