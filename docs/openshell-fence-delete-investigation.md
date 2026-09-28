# OpenShell fence-delete investigation (2026-09-27)

Root-cause investigation of sandboxes being deleted by the OpenShell gateway at
~4.5–5 minutes of age on the `sno.tokyo-brunch.com` cluster. Status: diagnosis
complete, no upstream fix filed (user call pending), procedural mitigation in
place. Investigation interrupted at user request; this document is the complete
record.

## Symptom

Any sandbox created on the k8s gateway could disappear at ~4.5 to 5 minutes of
age (`ux-c1` deleted at 4m36s). Gateway log sequence:

```
ERROR kube_client::client::builder: failed with error client error (SendRequest)
WARN  driver: could not verify sandbox-runtime workload generation pod=default--ux-c1
       error=ServiceError: client error (SendRequest)
WARN  driver: rolled back stale fail-closed sandbox-runtime bootstrap
       sandbox=default--ux-c1
INFO  driver: rpc.method=DeleteSandbox sandbox_id=825bfc13-...
```

`SendRequest` errors also fire when no sandbox exists ("skipping
sandbox-runtime reconciliation: Sandbox list failed"), at a roughly 6.5–12
minute cadence, always near identical sub-second marks of a minute (periodic
timer hitting a stale connection, not random load).

## Root-cause chain (five layers)

### L1 — The kill decision (gateway driver logic)

`crates/openshell-driver-kubernetes/src/driver.rs` (NVIDIA/OpenShell v0.1.1):

- `SANDBOX_RUNTIME_RECONCILE_INTERVAL = 30s` (`:280`)
- `SANDBOX_RUNTIME_BOOTSTRAP_GRACE = 5m` (`:282`)
- During bootstrap, the reconciler calls
  `sandbox_runtime_control_availability()` (`:3736`). If the result is anything
  other than `Available` — including a transient transport error — control
  flows to `reap_stale_sandbox_runtime_bootstrap` (`:3743`).
- The reaper deletes the CR once bootstrap age >= 5m (`:4029–4084`,
  delete with uid/resourceVersion preconditions, warning
  `rolled back stale fail-closed sandbox-runtime bootstrap`).
- Post-bootstrap sandboxes ARE tolerant: generation-check `Unknown` results
  warn and retry (`:3769–3775`). Only the bootstrap window is lethal.
- No retry/backoff, no consecutive-failure threshold, no configurability of
  the 5m grace. One or two unlucky 30s ticks in a 5-minute window kill a
  healthy sandbox.

### L2 — What SendRequest actually is (client mechanics)

With temporary debug logging (`server.logLevel` EnvFilter override, commit
`aea9e59`, reverted in `5833859`), a failure burst at 2026-09-28T01:16:03Z:

```
01:16:03.3637 hyper_util::client::legacy::client:
              client connection error: hyper::Error(Io, Kind(TimedOut))
01:16:03.3639 kube_client::client::builder: requesting
              GET .../apis/agents.x-k8s.io/v1beta1/namespaces/openshell/sandboxes
01:16:03.3639 hyper_util pool: reuse idle connection for ("https", 172.30.0.1)
01:16:03.3744 ERROR kube_client: failed with error client error (SendRequest)
```

A prior request timed out after exactly 30s (the gateway's kube
`read_timeout=30s`, driver.rs:761). hyper evicts that conn; the next request
reuses a stale pooled connection and fails ~10ms later. So `SendRequest` =
write/read on a pooled connection the server had silently dropped.

### L3 — The apiserver side (request stalls server-side)

kube-apiserver log at the same instant, matching the gateway's failed request
path exactly:

```
E writers.go:123 "apiserver was unable to write a JSON response:
                  http: Handler timeout"
E timeout.go:140 "Post-timeout activity" method="GET"
   path="/apis/agents.x-k8s.io/v1beta1/namespaces/openshell/sandboxes"
```

Daily volumes on an otherwise idle SNO:
- 216 `http: Handler timeout` — ALL on the sandboxes CRD path
- 287 `watch chan error: etcdserver: mvcc: required revision has been compacted`

Key specificity: ONLY the `agents.x-k8s.io` sandboxes list times out. All
other cluster traffic is informer-cache-served and unaffected.

### L4 — etcd layer (connection churn, revision churn)

apiserver → etcd gRPC transport fails on a suspiciously steady ~30s grid
(01:07:15, 01:07:45, 01:08:15, …):

```
addrConn.createTransport failed to connect to {Addr: "192.168.5.162:2379"}:
connection error: "transport: Error while dialing: ... operation was canceled"
(also: "authentication handshake failed: context canceled")
```

etcd itself shows 200ms+ "apply request took too long" bursts (40 in 14h) and
1 leader change; put rate is modest (~5.5/s). Watch resets ("required revision
has been compacted") arrive at ~30s spacing — a watcher repeatedly
re-requesting stale revisions after transport resets. The 30s grid both here
and in L2 suggests correlated timers, not load.

### L5 — Host/resource context

- SNO OCP 4.22, one node; during the diagonal window CPU requests were 94%
  (7061m/7500m) with prometheus ~984m, apiserver ~900m, argocd
  application-controller ~535m (sync-retry storm amplifying API load).
- After cleanup: 80% requests, ~3070m live — and stalls STILL occurred
  (4 gateway SendRequest + 3 apiserver handler-timeouts in the first 10
  minutes post-restart), so load amplifies but does not cause the flakiness.

## What was ruled out

- **The agent sandbox CRD itself**: `strategy: None` conversion (no webhook),
  healthy Established, 654KB schema, zero CRs present during healthy period,
  fresh cluster-admin lists complete in ~1.3s.
- **Cluster network generally**: fresh-connect probe pod curling
  `https://172.30.0.1` every 5s for 20 min on the same service IP saw ZERO
  failures (717+ successful connects) while the gateway was erroring.
- **RBAC**: gateway SA passes `auth can-i` checks; earlier diag-pod 403s were
  probe-script RBAC, not transport.
- **Image/pod stability**: supervisor + sandbox pods healthy when killed;
  deletion originates from gateway driver decision, never kubelet/OOM/infra.

## Interpretation

The lethal window is the 5-minute bootstrap grace. The gateways's quorum
lists of the sandboxes CRD (no resourceVersion → etcd round-trip) are the
only hot path that touches apiserver→etcd directly; cache-served clients
never see the intermittent etcd transport stalls. When a stall overlaps the
bootstrap window, L1 turns a transient transport hiccup into a permanent
sandbox deletion.

Open question not chased (stopped at user request): whether the gateway's
lists are truly quorum (resourceVersion unset) vs cache-served with
resourceVersion=0 — a comparative in-cluster probe of
`GET .../sandboxes` vs `GET .../sandboxes?resourceVersion=0` was prepared
(`/tmp/cvq.sh`) but aborted before data was collected. Also unchased: the
micro-cause of the 30s-grid apiserver→etcd dial cancellations (kubelet probe
cadence is a suspect; OVN conntrack keepalive is another).

## Mitigations in place

1. **Procedural (active)**: create demo sandboxes ahead of showtime; if a
   sandbox dies at ~5 min, recreate — most creates complete bootstrap inside
   a calm window. Sandboxes past bootstrap tolerate later API flaps.
2. **Runbook entry** in `docs/openshell-demo-opencode.md` (commit `3baf99d`)
   pointing here.
3. **Upstream issue text ready** as evidence-complete draft:
   `specs/009-opencode-ux-scenarios/upstream-issue-draft.md`. Suggested
   upstream fixes: treat transport failures as Unknown/retryable at
   driver.rs:3736 (same tolerance as :3769), require N consecutive failures
   before reap, make grace/read_timeout configurable.
4. **CPU freed**: diag pods deleted; sync-retry storm resolved (certgen hook
   was blocked on unschedulable 500m request due to 94% node CPU allocation).

## Incident timeline (2026-09-27/28, UTC)

- 00:15–00:45Z — `SendRequest` bursts at ~:15/:16 of minutes, 7/2/9/12 min
  gaps; `ux-c1` deleted at 00:25:16Z (created 00:20:40Z).
- 01:05Z — debug logLevel commit `aea9e59` pushed; Argo child app needed
  manual operation (children lack automated syncPolicy; parent `minilab-prod`
  has automated); sync blocked on `openshell-certgen` PreSync hook hitting
  "Insufficient cpu" (node at 94% requests).
- 01:15Z — diag pods deleted; certgen completed; gateway restarted with
  debug logging (`3baf99d` revert came later).
- 01:16:03Z — definitive burst captured (L2+L3 evidence above).
- 01:18Z — etcd/etcdctl direct access impractical (no client certs on etcd
  pod mount); Prometheus used instead (put rate 5.5/s, no storm).
- ~01:20Z — debug logging reverted (`5833859`); matilda provider persisted
  across restarts (SQLite not wiped this day).
- Later — user rejected premature upstream filing; NVIDIA/OpenShell#3758
  closed as not-planned with retraction comment; evidence preserved in-repo.

## Files and commits

- `docs/openshell-fence-delete-investigation.md` — this document.
- `docs/openshell-demo-opencode.md` troubleshooting entry (commit `3baf99d`).
- `specs/009-opencode-ux-scenarios/upstream-issue-draft.md` — filing-ready
  upstream issue text (commit `b793e1b`).
- Debug-toggle commits: `aea9e59` (add logLevel), `5833859` (revert).
- Diag assets (ephemeral): `/tmp/apidiag/` pods, `/tmp/cvq.sh` (aborted
  comparative probe).
- Upstream: NVIDIA/OpenShell#3758 (filed, then closed as premature at user
  direction 2026-09-27; can be reopened or refiled from the in-repo draft).

## Impact on feature 009

SC-002 (multi-sandbox ≥5-minute stable overlap) is at risk from this defect:
any sandbox created inside an API-stall window can be reaped at the 5-minute
mark. Plan A: run scenario smoke checks with sandbox creation done in a
pre-step, verifying survival past the 5-minute mark before executing the
scenario proper. Long-term: unblocked only by the upstream fix (or a
configurable-grace escape hatch) landing in a released version.
