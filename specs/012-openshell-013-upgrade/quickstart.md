# Quickstart: OpenShell 0.1.3 Upgrade Validation

End-to-end validation of feature 012. Run as kube:admin with `oc` access to
minilab sno, and a valid openshell gateway session (login fresh — see
minilab#9 for token lifetime).

## G0 — Pre-flight (locally)

```bash
# Chart + images exist
helm show chart oci://ghcr.io/nvidia/openshell/helm-chart --version 0.1.3 | head
# Static gates BEFORE push
make test-static && ./pattern.sh make validate-schema
```

Expected: chart 0.1.3 metadata shown; both gates green.

## G1 — Apply version bump (main)

Edit the 5 surfaces per `contracts/README.md#U1` (2 values files + 3 test files),
commit all on `main` in one commit, `git push origin main`.

## G2 — Argo CD converge (force + verify)

```bash
oc -n vp-gitops annotate application/openshell argocd.argoproj.io/refresh=hard
oc -n vp-gitops patch application/openshell --type=merge \
  -p '{"operation":{"sync":{"prune":false}}}'
# watch
oc -n vp-gitops get applications | grep openshell
```

Expected: all openshell apps Synced+Healthy within 15 min (SC-001), gateway pod
image `0.1.3` (SC-002).

## G3 — Workstation CLI parity

```bash
brew unlink openshell 2>/dev/null || true
make install-openshell-cli
openshell --version        # expect: openshell 0.1.3
make check-openshell-cli   # expect: green
```

Expected: SC-003 PASS.

## G4 — Policy-at-create proof (U2, SC-004)

```bash
# Fresh login (token lifetime ~50 min — see minilab#9)
OPENSHELL_NO_BROWSER=1 openshell gateway login k8s
SB=fix013-$(date +%s)
openshell sandbox create --name "$SB" \
  --policy charts/openshell-policy/policies/zen-demo.yaml \
  --from ghcr.io/butler54/openshell-sandbox:latest --detach
# Assert birth-state admission + policy BEFORE any exec / policy set
openshell sandbox get "$SB" -o json | python3 -c \
  'import json,sys;d=json.load(sys.stdin);print(d.get("admission"),d.get("policy_version"))'
# First op must honor deny-all (sinkhole)
openshell sandbox exec -n "$SB" -- curl -m 8 https://github.com
# Iterative path (008/011 remediation loop) still works
openshell policy set "$SB" --policy charts/openshell-policy/policies/zen-demo.yaml -w
```

Expected: admission `accepted`, `policy_version >= 1` at birth; curl denied with
`Immediate connect fail for 198.18.0.x: Permission denied`; policy set updates
apply (U2 + U3). `Ready` within 5 min, no `ConfigurationInvalid`.

## G5 — Demo script adoption + smoke

After U2 validates: switch initial-policy acquisition in
`deploy/openshell/demo/zen/run-zen-demo.sh` and `deploy/openshell/demo/run-demo.sh`
to `create --policy` / `OPENSHELL_SANDBOX_POLICY` (keep iterative `policy set`).
Then:

```bash
./deploy/openshell/demo/zen/run-zen-demo.sh --smoke
```

Expected: PASS hi (ZEN_HI_OK), 5/5 deny proofs, empty sandbox list (SC-005).

## G6 — Close

```bash
openshell sandbox list -g k8s    # empty
openshell forward list           # empty
oc -n vp-gitops get applications | grep -vE 'Synced.*Healthy' || echo all-green
git log --oneline -5             # all work on main
```

Expected: zero residual, everything on main, issue #8 referenced in evidence log.
