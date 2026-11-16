# Contract: Operator Review Artifact

**Feature**: 014-ocp501-openshell-upgrade | **Consumer**: `/speckit.tasks`, implementation, `/speckit.converge` | **Format of**: `specs/014-ocp501-openshell-upgrade/review-log.md` (operator-review section)

The review artifact is the durable record required by FR-001/FR-004/FR-010 and consumed by convergence checks. It MUST contain one record per subscription declared in `values-prod.yaml` `clusterGroup.subscriptions` — exactly these seven keys:

`lvms-operator`, `eso`, `cluster-observability-operator`, `cert-manager-operator`, `ztwim`, `rhbk`, `agent-sandbox`

The framework-managed `patterns-operator` subscription (on-cluster, not declared in the pattern values) MAY appear as an additional observational record clearly marked `framework-managed — no Git pin decision`; it is not part of the completeness gate.

## Record format

```markdown
### <subscription-key> — <UPDATE | KEEP | HOLD>

- **Package**: <OLM package name>
- **Pin before**: channel=<...>, csv=<...|->, approval=<Automatic|Manual>
- **Pin after**: channel=<...>, csv=<...|->, approval=<Automatic|Manual>   (identical to before for KEEP)
- **5.0.1 catalog state**: <channels and head CSVs observed; subscription conditions>
- **Decision**: <UPDATE|KEEP|HOLD> — <one-paragraph rationale>
- **Evidence**: <commands run + date; links to output captures if large>
```

## Rules

1. **Completeness**: every key listed above appears exactly once (SC-001: 100% coverage).
2. **Consistency**: for `UPDATE`, the `Pin after` values MUST match the values committed to `values-prod.yaml`/`values-global.yaml` in this feature; for `KEEP`/`HOLD`, no value files change for that operator.
3. **HOLD legitimacy**: a `HOLD` MUST cite the blocking catalog evidence (e.g., `ResolutionFailed/ConstraintsNotSatisfiable` with no 5.0.1-compatible channel) and confirm the installed CSV remains healthy.
4. **Imperative steps**: any imperative action arising from a decision (e.g., forced sync, installplan cleanup) is recorded in the artifact's imperative-steps section with command, rationale, result, and reconcile-back note (constitution II).
5. **Approval mode**: FR-011 changes only the cluster-observability subscription to `Automatic`. Subscriptions that declare no `installPlanApproval` in Git (eso) record the OLM default explicitly as such — recording a value absent from Git would otherwise violate rule 2 for a KEEP.

## Verification (used by tasks and converge)

```bash
# every subscription key in values-prod.yaml has a record
# (scope to the Operator Review section; exclude the framework-managed
#  observational record, which the contract allows but does not require)
yq -r '.clusterGroup.subscriptions | keys[]' values-prod.yaml | sort > /tmp/expected
sed -n '/^## Operator Review/,/^## Catalog Snapshot/p' specs/014-ocp501-openshell-upgrade/review-log.md \
  | grep -E '^### ' | sed 's/### //; s/ — .*//' | grep -v '^patterns-operator$' | sort > /tmp/recorded
diff /tmp/expected /tmp/recorded   # must be empty
```
