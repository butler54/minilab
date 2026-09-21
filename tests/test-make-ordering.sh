#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
db=$(make -C "$root" -qp 2>/dev/null || true)
deps=$(awk -F: '/^pattern-install:/{print $2}' <<<"$db" | tr '\n' ' ')
[[ " $deps " == *" check-bootstrap-storage "* ]] || {
  printf 'pattern-install does not depend on check-bootstrap-storage\n' >&2; exit 1;
}
[[ " $deps " != *" bootstrap-storage "* ]] || {
  printf 'pattern-install must not depend on the mutating bootstrap-storage target\n' >&2; exit 1;
}
[[ $db == *'bootstrap-storage:'* && $db == *'check-bootstrap-storage:'* ]] || {
  printf 'bootstrap-storage and check-bootstrap-storage targets are missing\n' >&2; exit 1;
}
printf 'make ordering passed\n'
