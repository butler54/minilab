#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat >"$tmp/bin/podman" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
  --version) printf 'podman version 5.0.0\n' ;;
  system) printf 'Name URI Identity Default\nremote ssh://example invalid true\n' ;;
  run) printf '%s\n' "$@" >"$PODMAN_CAPTURE" ;;
esac
EOF
chmod +x "$tmp/bin/podman"
PATH="$tmp/bin:$PATH" HOME="$tmp/home" PODMAN_CAPTURE="$tmp/args" LOCAL_STORAGE_CAPACITY_GIB=80 \
  bash "$root/pattern.sh" true
args=$(<"$tmp/args")
[[ $args == *$'LOCAL_STORAGE_CAPACITY_GIB'* ]]
[[ $args != *'/etc/pki:/etc/pki:ro'* && $args != *'/etc/ssl:/etc/ssl:ro'* && $args != *'/usr/share/ca-certificates:/usr/share/ca-certificates:ro'* ]]
printf 'pattern wrapper forwards storage capacity and supports remote Podman without host PKI mounts\n'
