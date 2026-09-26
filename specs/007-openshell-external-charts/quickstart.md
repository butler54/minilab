# Quickstart: Validation Guide — External Chart Sourcing Refactor

**Feature**: `007-openshell-external-charts` | Static-first; designated-cluster runtime appendices stay in 006's quickstart.

## G1 — Offline proof gates (run anywhere)

| Gate | Command | Proves |
|------|---------|--------|
| Refactor suites | `make validate-openshell` | updated 7+ suites incl. `test-external-refs.sh` |
| Pattern config | `tests/validate-pattern-config.sh` | values syntax, local chart lints |
| Schema | `./pattern.sh make validate-schema` | clustergroup schema accepts the new application forms |

## V-SRC — Source-of-truth proofs (SC-001, SC-002)

1. `rg -l 'kind: CustomResourceDefinition|^apiVersion.*helm.cattle|^# Source:' charts/ || true` and `find charts -name '*.tgz' -o -name 'crds'` → **empty** (no upstream chart content).
2. Application entries in `values-prod.yaml` for openshell/agent-sandbox/cert-manager/ztwim carry `chartVersion` with EXACT pins matching `contracts/external-chart-contract.md`.
3. **Bump drill**: change exactly one version field to a bogus value → suites must FAIL with a version-drift error; revert. Record the diff — it must touch only the version line.
4. `helm template openshell oci://ghcr.io/nvidia/openshell/helm-chart --version 0.0.116 -f overrides/values-openshell-gateway.yaml | rg 'kind: StatefulSet'` (online, optional pre-commit smoke) → renders.

## V-REF (runtime appendix of 006 testing phase, on designated cluster)

1. After pattern sync: `oc -n openshift-gitops get app openshell -o jsonpath='{.spec.sources}'` shows the multi-source pair (pattern git ref + external OCI source at pinned targetRevision).
2. `oc -n openshift-gitops get app agent-sandbox -o jsonpath='{.spec.sources[1].targetRevision}'` == `v1.0.3`.
3. Every feature Application is `Synced/Healthy` (continues into 006's V-ORDER).
4. If the OCI form fails to resolve on the cluster's ArgoCD, flip `repoURL` to the `oci://` prefix form per research.md residual-risk row and re-verify.

## Impacted 006 checks (updates applied by this feature)

- `tests/test-openshell-render.sh` — wrapper-based assertions replaced by app-override + merged-values assertions (suites updated per tasks).
- `tests/test-openshell-pins.sh` — scans now cover `values-prod.yaml` application pins and all `overrides/values-*.yaml`.
- `tests/test-openshell-ztwim.sh` — downscoped to the local `ClusterSPIFFEID` + `values-ztwim.yaml` intent (upstream CRs now owned by the VP chart whose own CI covers them).
- README "Update procedure" (charts/openshell/README.md) — deleted with the wrapper; version-bump runbook becomes `contracts/external-chart-contract.md` rule 3.
