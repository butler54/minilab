# openshell-policy

Sandbox policy as code (spec FR-008). Git is the source of truth; the ConfigMap
(`openshell-policy` in ns `openshell`) mirrors `policies/*.yaml` and is
reconciled by Argo CD like every other pattern manifest.

## Application mechanism (recorded deviation)

Upstream 0.0.116 exposes policy mutation only via its authenticated API (user
auth = interactive OIDC); there is no declarative, in-cluster policy consumer.
Applying policy content to sandboxes is therefore a **documented imperative
step** (Constitution II — same category as `openshell sandbox create`):

```sh
# edit policies/ -> commit/push -> Argo syncs ConfigMap -> then, from your checkout:
openshell policy update <sandbox> --file policies/<name>.yaml --wait
```

The ConfigMap keeps cluster-side policy inspectable (`oc get cm openshell-policy
-n openshell -o yaml`) and the checksum annotation lets the gateway/app layer
detect drift. If a later OpenShell release supports a declarative policy
source, this chart switches to it and the imperative step is removed.
