# Default Storage Class Contract

## Values Interface

| Value | Contract |
|-------|----------|
| `global.localStorage.defaultStorageClass.enabled` | When true, renders the scheduled Job that establishes the LVMS class as default; default `true`. |
| `global.localStorage.defaultStorageClass.schedule` | Cron schedule for the Job (default every 10 minutes). |
| `global.localStorage.storageClassName` | The LVMS class the Job targets (existing value, `lvms-loopback`). |
| `global.lvmsCompatibility.cliImage` | Image running the Job (existing value). |

## Decision Contract

| Condition | Expected result |
|-----------|-----------------|
| No storage class is the cluster default, and `lvms-loopback` exists | Job annotates `lvms-loopback` with `is-default-class: "true"` |
| `lvms-loopback` already the default | No-op (idempotent) |
| Another class is already the default | No-op; foreign default untouched |
| `lvms-loopback` not yet present | Job exits (retry on next schedule) without creating it |
| Operator removes the annotation | Next scheduled run restores it |

## Idempotence Invariants

| Invariant | Verification |
|-----------|--------------|
| Repeated runs never create a duplicate class or conflicting default | Run the Job twice; class annotation unchanged after first successful run |
| Explicit storage choices unaffected | A claim naming a supported class binds to it, not the default |

## RBAC Contract

| Permission | Scope |
|------------|-------|
| `get/list/watch` StorageClasses | cluster-scoped |
| `patch` StorageClasses | cluster-scoped (target class annotation) |
| No other permissions | least-privilege |