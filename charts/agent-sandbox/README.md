# agent-sandbox (vendored upstream chart)

Vendored copy of `helm/` from the kubernetes-sigs/agent-sandbox repository.

- **Source**: https://github.com/kubernetes-sigs/agent-sandbox/tree/v1.0.3/helm
- **Tag**: `v1.0.3` (released 2026-09-17)
- **Vendored**: 2026-09-23 (feature 006-openshell-gitops-install, research decision D5)
- **Modifications from upstream**: values.yaml only — image tag pinned to `v1.0.3`,
  explicit controller resources, `containerSecurityContext.seccompProfile=RuntimeDefault`,
  `namespace.create=false` (namespace owned by the pattern clustergroup),
  `controller.extensions=false` (core API only; OpenShell 0.0.116 requires only the
  core `sandboxes.agents.x-k8s.io/v1beta1` CRD).
- **Update procedure**: re-copy `helm/` at a new upstream tag, re-apply the
  values.yaml deltas above, bump the tag here, and run `make validate-openshell`.

Upstream release manifest note: NVIDIA's OpenShell docs reference
`releases/latest/download/manifest.yaml`, which 404s from upstream v1.0 onward —
vendoring this Helm chart is the supported GitOps install path for this repo.
