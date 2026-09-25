# 05 - Argo CD (GitOps Control Plane)

This directory installs, configures, and exposes **Argo CD** as the central GitOps continuous delivery engine.

---

## Overview

Argo CD automates the deployment of the desired application states declared in Git. In this architecture:
1. **TLS Termination at Gateway**: Traefik terminates HTTPS for `https://argocd.chetan.local` using the wildcard certificate and proxies cleartext HTTP to `argocd-server` on port `80`.
2. **Kustomize + Helm Support**: Configured with `--enable-helm` and `--load-restrictor=LoadRestrictionsNone` so application environment overlays can inflate Helm charts located outside their directory (`../../../apps`).
3. **Gateway API Ignore Differences**: Configured to ignore auto-injected Gateway API schema defaults (`backendRefs[].weight`, `group`, `kind`) so HTTPRoutes remain permanently in `Synced` status.

---

## File Structure

```
05-argocd/
├── 01-install-argocd.sh         # Installs Argo CD, applies configs, and prints admin password
├── 02-adopt-infra-apps.sh       # Adopts Traefik and Metrics Server into Argo CD management
├── argocd-configmaps.yaml       # ConfigMaps: argocd-cm and argocd-cmd-params-cm
├── argocd-httproute.yaml        # Gateway API HTTPRoute for argocd.chetan.local
└── README.md                    # Documentation
```

---

## Key Configurations Explained

In [argocd-configmaps.yaml](file:///c:/Projects/My_Projects/GitOps-demo/05-argocd/argocd-configmaps.yaml):

### 1. Insecure Server Behind Reverse Proxy
```yaml
server.insecure: "true"
```
Disables internal TLS on `argocd-server` so Traefik Gateway can forward HTTP traffic without certificate mismatch loops.

### 2. Kustomize Build Options
```yaml
kustomize.buildOptions: "--enable-helm --load-restrictor=LoadRestrictionsNone"
```
Permits Kustomize overlays in the workload repo (`gitops-argocd-apps/environments/<env>/<app>/kustomization.yaml`) to reference local charts in `../../apps/<app>`.

### 3. Global HTTPRoute Ignore Differences
```yaml
resource.customizations.ignoreDifferences.gateway.networking.k8s.io_HTTPRoute: |
  jqPathExpressions:
    - .spec.parentRefs[].group
    - .spec.parentRefs[].kind
    - .spec.rules[].backendRefs[].group
    - .spec.rules[].backendRefs[].kind
    - .spec.rules[].backendRefs[].weight
```
When Kubernetes processes an `HTTPRoute`, the Gateway controller injects schema defaults. This rule tells Argo CD not to treat these auto-injected fields as configuration drift.

---

## Quickstart

### Step 1: Install Argo CD & Configure UI Access
```bash
bash 05-argocd/01-install-argocd.sh
```

This will:
* Install Argo CD manifests into the `argocd` namespace.
* Apply [argocd-configmaps.yaml](file:///c:/Projects/My_Projects/GitOps-demo/05-argocd/argocd-configmaps.yaml).
* Apply [argocd-httproute.yaml](file:///c:/Projects/My_Projects/GitOps-demo/05-argocd/argocd-httproute.yaml).
* Print the initial `admin` password.
* Restart the `argocd-server` pod to load new settings.

### Step 2: Adopt Platform Infrastructure Apps
```bash
bash 05-argocd/02-adopt-infra-apps.sh
```
Takes the pre-installed Traefik Gateway controller and Metrics Server and brings them under Argo CD GitOps management without terminating running pods.

---

## Accessing Argo CD UI

1. Add domain to your `hosts` file (`C:\Windows\System32\drivers\etc\hosts` or `/etc/hosts`):
   ```text
   127.0.0.1 argocd.chetan.local
   ```
2. Open browser: [https://argocd.chetan.local](https://argocd.chetan.local)
3. **Username**: `admin`
4. **Password**: Retrieve with:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

---

## Next Step

With Argo CD running and managing platform infrastructure, proceed to:
➡️ [06-apps](file:///c:/Projects/My_Projects/GitOps-demo/06-apps/README.md) to connect the workload repository (`gitops-argocd-apps`) and deploy applications.
