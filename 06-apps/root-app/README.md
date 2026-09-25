# Root ApplicationSet (`branch-environments`)

This directory contains the root Argo CD **ApplicationSet** that dynamically generates and manages multi-environment application instances using the GitOps Matrix Generator pattern.

---

## Direct Installation via `kubectl`

You can install or update the ApplicationSet directly using standard `kubectl`:

```bash
# From repository root:
kubectl apply -f 06-apps/root-app/root-applicationset.yaml

# OR from inside this directory:
cd 06-apps/root-app
kubectl apply -f root-applicationset.yaml
```

To check its status:
```bash
kubectl get applicationset branch-environments -n argocd
kubectl describe applicationset branch-environments -n argocd
```

---

## How This ApplicationSet Works

This manifest uses the **Matrix Generator**, which multiplies two generators together:

```text
(Git Generator: environments/*) × (List Generator: app1, app2, app3)
```

1. **Git Directory Generator:**
   * Scans the target Git repository (`repoURL: https://github.com/erchetansoni/gitops-argocd-apps.git`) for directories matching:
     ```text
     environments/*
     ```
   * Example: If the repository contains `environments/main` or `environments/dev`, it creates variables:
     * `{{ .path.path }}` = `environments/main`
     * `{{ .path.basename }}` = `main`

2. **List Generator:**
   * Iterates through the list of applications:
     * `app: app1`
     * `app: app2`
     * `app: app3`

3. **Template Output:**
   * Combines them into an Argo CD Application named `{{ .path.basename }}-{{ .app }}` (e.g., `main-app1`, `main-app2`, `dev-app1`, `dev-app2`).
   * Sets target path to `{{ .path.path }}/{{ .app }}` (e.g., `environments/main/app1`).
   * Deploys into target namespace `{{ .path.basename }}` (e.g., `main` or `dev`).
   * Enables automated sync with `prune: true` and `selfHeal: true`.
   * Sets `ignoreDifferences` for `gateway.networking.k8s.io/HTTPRoute` to avoid false drift.

---

## Directory Matching Contract

The Git generator scans the repository specified in `repoURL`:
```yaml
repoURL: https://github.com/erchetansoni/gitops-argocd-apps.git
directories:
  - path: environments/*
```

> [!IMPORTANT]
> For applications to be generated, the target repository **must contain** folders matching `environments/<environment_name>` (such as `environments/main` or `environments/dev`).
> Each environment folder must contain subdirectories corresponding to the apps (`app1`, `app2`, `app3`).

---

## Useful Inspection Commands

```bash
# List all generated applications
kubectl get applications -n argocd

# Check ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50

# View in Argo CD Web UI
https://argocd.chetan.local
```
