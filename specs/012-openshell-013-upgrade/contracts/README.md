# Contracts: OpenShell 0.1.3 Upgrade

Interface behaviors this feature must satisfy. Three contracts.

## Contract U1: Version pins converged

**Statement**: Post-push, the five version values (chart + 3 images + CLI) are all
`0.1.3`, and Argo CD shows the openshell applications Synced+Healthy against
the new desired state.

**Inputs**: Git commits on `main` bumping the five values; one recorded
force-refresh+sync (`oc annotate ... refresh=hard` + sync operation patch).

**Output indicators**:
- `openshell --version` → `openshell 0.1.3`
- `make check-openshell-cli` → PASS
- `oc -n vp-gitops get applications | grep openshell` → all `Synced`/`Healthy`
- gateway pod image tag `0.1.3` (`oc -n openshell get pod openshell-0 -o jsonpath='{.spec.containers[0].image}'`)

**Failure responses**:
- chart/image tag mismatch → tests fail; do not push.
- Argo degraded > 15 min → revert pin commit, re-sync, record.
- brew shadowing → `brew unlink openshell` before check.

## Contract U2: Policy attached at create (US3 core)

**Statement**: A sandbox created with a policy file supplied at create time reaches
ready with the policy active from birth — no admission-rejected window, no
300s repair race, no `ConfigurationInvalid`.

**Inputs**:
```
openshell sandbox create --name <n> \
  --policy charts/openshell-policy/policies/zen-demo.yaml \
  --from ghcr.io/butler54/openshell-sandbox:latest \
  --detach
```
**Required observable assertions** (any one missing → contract FAIL):
1. `openshell sandbox get <n> -o json` → admission `accepted`, `policy_version >= 1` before the first exec.
2. An egress attempt matching a deny rule fails with the supervisor sinkhole
   (`Immediate connect fail for 198.18.0.x: Permission denied`) on the FIRST exec.
3. No `openshell policy set <n>` command was issued between create and assertions.
4. Ready from create in <= 5 min, zero `ConfigurationInvalid` conditions.

**Failure responses**:
- Any assertion fails → root-cause (logs: `openshell sandbox get -o json` conditions,
  gateway pod logs, supervisor/admission state) → fix config/usage if within repo
  scope → re-validate. Unfixable here → retain create+policy-set race in scripts,
  record upstream reference, contract recorded FAIL-documentative.

## Contract U3: Demo flows regression-guarded

**Statement**: Repo demo drivers use policy-at-create for the *initial* policy where
U2 validates; iterative post-create `openshell policy set` still applies inline
for remediation narratives; tests + zen smoke stay green.

**Inputs**: edits to `deploy/openshell/demo/zen/run-zen-demo.sh` and
`deploy/openshell/demo/run-demo.sh` (policy-at-create path with documented fallback).

**Output indicators**:
- `bash -n` both scripts; `make test-static` PASS; `./pattern.sh make validate-schema` PASS.
- `run-zen-demo.sh --smoke` completes end-to-end: sandbox Ready, zen `hi` = ZEN_HI_OK,
  ≥5 deny proofs PASS, teardown leaves empty sandbox list.
- Iterative `policy set` mid-life still increments policy version (remediation loop intact).

**Failure responses**:
- Smoke fails with new artifact changes → revert script changes only (platform pin
  stays) and re-validate U2 separately; do not mix regressions into the version bump.
