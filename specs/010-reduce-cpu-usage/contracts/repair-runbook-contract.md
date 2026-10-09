# Contract: Agent-Sandbox Leak Repair Runbook

Mirror of `docs/agent-sandbox-repair.md` (the Git-recorded rationale) with the
executable behavior of `scripts/repair-agent-sandbox-leak.sh`.

## Preconditions (script MUST verify all, or exit non-zero without changes)

1. `Application/vp-gitops/agent-sandbox` exists on the cluster.
2. That Application is **not** present in `values-prod.yaml` `clusterGroup.applications` (checked against local Git worktree at the commit being deployed — guards against someone resurrecting it in Git first).
3. `oc get sandboxes,sandboxclaims,sandboxtemplates,sandboxwarmpools -A` is empty.
4. CSV `agent-sandbox-system/agent-sandbox-operator.v0.9.0` exists (phase value irrelevant — it is expected to be `Failed` pre-repair).

## Action (exactly once)

`oc delete application agent-sandbox -n vp-gitops` — the
`resources-finalizer.argocd.argoproj.io/foreground` finalizer cascades deletion
of exactly the 4 ArgoCD-tracked objects: `Deployment/agent-sandbox-controller`
(+ ClusterRoles ×2, ClusterRoleBinding). Untracked Helm CRDs and the namespace
stay (see `research.md` D1 — deletion cannot cascade to CRDs).

## Postconditions (script MUST probe until timeout 10m)

1. `oc get application agent-sandbox -n vp-gitops` → NotFound.
2. `oc get deployment agent-sandbox-controller -n agent-sandbox-system` → exists with **non-Helm** labels (recreated by OLM).
3. CSV phase becomes `Succeeded`.
4. No new events reason `InstallComponentFailed` in `agent-sandbox-system` for 5m.
5. Rate probe (PromQL from `ANALYSIS.md`): `sum(rate(apiserver_request_total{verb="PUT", resource="clusterserviceversions"}[5m]))` < 0.1.

## Idempotence & rollback

- Second run: detects condition 1 false → prints "no leak present", exits 0.
- Rollback: none needed — Git desired state equals post-repair state
  (`minilab-prod` selfHeal converges the remainder: `minilab-prod` and
  `lvms-config` sync clean-up). Re-introducing the leak would require a Git
  change, which the existing test suites (`test-external-refs.sh`,
  `test-openshell-render.sh`, `test-openshell-pins.sh`) already reject in CI/local
  validation.

## Recording

Run output (preconditions + postconditions, full probe values) is appended to
`specs/010-reduce-cpu-usage/ANALYSIS.md` under "Post-repair evidence" — FR-011.
