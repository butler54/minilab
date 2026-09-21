# Quickstart: Validate Default Storage Class

## Prerequisites

- The pattern installed with LVMS and the `lvms-loopback` storage class present.
- The `lvms-config` chart applied (Argo CD app `lvms-config` synced).

## Default Establishment Validation

1. Confirm no storage class is currently the default:
   ```bash
   oc get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}'
   ```
   (Expect `lvms-loopback` either absent of the annotation or `false`, and no other class `true`.)
2. Confirm the `lvms-config` app renders the scheduled Job:
   ```bash
   helm template lvms-config charts/lvms-config -f values-global.yaml | grep -E 'kind: CronJob'
   ```
3. Allow the Job's next scheduled run (or the ArgoCD-synced CronJob to trigger), then confirm:
   ```bash
   oc get storageclass lvms-loopback -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'
   # expect: true
   ```

## Implicit-Binding Validation

1. Create a PVC with no storage class and a consumer pod; confirm it binds through `lvms-loopback`.
2. Confirm a PVC that explicitly requests `lvms-loopback` (or another supported class) binds to that class, not a different default.

## Idempotence / Drift-Recovery Validation

1. Run the CronJob a second time; confirm the default annotation is unchanged and no duplicate default classes appear.
2. Temporarily remove the default annotation; confirm the next scheduled run restores it.
3. If another storage class is already default, confirm the Job does not alter it.

For the decision rule and RBAC, see [default-storage-class.md](contracts/default-storage-class.md). For the state model, see [data-model.md](data-model.md).

## Target-Cluster Results

Unchecked: target-cluster validation has not been run from this workspace. Confirm on the target OpenShift 4.22 cluster that the Job establishes the default, implicit claims bind to `lvms-loopback`, and the COO-managed Perses PVC binds (previously Pending due to no default class).