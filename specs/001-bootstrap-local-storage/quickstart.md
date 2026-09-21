# Quickstart: Validate Bootstrap Local Storage

## Prerequisites

- A supported connected SNO cluster and an authenticated `oc` context.
- A persistent host `/var` filesystem with capacity for the configured usable PVC capacity plus bootstrap overhead and normal OpenShift operating reserve.
- The pattern branch pushed to the configured remote before the standard pattern installer reconciles it.
- No existing conflicting mapping for the configured loop device.
- A maintenance window: applying the storage MachineConfig may reboot the sole node and briefly interrupt the API.

## Default Validation

1. Run `./pattern.sh make bootstrap-storage`. The script preflights the node, applies the MachineConfig, tolerates the expected API interruption during the SNO reboot, and verifies the loop device.
2. Confirm the bootstrap reports the default 100 GiB usable capacity, 120 GiB backing allocation, at least 20 GiB retained host reserve, successful systemd unit state, and a stable exact loop mapping.
3. Run `./pattern.sh make check-bootstrap-storage` to confirm the prerequisite is ready without mutating host storage.
4. Run `./pattern.sh make install`.
5. Run `./pattern.sh make validate-schema` and `./pattern.sh make argo-healthcheck`.
6. Confirm the LVMS operator, LVMCluster, generated `lvms-loopback` storage class, and its CSI components are ready.
7. Confirm Vault's persistent claim is bound to `lvms-loopback` and Vault reports ready.
8. Create a 5 GiB RWO PVC using `lvms-loopback` and a consumer pod; write then read a test value after restarting the pod.
9. Delete the test PVC and perform the documented retained-volume cleanup before repeating capacity-boundary validation.

## Configured Capacity Validation

1. Run `LOCAL_STORAGE_CAPACITY_GIB=<approved-value> ./pattern.sh make bootstrap-storage`.
2. Confirm reported usable capacity matches the selected value, backing allocation follows `ceil(capacityGiB / 0.85)` rounded to 4 GiB, and at least 20 GiB host reserve remains.
3. Complete the Default Validation steps with a PVC size within the selected usable capacity.

## Failure and Recovery Validation

1. Attempt bootstrap with a capacity exceeding available host space; confirm it fails before creating a backing file.
2. Simulate or detect a conflicting loop-device mapping; confirm bootstrap fails without changing that mapping.
3. Re-run after a successful bootstrap; confirm it reuses the same configuration and reports no duplicate resources.
4. Restart the SNO node under normal maintenance conditions; confirm the fixed mapping returns, the storage class remains available, the test PVC data is readable, and Vault becomes ready.
5. After Vault is bound and the 5 GiB validation PVC has been reclaimed, request a 100 GiB PVC and confirm it can bind; request a 101 GiB PVC and confirm it is rejected without exhausting the host filesystem.

For design fields and expected state transitions, see [data-model.md](data-model.md). For invocation and ordering guarantees, see [bootstrap-storage.md](contracts/bootstrap-storage.md).

## Target-Cluster Results

Unchecked: target-cluster validation has not been run from this workspace. Before marking this feature complete, record the target OpenShift release, LVMS catalog channel/CSV, generated StorageClass name, SNO node selector and taint, and the results of every validation above. For retained volumes, delete validation PVCs and consumers, confirm no required PV data remains, then remove only the corresponding retained PV according to the LVMS and OpenShift release documentation; never delete the backing file while LVMS consumers exist.
