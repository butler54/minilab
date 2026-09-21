#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$root/charts/observability-config"
values="$root/values-global.yaml"

rendered=$(helm template observability-config "$chart" -f "$values" \
  --set 'global.observability.rbac.viewerGroup=minilab-viewers' \
  --set 'global.observability.rbac.editorGroup=minilab-admins')

check_subject() {
  local kind="$1" name="$2" group="$3"
  echo "$rendered" | python3 -c "
import sys, yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get('kind') == '$kind' and d.get('metadata',{}).get('name') == '$name':
        print(d.get('subjects',[{}])[0].get('name',''))
" | grep -q "$group" || { echo "$name missing or wrong group"; exit 1; }
}

# Viewer bindings render against the configured viewer group.
check_subject RoleBinding perses-dashboard-viewer minilab-viewers
check_subject RoleBinding perses-datasource-viewer minilab-viewers

# Editor bindings render against the configured editor group.
check_subject RoleBinding perses-dashboard-editor minilab-admins
check_subject RoleBinding perses-datasource-editor minilab-admins

# Cluster-scoped global datasource editor binding for the editor group.
check_subject ClusterRoleBinding perses-global-datasource-editor minilab-admins

# With no groups configured, no RBAC bindings render.
plain=$(helm template observability-config "$chart" -f "$values")
count=$(echo "$plain" | python3 -c "
import sys, yaml
print(sum(1 for d in yaml.safe_load_all(sys.stdin) if d and d.get('kind') in ('RoleBinding','ClusterRoleBinding') and d.get('metadata',{}).get('name','').startswith('perses-')))
")
[ "$count" -eq 0 ] || { echo "RBAC bindings rendered without configured groups"; exit 1; }

printf 'observability rbac validation passed\n'