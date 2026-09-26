#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Contract: specs/006-openshell-gitops-install/contracts/secrets-contract.md
# 1. Every ExternalSecret remoteRef key must be derived from the vaultPrefix
#    declared for that secret in values-secret.yaml.template (hub|global —
#    alignment is what makes the path valid, per PR review).
# 2. No secret literals anywhere in charts/ or values files.
python3 - "$root" <<'EOF'
import os, re, sys, yaml

root = sys.argv[1]
fail = []

# Derive expected vault paths from the seed template (single source of truth).
seed = yaml.safe_load(open(os.path.join(root, "values-secret.yaml.template")))
expected_key = {}
for entry in seed.get("secrets", []):
    name = entry.get("name", "")
    prefixes = entry.get("vaultPrefixes", [])
    if prefixes and name.startswith("openshell"):
        expected_key[name] = prefixes[0]
assert len(expected_key) == 5, f"expected 5 openshell vault entries, got {len(expected_key)}"

# (ExternalSecret template -> its openshell-<name> secret)
expected = {
    "openshell-platform/templates/openshell-kek-es.yaml": {
        "vault_name": "openshell-gateway-kek",
        "property": "kek",
        "secretKey": "key-encryption-key",
        "target": "openshell-kek",
        "namespace": "openshell",
        "chart": "openshell-platform",
        "extra_sets": [],
    },
    "cert-manager-config/templates/cloudflare-token-es.yaml": {
        "vault_name": "openshell-cloudflare",
        "property": "api-token",
        "secretKey": "api-token",
        "target": "cloudflare-api-token",
        "namespace": "cert-manager",
        "chart": "cert-manager-config",
        "extra_sets": [],
    },
    "openshell-demo/templates/demo-assets.yaml": {
        "vault_name": "openshell-openai",
        "property": "api-key",
        "secretKey": "api-key",
        "target": "openai-api-key",
        "namespace": "openshell",
        "chart": "openshell-demo",
        "extra_sets": ["global.openshell.demo.enabled=true"],
    },
}

def chart_values(chart):
    path = os.path.join(root, "charts", chart, "values.yaml")
    return yaml.safe_load(open(path))

def render(chart, extra_sets=None):
    import subprocess
    base = root
    cmd = ["helm", "template", chart, os.path.join(base, "charts", chart),
           "-f", os.path.join(base, "values-global.yaml"),
           "-f", os.path.join(base, "overrides/values-openshell.yaml"),
           "--set", "global.openshell.enabled=true"]
    for s in (extra_sets or []):
        cmd += ["--set", s]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        fail.append(f"helm template {chart} failed: {out.stderr.strip()[:400]}")
        return []
    return [d for d in yaml.safe_load_all(out.stdout) if d]

for rel, want in expected.items():
    docs = render(want["chart"], want.get("extra_sets"))
    es = [d for d in docs if d and d.get("kind") == "ExternalSecret"]
    if not es:
        fail.append(f"{rel}: no ExternalSecret rendered")
        continue
    found = False
    for d in es:
        meta = d.get("metadata", {})
        spec = d.get("spec", {})
        if meta.get("namespace") != want["namespace"]:
            fail.append(f"{rel}: wrong namespace {meta.get('namespace')}")
            continue
        if spec.get("target", {}).get("name") != want["target"]:
            fail.append(f"{rel}: wrong target {spec.get('target',{}).get('name')}")
            continue
        for entry in spec.get("data", []):
            rr = entry.get("remoteRef", {})
            key = rr.get("key", "")
            prefix = expected_key.get(want["vault_name"])
            expected_path = f"secret/data/{prefix}/{want['vault_name']}"
            if key != expected_path:
                fail.append(f"{rel}: remoteRef key {key!r} != derived path {expected_path!r} "
                            f"(vaultPrefix={prefix!r} from values-secret.yaml.template)")
                continue
            if rr.get("property") == want["property"] and entry.get("secretKey") == want["secretKey"]:
                found = True
    if not found:
        fail.append(f"{rel}: ExternalSecret data for {want['vault_name']} (property {want['property']}, secretKey {want['secretKey']}) not found")

# rh-keycloak: the ESO wiring lives in the external rhbk chart, but the vault
# paths are pinned by OUR overrides/values-keycloak.yaml — drift-check them
# against the seed template prefixes.
kc = yaml.safe_load(open(os.path.join(root, "overrides/values-keycloak.yaml")))
kcv = kc.get("keycloak", {})
kc_prefix = expected_key.get("openshell-keycloak")
kc_path = f"secret/data/{kc_prefix}/openshell-keycloak"
for section in ("adminUser", "postgresqlDb"):
    k = kcv.get(section, {}).get("passwordVaultKey", "")
    if k != kc_path:
        fail.append(f"keycloak.{section}.passwordVaultKey {k!r} != derived path {kc_path!r}")
for es in (kcv.get("extraSecrets") or []):
    for d in es.get("data", []):
        k = d.get("remoteRef", {}).get("key", "")
        gh_path = f"secret/data/{expected_key.get('openshell-github-oauth')}/openshell-github-oauth"
        if k != gh_path:
            fail.append(f"keycloak extraSecrets remoteRef {k!r} != derived path {gh_path!r}")
    secret_names = {d.get("secretKey") for d in es.get("data", [])}
    if "github_client_id" not in secret_names or "github_client_secret" not in secret_names:
        fail.append("keycloak.github oauth ExternalSecret must sync client-id AND client-secret")

# No secret material in Git: block stringData and obvious literals outside the
# seed template (values-secret.yaml.template, which documents vault inputs).
pat = re.compile(r"stringData:|BEGIN [A-Z ]*PRIVATE KEY|api[_-]?token:\s*\S|api[_-]?key:\s*\S|password:\s*\S", re.I)
skip_dirs = {".git", ".specify", "specs", "tests", ".claude", ".opencode"}
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    for fn in filenames:
        if not fn.endswith((".yaml", ".yml", ".tpl")) or fn == "values-secret.yaml.template":
            continue
        p = os.path.join(dirpath, fn)
        try:
            text = open(p, errors="ignore").read()
        except OSError:
            continue
        for m in pat.finditer(text):
            line = text[: m.start()].count("\n") + 1
            # Allow key NAMES in ExternalSecret/charts (e.g. `api-token` as a
            # referenced key) — flag only literal assignments with values.
            snippet = text.splitlines()[line - 1]
            if re.search(r"(stringData:|PRIVATE KEY|:\s*[\"']?[A-Za-z0-9+/=_\-]{16,})", snippet):
                fail.append(f"{os.path.relpath(p, root)}:{line}: possible secret literal: {snippet.strip()[:80]}")

if fail:
    for f in fail:
        print(f, file=sys.stderr)
    sys.exit(1)
print("openshell secrets contract validation passed")
EOF
