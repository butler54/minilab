#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/scripts/bootstrap-local-storage.sh"
assert_eq() { [[ $1 == "$2" ]] || { printf 'expected %s, got %s\n' "$2" "$1" >&2; exit 1; }; }
assert_eq "$(backing_gib 100 85 4)" 120
assert_eq "$(backing_gib 101 85 4)" 120
assert_eq "$(backing_gib 102 85 4)" 120
assert_eq "$(backing_gib 103 85 4)" 124
assert_eq "$(validate_capacity 100 85 4 20 140)" 120
if bash -ceu "source '$root/scripts/bootstrap-local-storage.sh'; validate_capacity 100 85 4 20 139" >/dev/null 2>&1; then printf 'insufficient space was accepted\n' >&2; exit 1; fi
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
oc_calls="$tmpdir/oc-calls"

yq() {
  if [[ $1 == eval ]]; then return 0; fi
  case $2 in
    .global.localStorage.capacityGiB) printf '100\n' ;;
    .global.localStorage.backingFilePath) printf '/var/lib/minilab/lvms-loopback.img\n' ;;
    .global.localStorage.loopDevice) printf '/dev/loop10\n' ;;
    .global.localStorage.backingEfficiency) printf '85\n' ;;
    .global.localStorage.backingRoundingGiB) printf '4\n' ;;
    .global.localStorage.hostReserveGiB) printf '20\n' ;;
  esac
}

oc() {
  printf '%q ' "$@" >> "$oc_calls"
  printf '\n' >> "$oc_calls"
  case " $* " in
    *' get nodes '*) printf 'sno.example.test\n' ;;
    *' df -BG '*) printf '200\n' ;;
    *'losetup -j "$file"'*)
      [[ ${MOCK_BACKING_FILE_OTHER_LOOP:-false} == true ]] && return 1
      [[ ${MOCK_PREFLIGHT:-safe} == safe ]] && printf 'MINILAB_EXISTING=1\n' || return 1
      ;;
    *' apply -f - '*) : ;;
  esac
}

assert_eq "$(preflight_host_storage sno.example.test /var/lib/minilab/lvms-loopback.img /dev/loop10 120)" MINILAB_EXISTING=1
[[ $(<"$oc_calls") == *'bash -ceu'* && $(<"$oc_calls") == *'/var/lib/minilab/lvms-loopback.img'* && $(<"$oc_calls") == *'/dev/loop10'* && $(<"$oc_calls") == *'stat -c %s'* && $(<"$oc_calls") == *'du -B1'* && $(<"$oc_calls") == *'losetup -n -O BACK-FILE'* ]] || {
  printf 'preflight did not use the expected fixed remote arguments\n' >&2; exit 1;
}
: > "$oc_calls"
assert_eq "$(host_available_gib sno.example.test)" 200
[[ $(<"$oc_calls") == *'df -BG --output=avail /var'* ]] || {
  printf 'available-space probe did not use the writable /var filesystem\n' >&2; exit 1;
}
: > "$oc_calls"
if (MOCK_PREFLIGHT=unsafe main) >/dev/null 2>&1; then
  printf 'unsafe backing storage state was accepted\n' >&2; exit 1
fi
[[ $(<"$oc_calls") != *'apply -f -'* ]] || { printf 'unsafe state reached MachineConfig apply\n' >&2; exit 1; }
: > "$oc_calls"
if (MOCK_BACKING_FILE_OTHER_LOOP=true main) >/dev/null 2>&1; then
  printf 'backing file attached to another loop device was accepted\n' >&2; exit 1
fi
[[ $(<"$oc_calls") == *'losetup -j "$file"'* ]] || { printf 'preflight did not inspect backing file loop mappings\n' >&2; exit 1; }
[[ $(<"$oc_calls") != *'apply -f -'* ]] || { printf 'other loop mapping reached MachineConfig apply\n' >&2; exit 1; }
: > "$oc_calls"
if (LOCAL_STORAGE_CAPACITY_GIB=invalid main) >/dev/null 2>&1; then
  printf 'malformed capacity was accepted\n' >&2; exit 1
fi
[[ ! -s $oc_calls ]] || { printf 'malformed capacity reached oc before validation\n' >&2; exit 1; }
unit=$(render_unit /var/lib/minilab/lvms-loopback.img /dev/loop10 120)
script=$(render_script)
[[ $unit == *'ExecStart=/usr/local/bin/minilab-lvms-loopback.sh "/var/lib/minilab/lvms-loopback.img" "/dev/loop10" "120"'* ]] || { printf 'unit does not invoke the separate loopback script with fixed arguments\n' >&2; exit 1; }
[[ $unit != *'$'* ]] || { printf 'unit ExecStart must not contain shell variables (systemd would expand them)\n' >&2; exit 1; }
[[ $unit == *'Before=crio.service kubelet.service'* ]] || { printf 'unit is not ordered before kubelet workloads\n' >&2; exit 1; }
[[ $unit == *'WantedBy=kubelet.service'* ]] || { printf 'unit must only want kubelet, not require it\n' >&2; exit 1; }
[[ $unit == *'RequiresMountsFor=/var/lib/minilab'* ]] || { printf 'unit must require the backing filesystem mount\n' >&2; exit 1; }
[[ $unit != *'RequiredBy=kubelet.service'* ]] || { printf 'unit must not hard-require kubelet\n' >&2; exit 1; }
[[ $unit != *'DefaultDependencies=no'* ]] || { printf 'unit must not disable default dependencies\n' >&2; exit 1; }
[[ $script == *'losetup "$loop"'* ]] || { printf 'script does not reject a conflicting loop device\n' >&2; exit 1; }
[[ $script == *'existing backing file has incompatible size'* ]] || { printf 'script does not reject an incompatible existing file\n' >&2; exit 1; }
[[ $script == *'fallocate -l "${size}G" "$file"'* ]] || { printf 'script does not allocate the backing file\n' >&2; exit 1; }
template=$(<"$root/bootstrap/machineconfigs/99-minilab-lvms-loopback.yaml.tpl")
[[ $template != *'directories:'* ]] || { printf 'MachineConfig must not declare ignition directories (MCO irreconcilable)\n' >&2; exit 1; }
[[ $template == *'${LOOPBACK_SCRIPT_BASE64}'* && $template == *'${SYSTEMD_UNIT_BASE64}'* ]] || { printf 'MachineConfig must ship both the loopback script and the unit\n' >&2; exit 1; }
printf 'bootstrap calculation, preflight, validation, conflict, unit safety, and rerun safeguards passed\n'
