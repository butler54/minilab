# Quickstart: V-DEMO validation (opencode-in-sandbox, matilda)

Runnable acceptance path for this feature. All artifact paths are repo-relative; every imperative step is recorded in Git before running (Constitution II).

## Phase -1: Prerequisites (one-time per gateway lifetime)

- Gateway authenticated: `OPENSHELL_NO_BROWSER=1 openshell gateway login k8s` (device flow), then `openshell status -g k8s` shows `Status: Connected` / `Authentication: Authenticated`.
- Matilda profile exists: `openshell profile describe matilda`; if missing: `openshell provider profile import -f deploy/openshell/profiles/matilda.yaml --global`.
- Matilda provider exists: `openshell provider list | grep matilda`; if missing: `MATILDA_API_KEY=$(...vault...) openshell provider create --name matilda --type matilda --global-profile --credential MATILDA_API_KEY`.

## Phase 0: Binary path discovery (one-time, feeds policy)

1. `openshell sandbox create --name bin-probe --from ghcr.io/butler54/openshell-sandbox:latest --detach --no-keep`
2. Apply existing policy first (a policy-less sandbox never reaches Ready): `openshell policy set bin-probe --policy charts/openshell-policy/policies/sample-matilda-demo.yaml --wait`, wait Ready, then: `openshell sandbox exec -n bin-probe -- sh -lc 'which node opencode curl; readlink -f $(which node); readlink -f $(which opencode)'`
3. Record the resolved paths into `charts/openshell-policy/policies/sample-matilda-demo.yaml` `binaries:` (repo change, commit).

## Phase 1: Smoke (non-interactive, scripted)

`DEMO_PROMPT="Reply with exactly: OPENSHELL_VDEMO_OK" deploy/openshell/demo/run-demo.sh --smoke`

Expected:
1. `PASS preflight` (gateway connected+auth).
2. `PASS create` (sandbox Ready; image pulled from ghcr.io/butler54).
3. `PASS inject` (template landed, verified `matilda.maincode.com` inside sandbox config).
4. `PASS policy` (status effective).
5. `PASS agent` (response substring `OPENSHELL_VDEMO_OK` observed in captured output; matilda edge status 200 lives in supervisor/es log if enabled).
6. `PASS deny` (≥1 non-allowlisted egress probe rc=7).
7. `PASS no-secrets` (no `mc_live` bytes inside env or `/sandbox`).
8. `PASS cleanup` (`openshell sandbox list` empty again).

## Phase 2: Interactive demo (TTY, for show)

`deploy/openshell/demo/run-demo.sh` (no `--smoke`):

1. Creates + configures sandbox as in smoke, then `openshell sandbox connect <name>` attaches.
2. Operator drives `opencode` inside the sandbox; a live `curl https://example.com` shows denial; a live `curl POST .../chat/completions -H "Authorization: Bearer $MATILDA_API_KEY"` returns 200 matilda.
3. Detach (Ctrl-P Ctrl-Q) → RE-RUN `deploy/openshell/demo/run-demo.sh --proofs` → proofs + cleanup as smoke Phase 1 steps 6–8.

## Phase 3 (record): sandboxctl attempt → bug reports

1. Attempt the same demo shape locally via `sandboxctl` per its standard workflow; record every hard failure with version (`sandboxctl doctor --all`), repro steps, expected-vs-actual.
2. Raise one GitHub issue per distinct defect on the appropriate repo; link from `docs/openshell-demo-opencode.md`.
3. This phase does NOT gate acceptance (clarify session: cluster gateway canonical); it feeds FR-005 tracking.

## Cleanup checklist (always end state)

- [ ] `openshell sandbox list` empty
- [ ] no unexpected sandboxes on local podman gateway (`podman ps -a --filter name=openshell-` empty)
- [ ] vault seeds unaffected (git status clean on `values-secret.yaml`)
