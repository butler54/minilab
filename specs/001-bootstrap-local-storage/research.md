# Research: Bootstrap Local Storage

## Decision: Use a persistent loopback-backed LVM Storage Operator device class

**Rationale**: The single-node lab has no spare disk, while the LVM Storage Operator supports an explicit loop-device path for testing. A preallocated persistent backing file avoids sparse-file overcommit. The bootstrap exposes `LOCAL_STORAGE_CAPACITY_GIB`, defaulting to `100`. It allocates `ceil(capacityGiB / 0.85)` GiB rounded up to a 4 GiB boundary, which produces a 120 GiB backing file at the default, and requires an additional 20 GiB free host reserve. The storage class must have `WaitForFirstConsumer`, `Retain`, and an overprovision ratio of `1`; a claim larger than configured usable capacity is rejected.

**Alternatives considered**:

- Add a physical disk: unavailable in the target lab.
- Use ephemeral storage: cannot safely support Vault data across restart.
- Make the loopback class a cluster-wide default: rejected because it can unexpectedly bind unrelated claims when another default exists.
- Use another distributed storage system: rejected as disproportionate for one node and contrary to the simplicity constraint.

## Decision: Establish the loop device with a MachineConfig applied by a Make bootstrap

**Rationale**: The host-side loop device must exist before LVMS discovers it, and it must be reattached across reboot before kubelet workloads start. The bootstrap script applies a Git-tracked MachineConfig containing a systemd one-shot unit that creates the backing file only when absent, verifies its size and available host capacity, and associates the same backing file with one fixed loop device. After machine-configuration rollout, the script verifies unit success, backing-file allocation, and the exact loop mapping before it succeeds. It fails if the fixed device maps to another file and never recreates or resizes an existing LVMS-consumed backing file. The unit uses `WantedBy=kubelet.service` rather than `RequiredBy` so a storage failure cannot block kubelet or the API, and the MachineConfig omits Ignition `storage.directories` because the MCO rejects directory reconciliation against a running cluster (`ignition directories section contains changes`). Applying the MachineConfig may reboot the sole node and briefly interrupt the API, which the bootstrap tolerates.

**Alternatives considered**:

- Run ad-hoc node commands: rejected because they are not declarative, repeatable, or reboot-safe.
- Attach any free loop device dynamically: rejected because device identity can change across runs and jeopardize recovery.
- Create the file only in the bootstrap container: rejected because it does not configure the OpenShift node persistently.

## Decision: Use clustergroup operator ownership and one configuration readiness hook

**Rationale**: The clustergroup owns the LVMS namespace, OperatorGroup, and automatic Subscription, avoiding a local chart that duplicates framework ownership. One least-privilege Sync hook in the configuration chart waits for the pinned CSV, controller deployment, CRD, `LVMCluster`, generated storage class, and CSI components. Vault at wave `+10` cannot advance until that check succeeds. The scheduled imperative framework is not used for an initial readiness gate because it cannot synchronously block Vault reconciliation. `bootstrap-storage` does not claim LVMS or StorageClass readiness; those are post-install checks.

**Alternatives considered**:

- Keep separate operator and operator-readiness charts: rejected because the clustergroup already owns namespace, OperatorGroup, and Subscription, and a second readiness Job/RBAC set is redundant.
- Rely on application creation order without waves: rejected because application ordering is not a readiness guarantee.
- Use a Vault retry loop as the dependency control: rejected because it masks failed storage prerequisites.

## Decision: Configure Vault explicitly, not by changing the Kubernetes-wide storage default

**Rationale**: The feature requires Vault to use the local class by default while allowing other workloads to opt in. Follow coco-pattern's provider-selected shared-value-file pattern: add `overrides/values-storage-lvm.yaml`, set `vault.server.dataStorage.storageClass: lvms-loopback`, and add that file through `clusterGroup.sharedValueFiles` after base values. This preserves any existing cluster-wide default; a later, explicitly selected value file remains the documented override mechanism.

**Alternatives considered**:

- Mark the class as Kubernetes default: rejected due to competing-default ambiguity and unintended workload placement.
- Require users to supply a Vault override: rejected because it defeats the requested safe default.

## Implementation Verification Required

The connected OpenShift 4.22.8 target has one control-plane node. Its `redhat-operators` catalog exposes `stable-4.22` and `lvms-operator.v4.22.0`; `values-global.yaml` is the single compatibility configuration for that channel, CSV, readiness target, and 4.22 CLI image. The generated StorageClass still cannot be confirmed until the LVMCluster has reconciled.

The target node has control-plane, master, and worker labels with no taints. The configuration selects the control-plane label and retains the harmless `NoSchedule` toleration. The exact generated StorageClass name remains a target-cluster check.

The target's clustergroup 0.9.58 deployment emits multi-source value files and child-application sync waves. This repository's interpolated `sharedValueFiles` and hook behavior still require deployment verification.

## Decision: Retain one synchronous configuration readiness hook

**Rationale**: The Validated Patterns imperative framework runs scheduled, idempotent Ansible jobs and cannot synchronously prevent Vault's initial Argo CD reconciliation. The framework's `clusterGroup.namespaces` and `clusterGroup.subscriptions` now own LVMS installation. A single least-privilege Sync hook remains in the LVMS configuration chart to verify the already-applied LVMCluster, generated StorageClass, and CSI workloads before the later Vault wave. The redundant operator readiness application and its Job/RBAC resources were removed.

**Alternatives considered**:

- Scheduled imperative playbook: rejected because its schedule cannot form an initial installation gate.
- A separate operator readiness application: rejected because the framework Subscription scaffold owns operator installation and its reconciliation order; the configuration hook supplies the required post-configuration readiness boundary.
