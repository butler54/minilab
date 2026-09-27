# Phase 0 Research: Opencode-in-Sandbox Demo

## D1. Carrier sandbox image

**Decision**: `ghcr.io/butler54/openshell-sandbox:latest` (the `sandbox/standard` layer of `butler54/containers`).

**Rationale**: The image family is built `FROM ghcr.io/nvidia/openshell-community/sandboxes/base@sha256:aeef1c63f00e2913ea002ccb3aaf925f338b5c5d70e63576f0d95c16a138044e` — the same digest pinned as the gateway's `sandbox.default_image`, so the agent-runtime contract (seccomp mediation, DNS interception, agent binary mount at `/opt/openshell/bin`, workspace at `/sandbox`) is inherited unchanged. `opencode-ai@1.18.30` is npm-global in every derived variant; user's own workflow images (speckit/docs) stay untouched by this demo.

**Alternatives considered**: pre-built dedicated demo image — rejected at clarify Q3 (runtime injection accepted, image-bake deferred). Stock NVIDIA base without butler54 layers — rejected (no opencode preinstalled).

## D2. Custom image on cluster gateway (0.1.1)

**Decision**: `openshell sandbox create --from ghcr.io/butler54/openshell-sandbox:latest` is the mechanism for a per-sandbox custom image; no driver-config change needed (`allow_driver_config=false` only locks driver-config JSON, not image source).

**Evidence**: CLI `--from` flag (0.1.1) accepts any container image reference; the k8s driver templates the agent container from it while init containers + supervisor mounts come from generated runtime (`sandbox:0.1.1` runtime image). img-smoke creation ACCEPTED the request (reached Provisioning; interrupted by a gateway kube-watcher outage, resolved by V-REBUILD-style pod bounce). Image tag is `latest` today — acceptable for this feature; drift-guard deferred to the image-versioning follow-up.

## D3. Config injection mechanism

**Decision**: Runtime injection via `openshell sandbox exec` writing `/sandbox/.config/opencode/opencode.json` from the Git-checked-in template in `deploy/openshell/demo/opencode-matilda.json`, wrapped idempotently by `deploy/openshell/demo/inject-config.sh`.

**Rationale**: The image family expects HOME-level config under `/sandbox/.config/` (the speckit layer bootstraps exactly `/sandbox/.config/opencode/commands/`), and sandbox pods persist `/sandbox` only for the sandbox's lifetime — matching the "ephemeral demo" requirement (FR-009). `sandbox exec` is the documentable, session-agnostic path that works before any interactive `connect`.

**Key mechanism detail**: opencode resolves provider config from `$HOME/.config/opencode` layout; the template sets model `matilda-code-1.0`, `provider.matilda.options.baseURL = https://matilda.maincode.com/api/v1/code`, and `apiKey: "{env:MATILDA_API_KEY}"` — the env var value inside the sandbox is the gateway-injected `openshell:resolve:env:*` placeholder (never the real key), rewritten by the egress proxy at L7.

## D4. Session shapes

**Decision**: Dual shape per clarify Q2 — interactive via `openshell sandbox connect <name>` (Ctrl-P Ctrl-Q detaches), and one-shot via `openshell sandbox exec -n <name> -- opencode run "<prompt>"`; the runbook covers both with the smoke path scripted in `run-demo.sh`.

## D5. Allowlisted binaries

**Decision**: The matilda demo egress policy adds the agent runtime executables to the allow rule: `/usr/bin/curl` (kept; used by the one-shot smoke) plus **node and opencode entrypoints** as resolved inside the sandbox at demo time, discovered by the documented step `readlink -f $(which opencode node)` and recorded into `charts/openshell-policy/policies/sample-matilda-demo.yaml`.

**Rationale**: rego's `binary_allowed` matches kernel-resolved `/proc/<pid>/exe`, which for a Node script is the `node` binary, not the npm wrapper — hard failure unless node (and `opencode` if it preloads a native shim) is listed. The exact paths inside the `standard` image are finalized during implementation (captured as quickstart V-DEMO step 0).

## D6. sandboxctl compat attempt

**Decision**: sandboxctl invocation comes from the user's LOCAL podman gateway (freshly reset 0.1.1 state); its scope is a smoke-shaped attempt ("what would sandboxctl do here") recorded for bug reports, while ALL acceptance evidence is produced against the cluster gateway (clarify Q1). Known pre-existing blockers that become bug fodder: schema-migrating stale sandboxes (fixed already), provider/profile setup not expressible via sandboxctl today, matilda config injection not native to sandboxctl. Failures get raised as issues (FR-005) on the appropriate repo.

## D7. CLI token lifecycle friction

**Decision**: Record as known operational friction (documented); refresh-token rotation between CLI and direct scripts burns tokens; quickstart includes the device-flow re-login step when `Token is not active` appears. A Keycloak dedicated automation client (`OPENSHELL_OIDC_CLIENT_SECRET` path) is deferred — post-demo follow-up candidate, tracked alongside the monthly-login UX.

## D8. Gateway watcher recovery

**Decision**: The gateway's intermittent `resourceVersion too old` watcher error clears with a pod restart; treated as a V-REBUILD data point, not a blocker; recorded in the runbook's troubleshooting section.
