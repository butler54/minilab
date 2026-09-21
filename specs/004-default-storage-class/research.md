# Research: Default Storage Class

## Decision: A scheduled Kubernetes CronJob in the `lvms-config` chart

**Rationale**: The user clarified a dedicated scheduled Kubernetes Job (Option B). A `CronJob` in the `lvms-config` chart is self-contained, reuses the chart's existing conventions (same `ose-cli` image, same least-privilege RBAC pattern as the readiness Job), and needs no external Ansible runtime. It runs on a schedule so it also self-heals: if an operator removes the default-class annotation, the next run restores it (edge case in spec). Registering under `clusterGroup.imperative.jobs` (the coco-pattern imperative framework) was rejected: it adds the Ansible runtime and a second job-execution mechanism for a single small annotation task, contrary to Simplicity First.

**Alternatives considered**:

- Imperative framework (coco-pattern `clusterGroup.imperative.jobs` + Ansible playbook): rejected as heavier than needed; a single idempotent `oc annotate`/`oc patch` is simpler in a CronJob.
- A one-shot ArgoCD Sync hook Job (like the readiness Job): rejected because it would only run on initial sync and could not restore the default if later removed; a scheduled Job covers both install-time establishment and drift recovery.
- A declarative StorageClass manifest overriding the LVMS-generated class: rejected because LVMS owns the StorageClass; a second manifest would conflict with the operator.

## Decision: Annotate only when no default exists

**Rationale**: The user clarified (Option B) that the mechanism acts only when no storage class is already the default; an existing foreign default is left untouched. The Job's logic: list StorageClasses, check for any with `storageclass.kubernetes.io/is-default-class: "true"`; if none exists and `lvms-loopback` is present and not already default, annotate it; otherwise do nothing (idempotent). This preserves the earlier storage feature's contract that explicit storage-class choices always win and never overrides a foreign default.

**Alternatives considered**:

- Always force `lvms-loopback` as the sole default (remove others): rejected — the user chose to leave a foreign default untouched, and forcibly demoting other classes is surprising.
- Error when a foreign default exists: rejected — the user chose silent no-op for that case.

## Decision: Gate the Job behind a values flag, defaulting to enabled

**Rationale**: Operators on clusters with an existing default (or who manage defaults themselves) should be able to disable the mechanism declaratively. A `defaultStorageClass.enabled` value in the `lvms-config` chart (sourced from `global.localStorage` for consistency) renders the CronJob and its RBAC only when enabled. Default `true` for the supported lab.

**Alternatives considered**:

- Always run the Job: rejected — no escape hatch on clusters where another default is intentional.
- Use `values-global.yaml` `global.localStorage.defaultStorageClass` to enable/disable: accepted as the config surface, consistent with how storage knobs already live under `global.localStorage`.

## Decision: Least-privilege RBAC restricted to reading and patching StorageClasses

**Rationale**: The Job only needs to `get/list/watch` StorageClasses and `patch` the `lvms-loopback` StorageClass annotation. A dedicated ServiceAccount with a minimal Role (StorageClasses only) and RoleBinding, mirroring the `lvms-config-readiness` pattern, satisfies the constitution's least-privilege intent. It must also tolerate the control-plane `NoSchedule` taint (SNO) like the readiness Job.

**Alternatives considered**:

- Cluster-admin token: rejected — grossly over-privileged and against least privilege.

## Implementation Verification Required

- Confirm the `ose-cli` image in `global.lvmsCompatibility.cliImage` can read and patch StorageClasses from the CronJob pod (the existing readiness Job already uses it, so this is expected to hold).
- Confirm the exact default-class annotation behavior OpenShift scheduler expects: `storageclass.kubernetes.io/is-default-class: "true"` on a single class, and that a claim with no class binds to it.
- Confirm whether the generated `lvms-loopback` StorageClass already carries `is-default-class: "false"` (observed on target) and that the Job correctly detects and flips it to `"true"` only when no other default exists.