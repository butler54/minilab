# Contract: ArgoCD Reconciliation Cadence

Home of truth: `values-global.yaml`.

## Values contract

```yaml
main:
  gitops:
    channel: gitops-1.21            # preserve live value; do not regress
    operatorSource: redhat-operators # preserve live value
    customArgoYaml: |
      extraConfig:
        timeout.reconciliation: 600s
```

## Projection contract (verified against patterns-operator source)

| Layer | Object | Key | Expected value |
|-------|--------|-----|----------------|
| Git | `values-global.yaml` | `main.gitops.customArgoYaml` | YAML containing `timeout.reconciliation: 600s` |
| ConfigMap | `patterns-operator/patterns-operator-config` | `gitops.customArgoYaml` | identical YAML string |
| ArgoCD CR | `vp-gitops/vp-gitops` | `spec.extraConfig["timeout.reconciliation"]` | `"600s"` |
| Runtime CM | `vp-gitops/vp-gitops-argocd-cm`* | `timeout.reconciliation` | `600s` |

\* whatever argocd-cm instance name the gitops operator uses; verify with
`oc get cm -n vp-gitops -l app.kubernetes.io/part-of=argocd`.

## Failure modes this contract prevents

1. **Silent revert** — direct ARGOCD-CR or argocd-cm edits are reverted by the
   patterns-operator / gitops-operator (research.md D2); the contract forces the
   change through the operator-supported overlay seam.
2. **Values drift** — `tests/test-argocd-cadence.sh` fails if `values-global.yaml`
   no longer carries the 600s pin, or if it regresses `gitops.channel` /
   `gitops.operatorSource` below the live baseline recorded here.
