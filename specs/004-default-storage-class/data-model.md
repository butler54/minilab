# Data Model: Default Storage Class

## Default Storage Class State

| Field | Meaning | Validation |
|-------|---------|------------|
| `storageClassName` | The LVMS-based class intended as default | Must equal the generated LVMS class (`lvms-loopback`) |
| `isDefault` | Whether the class is the cluster-wide default | Reflects `storageclass.kubernetes.io/is-default-class` annotation |
| `foreignDefaultPresent` | Whether any other class is already default | Detected by the Job before acting |

**Lifecycle**: LVMS generates the class -> no default exists -> Job annotates class as default -> implicit claims bind to it. If an operator removes the annotation, the next scheduled run restores it. If a foreign default appears, the Job does not act.

## Default-Storage Mechanism

| Field | Meaning | Validation |
|-------|---------|------------|
| `enabled` | Whether the scheduled Job is rendered | Values flag, default `true` |
| `schedule` | Cron expression for the Job | Regular CronJob schedule (e.g. every 10 minutes) |
| `serviceAccount` | Least-privilege identity for the Job | Dedicated SA with StorageClass read/patch only |
| `cliImage` | Image running the check-and-annotate logic | Reuses `global.lvmsCompatibility.cliImage` |
| `storageClassName` | Class the Job targets | `global.localStorage.storageClassName` |

**Relationship**: One default-storage mechanism manages one target class. The mechanism's decision rule: act only when `foreignDefaultPresent == false` and the target class is present and not already default.

## Storage Choice Model

| Choice | Binding target |
|--------|----------------|
| No storage class requested | The cluster default (`lvms-loopback` after the mechanism runs) |
| Explicit supported class requested | The explicitly requested class (unchanged behavior) |

**Relationship**: The mechanism only affects implicit requests; explicit requests are unaffected (SC-003).