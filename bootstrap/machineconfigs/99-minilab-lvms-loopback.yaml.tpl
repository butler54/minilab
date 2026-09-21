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
      files:
      - path: /usr/local/bin/minilab-lvms-loopback.sh
        mode: 0755
        contents:
          source: data:text/plain;charset=utf-8;base64,${LOOPBACK_SCRIPT_BASE64}
      - path: /etc/systemd/system/minilab-lvms-loopback.service
        mode: 0644
        contents:
          source: data:text/plain;charset=utf-8;base64,${SYSTEMD_UNIT_BASE64}
    systemd:
      units:
      - name: minilab-lvms-loopback.service
        enabled: true
