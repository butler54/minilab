# minilab

## Local Persistent Storage

This pattern supports a connected single-node OpenShift lab without a spare disk. It creates one persistent loop device for LVMS before GitOps installs Vault. It is not node-loss-resilient and must not be used as production storage.

Run `./pattern.sh make bootstrap-storage` before installation, or use `./pattern.sh make install`, which has the same bootstrap as an ordered prerequisite. The default `LOCAL_STORAGE_CAPACITY_GIB` is 100. To select an approved capacity, run `LOCAL_STORAGE_CAPACITY_GIB=80 ./pattern.sh make bootstrap-storage`.

The backing allocation is `ceil(capacityGiB / 0.85)`, rounded up to a 4 GiB boundary. The bootstrap also leaves 20 GiB free on the root filesystem. For example, 100 GiB usable capacity requires a 120 GiB backing file plus the 20 GiB reserve. Before changing capacity, remove all LVMS consumers and follow the retained-volume cleanup procedure in the feature quickstart; an existing backing file with a different size is intentionally rejected rather than resized or destroyed.

The backing file is `/var/lib/minilab/lvms-loopback.img` and its fixed mapping is `/dev/loop10`. Reruns reuse only that exact mapping and file size. If the loop device maps elsewhere, or a partial backing file has an incompatible size, bootstrap stops without changing it. Inspect `oc debug node/<sno-node> -- chroot /host systemctl status minilab-lvms-loopback.service`, correct the conflict, then rerun.

The clustergroup owns the LVMS namespace, OperatorGroup, and automatic Subscription pinned to the validated 4.22 CSV. The single least-privilege readiness Sync hook in `lvms-config` waits for the CSV, CRD, LVMCluster, CSI components, and storage class before Vault at wave `+10` can reconcile. A scheduled imperative job is deliberately not used: it cannot synchronously block the initial Vault sync. The provider shared value file sets only `vault.server.dataStorage.storageClass: lvms-loopback`; it does not make that class Kubernetes-wide default. A later supported `extraValueFiles` or explicit Helm value can select a different Vault class and wins over this default.

Run local checks with `tests/validate-pattern-config.sh`, `tests/test-bootstrap-local-storage.sh`, `tests/test-lvms-ordering.sh`, `tests/test-vault-storage-override.sh`, and `tests/test-pattern-wrapper.sh`.
