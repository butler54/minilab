## Summary

On 0.1.1 the kubernetes driver's fence-verify path deletes healthy sandboxes
exactly at the 5-minute bootstrap grace boundary whenever the cluster has
transient API-server stalls even a single-digit percentage of reconcile ticks
miss. Root cause chain fully traced below; the concrete trigger on our SNO
cluster was periodic `apiserver -> etcd` gRPC dial cancellations that stall
`GET sandboxes.agents.x-k8s.io` past the gateway's 30s `read_timeout`.

## Impact

Sandboxes disappear at ~4.5-5 minutes of age with `DeleteSandbox` in the
gateway log, killed by the fence reaper while bootstrapping normally:

```
WARN openshell_driver_kubernetes::driver: could not verify sandbox-runtime
     workload generation ... error=ServiceError: client error (SendRequest)
WARN openshell_driver_kubernetes::driver: rolled back stale fail-closed
     fail-closed bootstrap
INFO ... rpc.method=DeleteSandbox sandbox_id=825bfc13-...
ERROR kube_client::client::builder: failed with error client error (SendRequest)
```

This makes any sandbox whose bootstrap window overlaps an API stall die at
exactly `SANDBOX_RUNTIME_BOOTSTRAP_GRACE` (5m) — observed repeatedly; example
sandbox `ux-c1` deleted at 4m36s.

## Trace (gateway debug logging enabled via `server.logLevel` EnvFilter)

```
01:16:03.363712 DEBUG hyper_util::client::legacy::client:
    client connection error: hyper::Error(Io, Kind(TimedOut))
01:16:03.363921 DEBUG kube_client::client::builder:
    requesting GET .../apis/agents.x-k8s.io/v1beta1/namespaces/openshell/sandboxes
01:16:03.363974 DEBUG hyper_util::client::legacy::pool:
    reuse idle connection for ("https", 172.30.0.1)
01:16:03.374400 ERROR kube_client::client::builder:
    failed with error client error (SendRequest)
01:16:03.374449 WARN driver: skipping sandbox-runtime reconciliation:
    Sandbox list failed
```

A prior pooled request times out after exactly 30s (`read_timeout` in
`driver.rs`), hyper evicts the conn, the next request reuses a stale pooled
connection that dies ~10ms later with `SendRequest`.

Server side at that same instant (kube-apiserver log):

```
E writers.go:123 "apiserver was unable to write a JSON response:
   http: Handler timeout"
E timeout.go:140 "Post-timeout activity" method="GET"
   path="/apis/agents.x-k8s.io/v1beta1/namespaces/openshell/sandboxes"
W watcher.go:331 watch chan error: etcdserver: mvcc: required revision
   has been compacted
W logging.go:55 addrConn.createTransport failed to connect to
   {Addr: "192.168.5.162:2379", ...} Err: connection error:
   "transport: Error while dialing: ... authentication handshake failed:
   context canceled"
```

The apiserver's own etcd gRPC dials fail on a suspiciously steady ~30s grid
and its etcd watchers keep re-requesting compacted revisions (287 compaction
resets and 216 handler-timeouts logged in 14h on an otherwise idle SNO), each
stalling that CRD list path past 30s. Fresh connections from other clients
(diagnostic pod curling `https://172.30.0.1` every 5s for 20 min) saw zero
failures — so this is specifically the gateway's long-lived in-cluster
connections + the 5m reap window interacting with transient server stalls.

## Code path (0.1.1)

`crates/openshell-driver-kubernetes/src/driver.rs`:

- `SANDBOX_RUNTIME_BOOTSTRAP_GRACE = 5m` (`:282`), reconcile every 30s (`:280`).
- During bootstrap, reconcile calls
  `sandbox_runtime_control_availability()` (`:3736`); if it is not
  `Available` **for any reason** — including transient `SendRequest` —
  control flows to `reap_stale_sandbox_runtime_bootstrap` (`:3743`), which
  hard-deletes the sandbox once `bootstrap_age >= 5m` (`:4029-4084`,
  `DeleteParams` preconditions + `warn!("rolled back stale fail-closed
  sandbox-runtime bootstrap")`).
- There is no retry/backoff distinguishing "resource genuinely missing" from
  "apiserver briefly unreachable", and no consecutive-failure threshold: a
  couple of unlucky 30s-interval ticks inside the 5m window doom the sandbox.

## Suggested mitigations (any of)

1. Treat transport/timeout failures (`SendRequest`, `Connection refused`,
   `Io TimedOut`) as `Unknown`/retryable in
   `sandbox_runtime_control_availability` and skip reap for that tick
   (already done at `:3769` for post-bootstrap generation checks — apply
   the same tolerance at `:3736`).
2. Require N consecutive failed verifies inside the grace window before
   reaping, or extend the grace window when recent ticks errored.
3. Make `SANDBOX_RUNTIME_BOOTSTRAP_GRACE` / `read_timeout` configurable via
   values/env instead of compile-time consts.

## Environment

- OpenShell 0.1.1 (gateway + sandbox-runtime + supervisor 0.1.1 images)
- OpenShift 4.22 SNO, kube-apiserver + etcd co-located on one node
- Gateway runs in-cluster (`openshell` ns), in-cluster kube config,
  `read_timeout=30s` (default from chart/driver code)
- `openshell gateway status` / CLI login: functional; only the fence path dies

Happy to provide the raw gateway debug log bundle and apiserver/etcd log
excerpts covering full 24h cadence histograms if useful.
