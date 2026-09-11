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
  (( available >= backing + reserve )) || die "insufficient root filesystem space: need $((backing + reserve)) GiB, have $available GiB"
  printf '%s\n' "$backing"
}

validate_storage_settings() {
  local capacity=$1 efficiency=$2 rounding=$3 reserve=$4
  [[ $capacity =~ ^[1-9][0-9]*$ ]] || die "LOCAL_STORAGE_CAPACITY_GIB must be a positive integer"
  [[ $efficiency =~ ^[1-9][0-9]*$ ]] && (( efficiency <= 100 )) || die "backingEfficiency must be 1 through 100"
  [[ $rounding =~ ^[1-9][0-9]*$ ]] || die "backingRoundingGiB must be positive"
  [[ $reserve =~ ^[0-9]+$ ]] || die "hostReserveGiB must be a non-negative integer"
}

render_unit() {
  local backing_file=$1 loop_device=$2 size_gib=$3
  cat <<EOF
[Unit]
Description=Create the persistent Minilab LVMS loop device
DefaultDependencies=no
After=local-fs.target
Before=crio.service kubelet.service
Wants=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/mkdir -p -m 0750 /var/lib/minilab
ExecStart=/usr/bin/bash -ceu 'file="$backing_file"; loop="$loop_device"; size=$size_gib; bytes=\$((size * 1073741824)); if /usr/sbin/losetup "\$loop" >/dev/null 2>&1; then [ "\$(/usr/sbin/losetup -n -O BACK-FILE "\$loop")" = "\$file" ] || { echo "\$loop is mapped to another file" >&2; exit 1; }; elif [ -e "\$file" ]; then [ "\$(/usr/bin/stat -c %s "\$file")" -eq "\$bytes" ] && [ "\$(/usr/bin/du -B1 "\$file" | /usr/bin/cut -f1)" -ge "\$bytes" ] || { echo "existing backing file has incompatible size or allocation" >&2; exit 1; }; /usr/sbin/losetup "\$loop" "\$file"; else /usr/bin/fallocate -l "\${size}G" "\$file"; /usr/sbin/losetup "\$loop" "\$file"; fi'
[Install]
RequiredBy=kubelet.service
EOF
}

render_machineconfig() {
  local unit; unit=$(render_unit "$backing_file" "$loop_device" "$backing_gib")
  SYSTEMD_UNIT_BASE64=$(printf '%s' "$unit" | base64 | tr -d '\n') envsubst '${SYSTEMD_UNIT_BASE64}' < "$machineconfig_template"
}

host_available_gib() {
  oc debug "node/$1" -- chroot /host df -BG --output=avail / | tr -dc '0-9'
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

main() {
  require oc; require yq; require envsubst
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
  nodes=$(oc get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[*].metadata.name}')
  [[ $(wc -w <<<"$nodes") -eq 1 ]] || die "exactly one control-plane node is required"
  node=$nodes
  [[ -n $node ]] || die "no control-plane node found; this bootstrap supports SNO only"
  available=$(host_available_gib "$node")
  existing=$(preflight_host_storage "$node" "$backing_file" "$loop_device" "$backing_gib") || die "unsafe existing backing file or loop-device mapping on $node"
  if [[ $existing == 1 ]]; then
    (( available >= reserve )) || die "insufficient root filesystem reserve: need $reserve GiB, have $available GiB"
  else
    validate_capacity "$capacity" "$efficiency" "$rounding" "$reserve" "$available" >/dev/null
  fi
  export backing_file loop_device backing_gib
  render_machineconfig | oc apply -f -
  for _ in $(seq 1 180); do
    oc get mcp/master -o jsonpath='{.status.configuration.source[*].name}' | tr ' ' '\n' | grep -qx 99-minilab-lvms-loopback && break
    sleep 10
  done
  oc get mcp/master -o jsonpath='{.status.configuration.source[*].name}' | tr ' ' '\n' | grep -qx 99-minilab-lvms-loopback || die "machine configuration was not rendered"
  oc wait --for=condition=Updated=true mcp/master --timeout=30m
  oc wait --for=condition=Degraded=false mcp/master --timeout=30m
  verify_node "$node" "$backing_file" "$loop_device" "$backing_gib"
  printf 'bootstrap-storage: %s GiB usable, %s GiB backing, %s GiB reserve verified\n' "$capacity" "$backing_gib" "$reserve"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
