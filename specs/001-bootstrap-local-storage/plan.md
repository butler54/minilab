# Implementation Plan: Bootstrap Local Storage

**Branch**: `001-bootstrap-local-storage` | **Date**: 2026-09-11 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-bootstrap-local-storage/spec.md`

## Summary

Provide 100 GiB of configurable local dynamic PVC capacity for the single-node lab, then make Vault use the resulting `lvms-loopback` storage class by default. `bootstrap-storage` establishes and verifies only the persistent loopback prerequisite. `pattern-install` depends on it, then `clusterGroup` owns the `openshift-storage` namespace, OperatorGroup, and LVMS Subscription. The single `lvms-config` application has a Sync hook at wave `-10`; Vault is configured at wave `+10`. T006 has not verified framework ordering or hook readiness semantics, so this plan makes no stronger readiness guarantee.

## Technical Context

**Language/Version**: GNU Make, Bash, YAML, Helm, and Ansible; versions supplied by the Validated Patterns utility container.

**Primary Dependencies**: Validated Patterns `rhvp.cluster_utils`, OpenShift Machine Config Operator, OpenShift LVM Storage Operator, Argo CD, and the HashiCorp Vault pattern chart.

**Storage**: One persistent, preallocated loopback backing file on the SNO host root filesystem; one LVMS thin pool providing 100 GiB of usable, non-overprovisioned RWO PVC capacity by default. Backing size is `ceil(capacityGiB / 0.85)` rounded up to 4 GiB; bootstrap requires that allocation plus a 20 GiB host reserve.

**Testing**: Shell tests for capacity calculation, unsafe mapping rejection, and idempotence; Helm render tests; Make dependency tests; YAML parsing; `oc` readiness checks; and end-to-end PVC write/read verification across pod and node restart.

**Target Platform**: Connected, supported single-node OpenShift lab with sufficient persistent root filesystem capacity; loopback-backed LVMS is explicitly lab-only and has no node-loss protection.

**Project Type**: Validated Pattern repository with Make/Ansible bootstrap and Helm/Argo CD GitOps configuration.

**Performance Goals**: Verify the loop-device prerequisite before installation; make 100 GiB usable capacity available before Vault creates its PVC; preserve data across pod and node restarts; do not allocate more PVC capacity than the backing store can support.

**Constraints**: No unused disk is available; bootstrap must be idempotent and fail closed on an occupied loop device, an existing incompatible configuration, or insufficient host capacity. The backing allocation includes thin-pool metadata and operational headroom beyond the 100 GiB usable capacity. Real secrets remain outside Git.

**Scale/Scope**: One `LVMCluster` and one SNO node. Capacity is configurable per installation. The storage class can serve multiple workloads, but only Vault receives the pattern default in this feature.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Plan response | Status |
|-----------|---------------|--------|
| GitOps-First | The MachineConfig, `clusterGroup` namespace and Subscription declarations, LVMCluster configuration hook, and Vault override are versioned in Git. Argo CD reconciles post-bootstrap resources. | Pass |
| Imperative Only Second | The pre-install action is the documented, idempotent exception needed to establish storage before dependent GitOps workloads can reconcile. It applies only Git-tracked desired state and fails closed. | Pass |
| Helm Only, No Kustomize | Operator configuration, readiness resources, and overrides are implemented as Helm charts and values; no Kustomize artifacts are introduced. | Pass |
| Simplicity First | One stable loop device, one LVMCluster, one storage class, and two small configuration charts avoid additional storage systems. This accepts SNO-local durability limits rather than adding replication. | Pass |

**Post-design re-check**: Pass. The design introduces no unmanaged runtime resource, committed secret, Kustomize overlay, or unjustified component beyond the required local storage provider.

## Project Structure

### Documentation (this feature)

```text
specs/001-bootstrap-local-storage/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/bootstrap-storage.md
└── tasks.md                 # Created by /speckit.tasks
```

### Source Code (repository root)

```text
Makefile                                      # Makes pattern-install depend on bootstrap-storage before common install target
scripts/bootstrap-local-storage.sh            # Validates and verifies bootstrap MachineConfig, unit, backing file, and loop mapping
bootstrap/machineconfigs/                     # Git-tracked MachineConfig template and loopback systemd unit
charts/lvms-operator/                         # Retired local operator chart; clusterGroup owns namespace, OperatorGroup, and Subscription
charts/lvms-config/                           # Helm chart: LVMCluster and the single LVMS Sync hook
overrides/values-storage-lvm.yaml             # Provider-selected Vault persistence override with lvms-loopback default
values-global.yaml                            # Global configurable local-storage capacity defaults
values-prod.yaml                              # Ordered LVMS and Vault application definitions
tests/                                        # Shell, render, and end-to-end validation coverage
```

**Structure Decision**: Keep all declarative resources in local Helm charts and values files. Keep the sole imperative prerequisite in `scripts/`, with its persistent host configuration represented by the MachineConfig template under `bootstrap/`. Follow the provider-selected `sharedValueFiles` override model used by coco-pattern for Vault storage configuration.

## Complexity Tracking

No constitution violations require an exception beyond the approved, documented bootstrap exception. The loopback-backed local volume is intentionally limited to the SNO lab and is not a production durability design.
