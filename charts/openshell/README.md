# openshell (wrapper chart)

Thin wrapper around the upstream NVIDIA OpenShell chart (research.md D1,
feature 006-openshell-gitops-install).

## Layout

- `Chart.yaml` — dependency on `oci://ghcr.io/nvidia/openshell/helm-chart`,
  pinned to `0.0.116` (digest recorded in `Chart.lock`).
- `charts/openshell-0.0.116.tgz` — vendored dependency (`helm dependency build`; committed to Git).
- `values.yaml` — **static** minilab pins: telemetry off, `init-container`
  sideload, GitOps-safe (`preflight.enabled=false`, KEK from `openshell-kek`),
  SCC-compatible security contexts, pinned images.
- `templates/` — pattern-owned extras: OAuthClient, router-CA fetch job+RBAC.
- Operator dials (hostname, issuer, OIDC endpoints) live in
  `../../overrides/values-openshell.yaml` (same file as the `global` feature
  values); drift between the two is caught by `tests/test-openshell-values.sh`.

## Update procedure (upstream release bump)

1. Bump `dependencies[].version` in `Chart.yaml` (exact semver, no ranges).
2. `helm dependency build` in this directory; commit the new tgz + `Chart.lock`.
3. Reconcile `values.yaml` against `helm show values oci://ghcr.io/nvidia/openshell/helm-chart --version <n>` — values schema is experimental and changes between upstream releases; diff carefully against research.md D10.
4. Refresh `server.sandboxImage` digest (`skopeo inspect docker://ghcr.io/nvidia/openshell-community/sandboxes/base:latest`).
5. `make validate-openshell`, then reconcile the testing-phase checklist in
   `specs/006-openshell-gitops-install/quickstart.md`.

## User authentication (research D3)

Kubernetes-mode gateways do NOT support mTLS user auth — OIDC is mandatory for
remote CLI use. This chart wires OpenShift's built-in OAuth server as the OIDC
issuer (`server.oidc.*` in overrides, CA via the router-ca fetch job) with a
public PKCE `OAuthClient` (`openshell-cli`, no client secret in Git).
Fallback if V-AUTH fails on the target cluster: cluster-local port-forward
per upstream docs (`oc -n openshell port-forward svc/openshell 8080:8080`).
