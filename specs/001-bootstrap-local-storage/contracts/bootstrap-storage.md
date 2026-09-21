# Bootstrap Storage Contract

## Make Interface

| Invocation | Contract |
|------------|----------|
| `make bootstrap-storage` | Validates and establishes the MachineConfig, backing file, systemd unit, and fixed loop-device mapping only. It is safe to rerun after success. Applying the MachineConfig may reboot the sole SNO node and briefly interrupt the API; the bootstrap tolerates that expected outage. |
| `make check-bootstrap-storage` | Read-only verification that the storage MachineConfig is applied, the machine config pool is not degraded, and the backing file and fixed loop mapping are valid. It never changes host storage. |
| `make install` | Runs `check-bootstrap-storage` as an ordered prerequisite of `pattern-install`. It does not apply storage or claim LVMS, StorageClass, or Vault readiness; T006 has not verified the framework readiness semantics. |
| `LOCAL_STORAGE_CAPACITY_GIB=<integer> make bootstrap-storage` | Selects usable local PVC capacity for this invocation. The omitted value is `100`. |

## Exit Behavior

| Condition | Expected result |
|-----------|-----------------|
| Clean supported SNO with sufficient host capacity | The backing file, successful unit state, and exact fixed loop mapping are verified. |
| Rerun after success | Completes without duplicating the backing file, loop mapping, or usable storage configuration. |
| Insufficient host capacity | Fails before changing host storage and states required versus available capacity. |
| Fixed loop device maps to another file | Fails without remapping or selecting another device. |
| Existing incompatible backing configuration | Fails with recovery guidance; does not resize, recreate, or destroy it. |
| LVMS or generated storage class not ready during `make install` | Fails before Vault installation continues. |

## GitOps Ordering Contract

| Component | Required order |
|-----------|----------------|
| Host loopback MachineConfig | Established by bootstrap before pattern installation |
| LVMS namespace, OperatorGroup, and Subscription | Owned by `clusterGroup.namespaces` and `clusterGroup.subscriptions` in `openshift-storage` |
| LVMS configuration application | `lvms-config` at sync wave `-10`, containing the single LVMS Sync hook |
| Vault application | Sync wave `+10` and explicit `lvms-loopback` persistence class |

These waves and hook annotations express the intended order. Until T006 verifies the Validated Patterns framework support, they are not a claimed readiness or blocking guarantee.
