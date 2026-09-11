apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-minilab-lvms-loopback
  labels:
    machineconfiguration.openshift.io/role: master
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      directories:
      - path: /var/lib/minilab
        mode: 0750
      files:
      - path: /etc/systemd/system/minilab-lvms-loopback.service
        mode: 0644
        contents:
          source: data:text/plain;charset=utf-8;base64,${SYSTEMD_UNIT_BASE64}
    systemd:
      units:
      - name: minilab-lvms-loopback.service
        enabled: true
