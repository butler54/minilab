# minilab

## Local Persistent Storage

This pattern supports a connected single-node OpenShift lab without a spare disk. It creates one persistent loop device for LVMS before GitOps installs Vault. It is not node-loss-resilient and must not be used as production storage.

Run `./pattern.sh make bootstrap-storage` as an explicit maintenance step before installation. Applying the storage MachineConfig can reboot the single SNO node and briefly interrupt the API; the bootstrap tolerates that expected outage. `make install` does not apply storage — it runs `check-bootstrap-storage` and stops with guidance if the prerequisite is missing. The default `LOCAL_STORAGE_CAPACITY_GIB` is 100. To select an approved capacity, run `LOCAL_STORAGE_CAPACITY_GIB=80 ./pattern.sh make bootstrap-storage`.

The backing allocation is `ceil(capacityGiB / 0.85)`, rounded up to a 4 GiB boundary. The bootstrap also leaves 20 GiB free on the `/var` filesystem. For example, 100 GiB usable capacity requires a 120 GiB backing file plus the 20 GiB reserve. Before changing capacity, remove all LVMS consumers and follow the retained-volume cleanup procedure in the feature quickstart; an existing backing file with a different size is intentionally rejected rather than resized or destroyed.

The backing file is `/var/lib/minilab/lvms-loopback.img` and its fixed mapping is `/dev/loop10`. Reruns reuse only that exact mapping and file size. If the loop device maps elsewhere, or a partial backing file has an incompatible size, bootstrap stops without changing it. The boot-time unit only *wants* kubelet (`WantedBy`), so a storage failure does not block kubelet or the API. Inspect `oc debug node/<sno-node> -- chroot /host systemctl status minilab-lvms-loopback.service`, correct the conflict, then rerun. If kubelet is down, recover from the node console instead: `journalctl -u minilab-lvms-loopback.service`, `losetup -a`, and `ls -l /var/lib/minilab`.

The clustergroup owns the LVMS namespace, OperatorGroup, and automatic Subscription pinned to the validated 4.22 CSV. The single least-privilege readiness Sync hook in `lvms-config` waits for the CSV, CRD, LVMCluster, CSI components, and storage class before Vault at wave `+10` can reconcile. The provider shared value file sets `vault.server.dataStorage.storageClass: lvms-loopback`. A later supported `extraValueFiles` or explicit Helm value can select a different Vault class and wins over this default.

The pattern also ensures an LVMS-based default storage class for workloads that request no class (for example, the COO-managed Perses server). The `lvms-config` chart declares `default: true` on the LVMS device class, which the LVMS operator natively applies to the generated `lvms-loopback` StorageClass as the cluster default. LVMS enforces a single default device class and owns the `is-default-class` annotation, so the default survives operator reconciliation. Disable it with `global.localStorage.defaultStorageClass.lvmClusterDefaultDeviceClass: false`. Explicit `storageClassName` requests are unaffected.

Run local checks with `tests/validate-pattern-config.sh`, `tests/test-bootstrap-local-storage.sh`, `tests/test-lvms-ordering.sh`, `tests/test-vault-storage-override.sh`, `tests/test-default-storage-class.sh`, and `tests/test-pattern-wrapper.sh`.

## Dashboarding and Alerting

This pattern provides dashboarding and alerting for OpenShift system workloads, application workloads, and external components using the Cluster Observability Operator (COO) and the Red Hat build of Perses. Perses dashboards are managed as code in `charts/observability-config/` and surfaced in the OpenShift console under `Observe > Dashboards (Perses)` — the single cluster-OAuth-protected access point.

- **Dashboards**: one `PersesDashboard` per domain (system, application, external). System and application dashboards query the in-cluster Thanos Querier; the external dashboard queries the COO `MonitoringStack` Prometheus, which scrapes configured external HTTP/HTTPS Prometheus exporters.
- **Single-node cluster summary**: the `Single-Node OpenShift Cluster Summary` dashboard reports node readiness, degraded cluster operators, CPU/memory capacity, and LVMS volume-group/thin-pool utilization. The pattern labels `openshift-storage` for platform monitoring so the LVMS-provided authenticated ServiceMonitor is scraped; the dashboard queries the resulting `topolvm_*` capacity series through platform Thanos.
- **Alerting**: the COO `MonitoringStack` Alertmanager routes stack alerts to PagerDuty (sole destination). The PagerDuty routing key is loaded from Vault via external-secrets and never committed to Git. Alerts resolve automatically and alert state remains visible in the platform even if delivery fails.
- **Retention**: 30 days by default, sized within the pattern's storage budget on the LVMS storage class.
- **Access control**: Perses viewer/editor roles bound to OpenShift groups declared via `global.observability.rbac`.

The observability configuration surface lives in `overrides/values-observability.yaml` (`externalTargets`, `dashboards`, `alertRules`, `rbac`, `retention`, `stackNamespace`, `storageClass`) and is applied through the pattern's shared-value-files mechanism. See `charts/observability-config/README.md` and `specs/002-deploy-dashboarding/` for the full configuration reference, contracts, and validation guide. Run local validation with `tests/test-observability-dashboards.sh`, `tests/test-observability-alerts.sh`, `tests/test-observability-configurability.sh`, `tests/test-observability-rbac.sh`, `tests/test-observability-override.sh`, and `tests/test-cluster-summary-dashboard.sh` (or `make validate-observability`).
