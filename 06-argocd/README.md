# 06 - Argo CD (GitOps Control Plane)

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
06-argocd/
├── 01-install-argocd.sh           # Installs Argo CD, applies configs, and prints admin password
├── 02-adopt-infra-apps.sh         # Adopts Traefik, Metrics Server, cert-manager, Harbor, and Forgejo
├── 03-configure-forgejo-repo.sh   # Configures in-cluster Forgejo repo secret in Argo CD
├── argocd-configmaps.yaml         # ConfigMaps: argocd-cm and argocd-cmd-params-cm
├── argocd-httproute.yaml          # Gateway API HTTPRoute for argocd.chetan.local
└── README.md                      # Documentation
```

---

## Key Configurations Explained

In [argocd-configmaps.yaml](argocd-configmaps.yaml):

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
bash 06-argocd/01-install-argocd.sh
```

This will:
* Install Argo CD manifests into the `argocd` namespace.
* Apply [argocd-configmaps.yaml](argocd-configmaps.yaml).
* Apply [argocd-httproute.yaml](argocd-httproute.yaml).
* Print the initial `admin` password.
* Restart the `argocd-server` pod to load new settings.

### Step 2: Adopt Platform Infrastructure Apps
```bash
bash 06-argocd/02-adopt-infra-apps.sh
```
Takes pre-installed infrastructure applications (Traefik, Metrics Server, cert-manager, Harbor, Forgejo, and Forgejo Runner) and brings them under Argo CD GitOps management without terminating running pods.

### Step 3: Configure In-Cluster Forgejo Repository Credentials & Deploy App-of-Apps
```bash
bash 06-argocd/03-configure-forgejo-repo.sh
```
1. Creates `Secret/forgejo-infra-repo-secret` labeled `argocd.argoproj.io/secret-type: repository`. Argo CD can now directly access `http://forgejo-http.forgejo.svc.cluster.local:3000/forgejo_admin/gitops-argocd-infra.git` for ultra-fast, offline, in-cluster GitOps synchronization.
2. Automatically deploys [05-infra-apps/app-of-apps.yaml](../05-infra-apps/app-of-apps.yaml), establishing the top-level GitOps orchestrator watching Forgejo `main`.

---

## 📦 Air-Gap Architecture: Why `airgap-helm-repo` Instead of Harbor or Forgejo?

In [02-adopt-infra-apps.sh](02-adopt-infra-apps.sh#L70-L103), when `INSTALL_MODE=airgap`, the script dynamically launches an in-cluster web server at `http://airgap-helm-repo.argocd.svc:8080` and rewrites the `repoURL` of all platform applications:

```text
[ Online Mode ]   repoURL: https://traefik.github.io/charts (Outbound Internet)
                         │ (Air-gap rewrite)
                         ▼
[ Air-Gap Mode ]  repoURL: http://airgap-helm-repo.argocd.svc:8080 (In-Cluster Internal)
```

### Why is this necessary?
In an air-gapped cluster with no internet route, Argo CD's `repo-server` cannot resolve or download chart tarballs from `github.io` or `goharbor.io`. If left pointing to public URLs, sync fails with `ComparisonError: dial tcp ... i/o timeout`.

### Why use `airgap-helm-repo` instead of in-cluster Harbor or Forgejo?

1. **Avoids the Harbor Circular Dependency ("Chicken-and-Egg")**:
   Harbor is one of the 6 applications being managed by Argo CD! If Harbor's Helm chart is hosted inside Harbor, and Harbor crashes or is restarting during an upgrade, Argo CD **could not even download the Harbor Helm chart to repair it**. `airgap-helm-repo` is completely independent.
2. **Zero Authentication Protocol Matching**:
   Public Helm repositories use unauthenticated HTTP `GET` requests (`index.yaml` + `*.tgz`). `airgap-helm-repo` replicates this exact behavior over internal HTTP port 8080 with **zero tokens, passwords, or certificate verifications**. Harbor requires OCI login credentials, and Forgejo requires Git/Package tokens.
3. **Stateless & Instant Boot**:
   `airgap-helm-repo` is a 5MB static micro-webserver backed directly by a Kubernetes Secret (`airgap-helm-charts`) populated from `airgap/charts/*.tgz`. It has **no database, no persistent volumes**, and boots in under 1 second.

| Feature | `airgap-helm-repo:8080` | In-Cluster Harbor | In-Cluster Forgejo |
| :--- | :--- | :--- | :--- |
| **Survives Harbor Outage** | ✅ **Yes** (Independent) | ❌ **No** (Circular failure) | ✅ **Yes** |
| **Authentication Setup** | ✅ **None** (Anonymous HTTP) | ⚠️ Requires OCI creds secret | ⚠️ Requires Git / Token |
| **Boot Time** | ⚡ **< 1 second** | ⏳ ~45–60 seconds | ⏳ ~15–30 seconds |
| **Database Dependency** | ✅ None (Stateless Secret) | ❌ PostgreSQL + Redis | ❌ SQLite / DB |
| **Primary Purpose** | 🎯 **Day-0 Platform Helm Charts** | 🎯 **Day-1 App Images & CI/CD** | 🎯 **Git Source of Truth** |

---

## 🔍 How to Validate Argo CD is Syncing with Forgejo (Not GitHub)

### 1. Check Registered Repositories in Argo CD UI
1. Open [https://argocd.chetan.local](https://argocd.chetan.local) -> Click **Settings (Gear Icon)** -> **Repositories**.
2. Verify:
   * **URL**: `http://forgejo-http.forgejo.svc.cluster.local:3000/forgejo_admin/gitops-argocd-infra.git`
   * **Connection Status**: 🟢 `Successful`
   * **GitHub presence**: None. GitHub is not registered.

### 2. Verify via CLI / API
```bash
# Verify repository secret in Kubernetes:
kubectl get secret forgejo-infra-repo-secret -n argocd -o jsonpath="{.data.url}" | base64 -d
# Output: http://forgejo-http.forgejo.svc.cluster.local:3000/forgejo_admin/gitops-argocd-infra.git
```

### 3. Understanding What Displays in the UI: Helm Apps vs Git Apps
* **Child Applications** (`traefik`, `harbor`, `metrics-server`, etc.): Display their **Helm Chart Version** (e.g., `41.6.0`, `1.19.2`) because they pull from Helm repositories.
* **Parent Application (`infra-apps`)**: Displays the **Git Branch** (`main`) and the live **Forgejo Commit SHA** (e.g., `53aaab0`) because it pulls manifests directly from Forgejo Git!

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
➡️ [07-apps](../07-apps/README.md) to connect the workload repository (`gitops-argocd-apps`) and deploy applications.

