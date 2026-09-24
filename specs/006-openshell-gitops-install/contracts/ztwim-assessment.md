# Contract: ZTWIM / SPIFFE Readiness Assessment (record-in-Git artifact)

**Feature**: `006-openshell-gitops-install` | **Phase 1 artifact**

FR-011/SC-006 require a definitive consume/defer record. This file is the contract for the **living assessment document**, which is instantiated in the repository at `docs/openshell-spiffe-assessment.md` during implementation and updated as upstream changes land.

## Required content of the instantiated record

| Field | Content |
|-------|---------|
| Date / recorder | When the assessment was last updated and by which change |
| Operator availability | ZTWIM operator version/channel available for OCP 4.22, GA status, evidence link |
| Consumable integrations (verified) | Each OpenShell integration point that accepts SPIFFE identities **with the verification evidence** (command output, OCSF/event, issued-SVID log line) |
| Deferred integrations | Each integration point that does not exist at the deployed OpenShell version, with the upstream signal that defines "ready" (release note, docs page, chart value) |
| Re-evaluation triggers | Named upstream events that flip any Deferred row (e.g. "OpenShell chart documents `providerTokenGrants.spiffe`; currently in `main` only") |

## Baseline at planning time (2026-09-23, from research.md)

| Integration point | Status at planning | Evidence to collect |
|-------------------|--------------------|---------------------|
| ZTWIM operator deploys + issues SVIDs (GA 1.1.1, OCP 4.22 catalog) | Consumable | `ClusterSPIFFEID` issues identity to a test pod (quickstart V-SPIFFE) |
| OpenShell `providerTokenGrants.spiffe` (gateway exchanges sandbox JWT-SVID for provider token) | **Probable-consumable** (in upstream `main`/docs; verify chart 0.0.116 values) | Sandbox reaches OpenAI with no key in sandbox env; DENY event shows policy attribution |
| SPIFFE identity of the agent runtime itself (blog roadmap item) | Deferred | Re-evaluate on each OpenShell release announcement |

## Rule

The instantiated record is updated in the same PR as any change to the ZTWIM or OpenShell versions — the assessment is a living document, not a one-time deliverable.
