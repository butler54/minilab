#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
values_file=${VALUES_FILE:-"$repo_root/values-global.yaml"}
machineconfig_template="$repo_root/bootstrap/machineconfigs/99-minilab-lvms-loopback.yaml.tpl"

die() { printf 'bootstrap-storage: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

ceil_div() { local n=$1 d=$2; printf '%s\n' "$(( (n + d - 1) / d ))"; }
round_up() { local n=$1 unit=$2; printf '%s\n' "$(( ((n + unit - 1) / unit) * unit ))"; }
backing_gib() {
  local capacity=$1 efficiency=$2 rounding=$3
  round_up "$(ceil_div "$((capacity * 100))" "$efficiency")" "$rounding"
}

validate_capacity() {
  local capacity=$1 efficiency=$2 rounding=$3 reserve=$4 available=$5
  [[ $capacity =~ ^[1-9][0-9]*$ ]] || die "LOCAL_STORAGE_CAPACITY_GIB must be a positive integer"
  [[ $efficiency =~ ^[1-9][0-9]*$ ]] && (( efficiency <= 100 )) || die "backingEfficiency must be 1 through 100"
  [[ $rounding =~ ^[1-9][0-9]*$ ]] || die "backingRoundingGiB must be positive"
  [[ $reserve =~ ^[0-9]+$ ]] || die "hostReserveGiB must be a non-negative integer"
  local backing; backing=$(backing_gib "$capacity" "$efficiency" "$rounding")
  (( available >= backing + reserve )) || die "insufficient /var filesystem space: need $((backing + reserve)) GiB, have $available GiB"
  printf '%s\n' "$backing"
}

validate_storage_settings() {
  local capacity=$1 efficiency=$2 rounding=$3 reserve=$4
  [[ $capacity =~ ^[1-9][0-9]*$ ]] || die "LOCAL_STORAGE_CAPACITY_GIB must be a positive integer"
  [[ $efficiency =~ ^[1-9][0-9]*$ ]] && (( efficiency <= 100 )) || die "backingEfficiency must be 1 through 100"
  [[ $rounding =~ ^[1-9][0-9]*$ ]] || die "backingRoundingGiB must be positive"
  [[ $reserve =~ ^[0-9]+$ ]] || die "hostReserveGiB must be a non-negative integer"
}

render_script() {
  cat <<'EOF'
#!/usr/bin/bash
set -euo pipefail
file=$1
loop=$2
size=$3
bytes=$((size * 1073741824))

if losetup "$loop" >/dev/null 2>&1; then
  [ "$(losetup -n -O BACK-FILE "$loop")" = "$file" ] || { echo "$loop is mapped to another file" >&2; exit 1; }
elif [ -e "$file" ]; then
  [ "$(stat -c %s "$file")" -eq "$bytes" ] && [ "$(du -B1 "$file" | cut -f1)" -ge "$bytes" ] || { echo "existing backing file has incompatible size or allocation" >&2; exit 1; }
  losetup "$loop" "$file"
else
  fallocate -l "${size}G" "$file"
  losetup "$loop" "$file"
fi
EOF
}

render_unit() {
  local backing_file=$1 loop_device=$2 size_gib=$3
  cat <<EOF
[Unit]
Description=Create the persistent Minilab LVMS loop device
RequiresMountsFor=/var/lib/minilab
After=local-fs.target
Before=crio.service kubelet.service
Wants=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/mkdir -p -m 0750 /var/lib/minilab
ExecStart=/usr/local/bin/minilab-lvms-loopback.sh "$backing_file" "$loop_device" "$size_gib"
[Install]
WantedBy=kubelet.service
EOF
}

render_machineconfig() {
  local unit script unit_b64 script_b64 template
  unit=$(render_unit "$backing_file" "$loop_device" "$backing_gib")
  script=$(render_script)
  unit_b64=$(printf '%s' "$unit" | base64 | tr -d '\r\n')
  script_b64=$(printf '%s' "$script" | base64 | tr -d '\r\n')
  template=$(cat "$machineconfig_template")
  template=${template//'${LOOPBACK_SCRIPT_BASE64}'/$script_b64}
  template=${template//'${SYSTEMD_UNIT_BASE64}'/$unit_b64}
  printf '%s\n' "$template"
}

host_available_gib() {
  local node=$1 out
  out=$(oc debug "node/$node" -- chroot /host df -BG --output=avail /var) || return 1
  [[ $out =~ ([0-9]+) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

preflight_host_storage() {
  local node=$1 expected_file=$2 expected_loop=$3 expected_size=$4
  local script
  script=$(cat <<'EOF'
set -euo pipefail
file=$1
loop=$2
size=$3
bytes=$((size * 1073741824))

if [ -e "$file" ]; then
  [ "$(stat -c %s "$file")" -eq "$bytes" ] || exit 1
  [ "$(du -B1 "$file" | cut -f1)" -ge "$bytes" ] || exit 1
  existing=1
else
  existing=0
fi

if losetup "$loop" >/dev/null 2>&1; then
  [ "$existing" -eq 1 ] || exit 1
  [ "$(losetup -n -O BACK-FILE "$loop")" = "$file" ] || exit 1
fi

# The backing file must not be shared with another loop device.
while IFS=: read -r mapped_loop _; do
  [ -z "$mapped_loop" ] || [ "$mapped_loop" = "$loop" ] || exit 1
done < <(losetup -j "$file")

printf 'MINILAB_EXISTING=%d\n' "$existing"
EOF
)
  # Pass values as positional parameters so the remote script remains fixed.
  oc debug "node/$node" -- chroot /host bash -ceu "$script" bash "$expected_file" "$expected_loop" "$expected_size"
}

verify_node() {
  local node=$1 expected_file=$2 expected_loop=$3 expected_size=$4
  local script
  script=$(cat <<EOF
set -euo pipefail
systemctl is-active --quiet minilab-lvms-loopback.service
[ "\$(stat -c %s '$expected_file')" -eq $((expected_size * 1073741824)) ]
[ "\$(du -B1 '$expected_file' | cut -f1)" -ge $((expected_size * 1073741824)) ]
[ "\$(losetup -n -O BACK-FILE '$expected_loop')" = '$expected_file' ]
EOF
)
  oc debug "node/$node" -- chroot /host bash -ceu "$script"
}

machineconfig_name=99-minilab-lvms-loopback

load_config() {
  require oc; require yq
  [[ -f $values_file ]] || die "values file does not exist: $values_file"
  yq eval '.' "$values_file" >/dev/null
  capacity=${LOCAL_STORAGE_CAPACITY_GIB:-$(yq -r '.global.localStorage.capacityGiB' "$values_file")}
  backing_file=$(yq -r '.global.localStorage.backingFilePath' "$values_file")
  loop_device=$(yq -r '.global.localStorage.loopDevice' "$values_file")
  efficiency=$(yq -r '.global.localStorage.backingEfficiency' "$values_file")
  rounding=$(yq -r '.global.localStorage.backingRoundingGiB' "$values_file")
  reserve=$(yq -r '.global.localStorage.hostReserveGiB' "$values_file")
  [[ $backing_file == /var/lib/minilab/lvms-loopback.img ]] || die "backingFilePath must be /var/lib/minilab/lvms-loopback.img"
  [[ $loop_device == /dev/loop10 ]] || die "loopDevice must be /dev/loop10"
  validate_storage_settings "$capacity" "$efficiency" "$rounding" "$reserve"
  backing_gib=$(backing_gib "$capacity" "$efficiency" "$rounding")
}

resolve_node() {
  local nodes
  nodes=$(oc get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].metadata.name}')
  [[ $(wc -w <<<"$nodes") -eq 1 ]] || die "exactly one control-plane node is required"
  node=$nodes
  [[ -n $node ]] || die "no control-plane node found; this bootstrap supports SNO only"
}

preflight_existing() {
  local raw
  raw=$(preflight_host_storage "$node" "$backing_file" "$loop_device" "$backing_gib") || return 1
  [[ $raw =~ ^MINILAB_EXISTING=([01])$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# The sole SNO node may reboot during MachineConfig rollout, which interrupts the
# API. This loop treats transport failures as expected, requires the node to
# actually converge onto a NEW rendered configuration, and only fails on a
# persistent degraded condition or timeout.
wait_for_convergence() {
  local pre_current=$1
  local mc_json degraded updated current desired ready
  local deadline=$(( SECONDS + 1800 ))
  local degraded_polls=0
  while (( SECONDS < deadline )); do
    if ! mc_json=$(oc get mcp/master -o json 2>/dev/null); then
      printf 'bootstrap-storage: API unavailable during rollout (expected while SNO reboots), retrying...\n' >&2
      degraded_polls=0
      sleep 10
      continue
    fi
    degraded=$(printf '%s' "$mc_json" | yq -r '.status.conditions[] | select(.type=="Degraded") | .status' 2>/dev/null || true)
    updated=$(printf '%s' "$mc_json" | yq -r '.status.conditions[] | select(.type=="Updated") | .status' 2>/dev/null || true)
    current=$(oc get node "$node" -o jsonpath='{.metadata.annotations.machineconfiguration\.openshift\.io/currentConfig}' 2>/dev/null || true)
    desired=$(oc get node "$node" -o jsonpath='{.metadata.annotations.machineconfiguration\.openshift\.io/desiredConfig}' 2>/dev/null || true)
    ready=$(oc get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ $updated == True && $ready == True && -n $current && $current == "$desired" && $current != "$pre_current" ]]; then
      return 0
    fi
    # A freshly applied MachineConfig can clear a pre-existing degraded state only
    # after the render controller re-renders the pool. Treat Degraded as fatal only
    # after it persists across consecutive successful polls.
    if [[ $degraded == True ]]; then
      degraded_polls=$((degraded_polls + 1))
      if (( degraded_polls >= 6 )); then
        local message
        message=$(printf '%s' "$mc_json" | yq -r '.status.conditions[] | select(.type=="Degraded") | .message' 2>/dev/null || true)
        die "machine config pool degraded during rollout: ${message:-see 'oc describe mcp master'}"
      fi
    else
      degraded_polls=0
    fi
    sleep 10
  done
  die "timed out waiting for $machineconfig_name rollout; inspect 'oc describe mcp master'"
}

bootstrap_storage() {
  load_config
  resolve_node
  local available existing
  available=$(host_available_gib "$node") || die "could not determine available /var space on $node"
  existing=$(preflight_existing) || die "unsafe existing backing file or loop-device mapping on $node"
  if [[ $existing == 1 ]]; then
    (( available >= reserve )) || die "insufficient /var filesystem reserve: need $reserve GiB, have $available GiB"
  else
    validate_capacity "$capacity" "$efficiency" "$rounding" "$reserve" "$available" >/dev/null
  fi
  local pre_current apply_out
  pre_current=$(oc get node "$node" -o jsonpath='{.metadata.annotations.machineconfiguration\.openshift\.io/currentConfig}' 2>/dev/null || true)
  printf 'bootstrap-storage: applying %s; this may reboot the sole SNO node and briefly interrupt the API\n' "$machineconfig_name" >&2
  export backing_file loop_device backing_gib
  apply_out=$(render_machineconfig | oc apply -f - 2>&1) || die "failed to apply MachineConfig $machineconfig_name"
  printf '%s\n' "$apply_out" >&2
  if [[ $apply_out != *'unchanged'* ]]; then
    wait_for_convergence "$pre_current"
  fi
  verify_node "$node" "$backing_file" "$loop_device" "$backing_gib"
  printf 'bootstrap-storage: %s GiB usable, %s GiB backing, %s GiB reserve verified\n' "$capacity" "$backing_gib" "$reserve"
}

check_bootstrap_storage() {
  load_config
  resolve_node
  oc get machineconfig "$machineconfig_name" >/dev/null 2>&1 || die "storage MachineConfig $machineconfig_name is not applied; run 'make bootstrap-storage' first"
  local degraded
  degraded=$(oc get mcp/master -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}' 2>/dev/null || true)
  [[ $degraded != True ]] || die "machine config pool is degraded; resolve it before installation"
  verify_node "$node" "$backing_file" "$loop_device" "$backing_gib" || die "storage backing is not ready; run 'make bootstrap-storage' first"
  printf 'check-bootstrap-storage: %s GiB backing verified on %s\n' "$backing_gib" "$node"
}

main() {
  case ${1:-} in
    check) check_bootstrap_storage ;;
    *) bootstrap_storage ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
