# Research: OpenShell 0.1.3 Upgrade (minilab#8)

2026-10-13 — resolved unknowns for the plan. All facts verified live.

## R1. Upstream 0.1.3 asset availability

- **Decision**: Bump chart + component pins to 0.1.3.
- **Verified**: `helm show chart oci://ghcr.io/nvidia/openshell/helm-chart --version 0.1.3`
  → chart `helm-chart` 0.1.3, appVersion 0.1.3, digest `sha256:44ec11bbf264fde0b65c804c856113a4dd322731a8b3803315724357855a434b`
  (published 2026-10-09, two releases after our 0.1.1 pin).
- Release notes (0.1.2 + 0.1.3) include: supervisor session-retry on startup (#3765),
  provider CAS retry (#3501), gateway OCSF JSONL (#3264 + helm wiring #3876),
  corporate-proxy CA bundles (#3549), TCP readiness probe for supervisor (#3700),
  sandbox-leak drop fix (#3750), orphan-reaper wake (#3757), optional cluster-scoped
  RBAC (#3459, chart value `gateway.rbac.clusterScoped.create`).

## R2. Chart values schema compatibility (0.1.1 → 0.1.3)

- **Decision**: Keep the existing `overrides/values-openshell-gateway.yaml` shape; only
  the three image tags go 0.1.1 → 0.1.3.
- **Verified**: `helm show values` diff 0.1.1 vs 0.1.3 is **purely additive** —
  new `gateway.rbac` (incl. `clusterScoped.create`), HPA block, `gateway.ocsfLog`
  (OCSF JSONL, `enabled:false` default, `path:/tmp/gateway-ocsf.jsonl`),
  `replicaRouting`, terminationGracePeriodSeconds default 5→30. All keys we
  override (`gateway/sandboxRuntime/supervisor.image.tag`, `sandbox.image.*`,
  `server.telemetryEnabled`, `replicaCount`) are unchanged in semantics.
- New knobs of interest (optional, may be toggled during implementation):
  `gateway.ocsfLog.enabled: true` restores the deny-evidence channel that
  011's FR-003 loop could not reach (no supervisor pods in k8s driver mode).
- The wp title fix for issue #8 action 1 does not depend on any of these.

## R3. Workstation CLI parity path

- **Decision**: Use upstream installer into `~/.local/bin` + `brew unlink openshell`.
- **Verified**: Homebrew `openshell` formula still ships **0.1.1 only** (checked 2026-10-13);
  pin must come from upstream releases. `make install-openshell-cli` already
  implements this fallback: when brew ≠ pin it runs the upstream installer with
  `OPENSHELL_VERSION=v$ver OPENSHELL_INSTALL_DIR=~/.local/bin`.
- **PATH hazard**: `/opt/homebrew/bin` precedes `~/.local/bin` in the default login
  PATH on this machine, so the brew 0.1.1 binary would shadow the 0.1.3 install;
  `brew unlink openshell` (reversible: `brew link`) removes the shadow without
  uninstalling. `tests/check-openshell-cli.sh` asserts `$openshell_bin --version`
  equals the chart pin and is the arbiter.
- The version-tie check reads the pin from `values-prod.yaml` → single source of truth.

## R4. Argo CD force-sync mechanics

- **Decision**: `oc`-based refresh + sync against `vp-gitops` namespace (recorded
  imperative step, constitution II).
- **Verified**: `argocd` CLI exists but its server config points at a stale
  localhost port (unset); `oc whoami`=kube:admin works and `openshell` app lives in
  `vp-gitops`. Procedure:
  1. `oc -n vp-gitops annotate application/openshell argocd.argoproj.io/refresh=hard`
  2. `oc -n vp-gitops patch application/openshell --type=merge -p '{"operation":{"sync":{"prune":false}}}'`
     (argocd exposes spec.operation for imperative syncs; alternatively
     `oc delete po -l app.kubernetes.io/name=openshift-gitops-application-controller -n vp-gitops` —
     no, prefer operation patch.)
- Self-heal is not enabled expansively; `lvms-config` OutOfSync (010 incident) is
  untouched by this feature.

## R5. Complete pin/expectation surface (single-edit list)

| File | Field | Change |
|---|---|---|
| `values-prod.yaml` | `clusterGroup.applications.openshell.chartVersion` | 0.1.1 → 0.1.3 |
| `overrides/values-openshell-gateway.yaml` | `gateway.image.tag`, `sandboxRuntime.image.tag`, `supervisor.image.tag` | → 0.1.3 |
| `tests/test-external-refs.sh` | expected `openshell` chartVersion (line ~53) | → 0.1.3 |
| `tests/test-openshell-pins.sh` | `OSC_VER` (line ~42) | → "0.1.3" |
| `tests/test-openshell-render.sh` | `OSC_VER` (line ~50) | → "0.1.3" |
- NOT touched: `overrides/values-ztwim.yaml` (ztwim chart 0.1.1, unrelated),
  `rh-keycloak` 0.1.0, "proven live openshell 0.1.1" historical annotations in
  policy files/docs (attribution comments; add new-version notes where behavior
  is re-verified, don't rewrite history).

## R6. Policy-at-create validation design (US3 mechanic)

- **Decision**: Validate with `openshell sandbox create --policy charts/openshell-policy/policies/zen-demo.yaml --from ghcr.io/butler54/openshell-sandbox:latest --detach`, then assert `openshell sandbox get -o json` → `admission=accepted`, `policy_version>=1` from birth; confirm deny-all egress (e.g. curl github.com → sinkhole deny) from the sandbox's very first exec BEFORE and without any `openshell policy set` call.
- 0.1.1 CLI already carries `--policy` + `OPENSHELL_SANDBOX_POLICY` (verified via
  `create --help` 2026-10-13); 0.1.3 supervisor fixes (#3765 "keep session retries
  during startup") improve the exact failure class 011 fought.

## Alternatives considered

- **Wait for brew formula 0.1.3**: rejected — blocks the whole feature on a party we can't control; the Makefile already supports the installer fallback.
- **Remove explicit image tags, rely on chart appVersion**: rejected — repo convention (test-asserted) pins tags explicitly for drift detection.
- **`argocd` CLI login + `argocd app sync`**: rejected for now — server config is stale; `oc patch` is equally declarative-triggering and works with kube:admin.
- **Enable `ocsfLog.enabled` in this feature**: deferred decision to implementation — small, additive; only if free (otherwise follow-up).
