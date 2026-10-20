# Air-Gapped 3-Node K3s Cluster Deployment Guide

This guide details how to migrate and deploy this entire GitOps platform from local KinD to a fully **Air-Gapped 3-Node K3s Kubernetes Cluster** with **zero external internet access**.

---

## 🏛️ High-Level Architecture (3-Node K3s Cluster)

```text
       ┌────────────────────────────────────────────────────────┐
       │   External VIP / DNS Round-Robin / LAN Load Balancer   │
       │           (Resolves *.chetan.local to Node IPs)        │
       └────────────────────────┬───────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│  K3s Node 1  │        │  K3s Node 2  │        │  K3s Node 3  │
│(Control-Plane)│       │   (Worker)   │        │   (Worker)   │
│              │        │              │        │              │
│ Traefik DS   │        │ Traefik DS   │        │ Traefik DS   │
│(:80, :443)   │        │(:80, :443)   │        │(:80, :443)   │
│              │        │              │        │              │
│ cert-manager │        │ Argo CD      │        │ Metrics-Svc  │
│ Local CA     │        │ Workloads    │        │ Workloads    │
└──────────────┘        └──────────────┘        └──────────────┘
```

* **Traefik Ingress**: Deployed as a `DaemonSet` on ports `80` and `443` across all nodes. Traffic sent to any of the 3 node IPs reaches the Gateway.
* **Storage**: Uses K3s built-in `local-path` provisioner (standard on all K3s nodes).
* **Network**: Flannel CNI (built into K3s).
* **Runtime**: Embedded `containerd` with offline image tarball pre-loading.

---

## 📋 Summary of Air-Gap Components

| Component | Online Source | Air-Gap Offline Source |
| :--- | :--- | :--- |
| **K3s Binary & Images** | `get.k3s.io` | `k3s` binary + `k3s-airgap-images-amd64.tar.zst` |
| **Container Images** | Docker Hub, Quay, GHCR, k8s.io | `airgap/airgap-images.tar` (imported into containerd) |
| **Gateway API CRDs** | `github.com/.../standard-install.yaml` | `02-traefik-controller/k8s-gateway-api-crd-v1.6.2-install.yaml` |
| **Traefik Helm Chart** | `https://traefik.github.io/charts` | `airgap/charts/traefik-41.6.0.tgz` |
| **cert-manager Chart** | `https://charts.jetstack.io` | `airgap/charts/cert-manager-v1.21.2.tgz` |
| **Metrics Server Chart**| `https://kubernetes-sigs.github.io/...` | `airgap/charts/metrics-server-3.14.0.tgz` |
| **Harbor Registry Chart**| `https://helm.goharbor.io` | `airgap/charts/harbor-1.19.2.tgz` |
| **Forgejo Git Chart** | `oci://code.forgejo.org/...` | `airgap/charts/forgejo-17.2.0.tgz` |
| **Forgejo Runner Chart**| `oci://codeberg.org/...` | `airgap/charts/forgejo-runner-0.7.6.tgz` |
| **Zabbix Helm Chart** | `https://zabbix-community.github.io/helm-zabbix` | `airgap/charts/zabbix-7.1.0.tgz` |
| **Argo CD Manifest** | `raw.githubusercontent.com/...` | `06-argocd/argocd-install-v3.5.3.yaml` |
| **GitOps Git Source** | `github.com/erchetansoni/...` | In-cluster Forgejo `http://forgejo-http.forgejo.svc.cluster.local:3000/...` |
| **Platform Helm Repo** | Public chart repos (`traefik.github.io`, etc.) | In-cluster service `http://airgap-helm-repo.argocd.svc:8080` |

---

### ❓ Why `http://airgap-helm-repo.argocd.svc:8080` Instead of Harbor or Forgejo?

When operating offline, Argo CD cannot resolve public Helm URLs (`traefik.github.io`, `helm.goharbor.io`). A common question is: *Why not serve the offline charts from internal Harbor or Forgejo?*

1. **Avoids the Harbor Circular Dependency ("Chicken-and-Egg")**:
   Harbor is one of the applications being deployed! If Harbor's chart is stored inside Harbor, and Harbor crashes or is restarting during an upgrade, Argo CD **could not even download the Harbor Helm chart to repair it**. `airgap-helm-repo` is completely independent.
2. **Zero Authentication Protocol Matching**:
   Public Helm repositories use unauthenticated HTTP `GET` requests (`index.yaml` + `*.tgz`). `airgap-helm-repo` replicates this exact behavior over internal HTTP port 8080 with **zero tokens, passwords, or certificate verifications**. Harbor requires OCI login credentials, and Forgejo requires Git/Package tokens.
3. **Stateless & Instant Boot**:
   `airgap-helm-repo` is a 5MB static micro-webserver backed directly by a Kubernetes Secret (`airgap-helm-charts`) populated from `airgap/charts/*.tgz`. It has **no database, no persistent volumes**, and boots in under 1 second.


---

## 💡 How Offline Detection & Image Loading Work

Understanding how the platform behaves when there is no internet connection:

### 1. Does it try internet first, or offline first?

**It uses Offline Mode FIRST (instant execution, zero timeout delay).**

The install scripts do **not** attempt an internet connection and wait for network timeouts. Instead, they check whether the offline files exist on disk:

```text
[ Script Starts ]
        │
        ▼
Is local .tgz chart or manifest on disk?
       ├── YES ──► Installs from local file immediately (100% offline, 0s delay)
       └── NO  ──► Falls back to online repository (helm repo add / curl)
```

Because the `.tgz` charts and `argocd-install-v3.5.3.yaml` are pre-bundled in the repo, the scripts **instantly detect the local files and run offline without ever contacting the internet**.

---

### 2. How Container Images Work in Air-Gap (KinD vs. K3s)

Applying Helm charts and manifests only creates Kubernetes *specifications* (`Deployments`, `Pods`). When Kubernetes starts a pod, the node's container runtime (`containerd`) must have the actual container image.

All manifests declare **explicit version tags** (e.g., `:v3.7.13`, `:v1.21.2`, `:v0.9.0`), meaning Kubernetes uses `imagePullPolicy: IfNotPresent`. Once an image exists in the local node cache, Kubernetes **never reaches out to the network**.

```text
KinD (Docker Container on Laptop)          K3s (Bare-Metal / VMs in Air-Gap)
┌────────────────────────────────┐        ┌────────────────────────────────┐
│ Laptop Host                    │        │ K3s Node Host                  │
│                                │        │                                │
│ ┌────────────────────────────┐ │        │ ┌────────────────────────────┐ │
│ │ KinD Container             │ │        │ │ K3s containerd runtime     │ │
│ │ (Internal containerd cache)│ │        │ │ (/var/lib/rancher/k3s/     │ │
│ └────────────────────────────┘ │        │ │  agent/images/)            │ │
│                                │        │ └────────────────────────────┘ │
└────────────────────────────────┘        └────────────────────────────────┘
Load via:                                 Load via:
kind load image-archive                   sudo bash airgap/load-offline-assets.sh
airgap/airgap-images.tar                  (copies tarball to K3s images directory)
```

#### Comparison: KinD vs. K3s Offline Behavior

| Action | KinD (Local Laptop with No Internet) | 3-Node K3s (Air-Gapped Cluster) |
| :--- | :--- | :--- |
| **How to load images** | `kind load image-archive airgap/airgap-images.tar --name gitops-demo-cluster` | `sudo bash airgap/load-offline-assets.sh` (run on all 3 nodes) |
| **Where images go** | Inside the KinD Docker container's internal `containerd` | Inside `/var/lib/rancher/k3s/agent/images/` on each node |
| **If images are NOT loaded** | Pods get stuck in `ImagePullBackOff` | Pods get stuck in `ImagePullBackOff` |
| **Once images are loaded** | Pods start immediately with `Running` status 🟢 | Pods start immediately with `Running` status 🟢 |
| **Helm charts & manifests** | Uses local `.tgz` and offline `.yaml` 🟢 | Uses local `.tgz` and offline `.yaml` 🟢 |

---

## 🚀 Step-by-Step Migration & Deployment

### Phase 1: Bundle Assets (On Connected Workstation)

Run the bundler script on your internet-connected machine:

```bash
bash airgap/bundle-offline-assets.sh
```

This automates:
1. Pulling all 9 required platform container images (`images.yaml`).
2. Exporting them to `airgap/airgap-images.tar`.
3. Packaging Helm charts (`.tgz`) for Traefik, cert-manager, and Metrics Server.
4. Downloading the complete Argo CD `v3.5.3` install manifest.

Copy the entire `gitops-argocd-infra` directory (including `airgap/airgap-images.tar`) onto a USB drive or secure jump host.

---

### Phase 2: Install 3-Node K3s Cluster (Air-Gapped)

On each node, download the official K3s air-gap release assets beforehand:
* `k3s` binary
* `k3s-airgap-images-amd64.tar.zst`
* `install.sh`

#### 1. Setup Node 1 (Server / Control-Plane):
```bash
# Place K3s airgap images
sudo mkdir -p /var/lib/rancher/k3s/agent/images/
sudo cp k3s-airgap-images-amd64.tar.zst /var/lib/rancher/k3s/agent/images/

# Install K3s server with Traefik disabled (CRITICAL!)
sudo cp k3s /usr/local/bin/chmod +x /usr/local/bin/k3s
INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_EXEC="server --disable=traefik" ./install.sh

# Capture join token and Node 1 IP:
K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
NODE1_IP="192.168.1.10" # Replace with your Node 1 IP
```

> [!IMPORTANT]
> The `--disable=traefik` flag is **mandatory**. K3s bundles legacy Traefik by default; disabling it prevents port `80`/`443` collisions with our Gateway API Traefik v3.

#### 2. Join Node 2 & Node 3 (Agents / Workers):
On each worker node:
```bash
sudo mkdir -p /var/lib/rancher/k3s/agent/images/
sudo cp k3s-airgap-images-amd64.tar.zst /var/lib/rancher/k3s/agent/images/
sudo cp k3s /usr/local/bin/ && sudo chmod +x /usr/local/bin/k3s

INSTALL_K3S_SKIP_DOWNLOAD=true \
K3S_URL="https://${NODE1_IP}:6443" \
K3S_TOKEN="${K3S_TOKEN}" \
./install.sh
```

#### 3. Verify the 3-Node Cluster:
On Node 1:
```bash
sudo kubectl get nodes
# Expected output: 3 nodes in 'Ready' status
```

---

### Phase 3: Load Platform Container Images on All 3 Nodes

Run this command **on Node 1, Node 2, and Node 3**:

```bash
# Standard run (Cleans stale images/tarballs on node, then loads fresh images):
sudo bash airgap/load-offline-assets.sh

# Clean, load images, and delete source tarball afterwards to reclaim disk:
sudo bash airgap/load-offline-assets.sh --clean-source

# Skip the cleanup phase if you only want to load:
sudo bash airgap/load-offline-assets.sh --skip-clean
```

#### What this script does:
1. **Pre-Load Cleanup**: Cleans any existing or stale image archives (`*.tar`, `*.tgz`, `*.tar.gz`, `*.tar.zst`) in `/var/lib/rancher/k3s/agent/images/` and prunes dangling container images (`k3s crictl rmi --prune` / `docker image prune`) to prevent disk bloat.
2. **Image Loading**: Copies the fresh image archive into `/var/lib/rancher/k3s/agent/images/` and imports all platform images directly into K3s containerd (`k8s.io` namespace).
3. **Verification**: Verifies that required platform images (Traefik, cert-manager, Metrics Server, Argo CD, Dex, Redis) are present in containerd.
4. **Post-Load Cleanup (Optional)**: If `--clean-source` is passed, deletes the source `airgap-images.tar` after import to free up space on smaller nodes.

---

### Phase 4: Configure Kubeconfig & Deploy Platform

On Node 1 (or workstation with admin kubeconfig):

```bash
# 1. Point to K3s cluster context:
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 2. Run the platform deployment sequence:
./02-traefik-controller/install-traefik-gateway-controller.sh
./03-cert-manager/install-cert-manager.sh
./04-traefik-gateway/install-traefik-gatewayclass.sh
./05-infra-apps/02-metrics-server/install-metrics-server.sh
./06-argocd/01-install-argocd.sh
./06-argocd/02-adopt-infra-apps.sh
```

Each script automatically detects the local `.tgz` Helm charts and local manifests, installing completely offline!

---

### Phase 5: Workload Repository Setup (Internal Git Server)

In an air-gapped environment, Argo CD cannot clone from `github.com`.

1. **Host Workload Git Repository**:
   Mirror `gitops-argocd-apps` to your internal Git server (e.g. self-hosted GitLab, Gitea, or Bitbucket Server on your LAN):
   ```text
   http://gitea.local:3000/devops/gitops-argocd-apps.git
   ```

2. **Update [.env](file:///c:/Projects/My_Projects/gitops-argocd-infra/.env)** at repository root:
   ```env
   REPO_URL="http://gitea.local:3000/devops/gitops-argocd-apps.git"
   GITHUB_USERNAME="your-git-user"
   GITHUB_TOKEN="your-git-token-or-password"
   REPO_SECRET_NAME="repo-creds-secret"
   ARGOCD_NAMESPACE="argocd"
   ARGOCD_HOST="argocd.chetan.local"
   ```

3. **Deploy Workload Apps**:
   ```bash
   bash 07-apps/01-install-repo-creds-secret.sh
   bash 07-apps/02-install-root-app.sh
   ```

---

## 🌐 LAN Ingress & DNS for 3 Nodes

Because Traefik is deployed as a `DaemonSet`, every node listens on port `80` and `443`.

To access the cluster from client machines on your LAN:

1. **Option A: Internal DNS / Router (Recommended)**
   Add DNS records in your local router/DNS server (pfSense, Pi-hole, AdGuard):
   ```text
   argocd.chetan.local   -> 192.168.1.10 (Node 1)
   app1.chetan.local     -> 192.168.1.11 (Node 2)
   app1.dev.chetan.local -> 192.168.1.12 (Node 3)
   ```
   *(Or round-robin across all 3 IPs).*

2. **Option B: Workstation `/etc/hosts` or `C:\Windows\System32\drivers\etc\hosts`**
   ```text
   192.168.1.10 argocd.chetan.local app1.chetan.local app1.dev.chetan.local
   ```

3. **Option C: High Availability with kube-vip**
   Deploy `kube-vip` to provide a single virtual IP (VIP, e.g. `192.168.1.200`) shared across all 3 nodes with automated failover.

---

## 🔍 Air-Gap Verification

```bash
# 1. Verify Traefik DaemonSet is running on all 3 nodes:
kubectl get daemonset -n traefik -o wide

# 2. Verify cert-manager and ClusterIssuer:
kubectl get pods -n cert-manager
kubectl get clusterissuer local-ca-issuer

# 3. Verify Gateway and Certificate:
kubectl get gateway -n default
kubectl get certificate -n default

# 4. Verify Metrics Server across 3 nodes:
kubectl top nodes
kubectl top pods -A

# 5. Access Argo CD:
curl -k https://argocd.chetan.local/
```

---

## 🧹 Cleaning Offline Assets & Large Image Archives

When you need to reclaim disk space by deleting local container image tarballs (`*.tar`, `*.tgz`, `*.tar.gz`, `*.tar.zst`):

```bash
# 1. Preview matching files and space to reclaim without deleting anything:
./clean-images.sh --dry-run
# Or in PowerShell:
.\clean-images.ps1 -DryRun

# 2. Interactively delete archives across the repository:
./clean-images.sh

# 3. Clean only the airgap directory:
./clean-images.sh ./airgap
# Or use the shortcut:
./airgap/clean-offline-assets.sh
```

---

## 🔄 Day-2 Lifecycle Operations: Adding Apps & Disconnecting Internet

### 1. Adding a New Platform/Infra App in Online Mode

Adding a new platform app (e.g. Prometheus, Vault, Loki) when connected to the internet is straightforward:

1. **Add to [05-infra-apps/platform-apps.yaml](../05-infra-apps/platform-apps.yaml)**:
   Append a new `Application` block under `items:`:
   ```yaml
   - apiVersion: argoproj.io/v1alpha1
     kind: Application
     metadata:
       name: prometheus
       namespace: argocd
       annotations:
         argocd.argoproj.io/sync-wave: "2"
     spec:
       project: default
       source:
         repoURL: https://prometheus-community.github.io/helm-charts
         chart: kube-prometheus-stack
         targetRevision: 69.3.0
         helm:
           valuesObject:
             # Custom Helm values
       destination:
         server: https://kubernetes.default.svc
         namespace: monitoring
       syncPolicy:
         automated:
           prune: false
           selfHeal: true
         syncOptions:
           - CreateNamespace=true
           - ServerSideApply=true
   ```
2. **Commit and Push**:
   ```bash
   git add 05-infra-apps/platform-apps.yaml
   git commit -m "feat(infra): add prometheus monitoring stack"
   git push forgejo main
   ```
3. **Argo CD reconciles automatically**: The root `infra-apps` Application detects the new child application in Forgejo Git and deploys Prometheus into Kubernetes.

---

### 2. Adding a New Platform/Infra App in Air-Gap Mode

In a disconnected environment, Argo CD cannot download charts from the internet, and Kubernetes cannot pull images from Docker Hub. You must package the assets on an internet-connected workstation first:

#### Step A: On the Connected Machine (Asset Preparation)
1. **Download the Helm Chart package**:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm pull prometheus-community/kube-prometheus-stack --version 69.3.0 -d airgap/charts/
   ```
2. **Re-generate the local chart repository index**:
   ```bash
   helm repo index airgap/charts/
   ```
3. **Identify & Export Container Images**:
   Render the chart templates to discover all required images:
   ```bash
   helm template airgap/charts/kube-prometheus-stack-69.3.0.tgz | grep -E 'image:\s*"?([^"[:space:]]+)'
   ```
   Add these image strings to `airgap/images.yaml`, pull them, and export to tarball:
   ```bash
   docker pull prom/prometheus:v3.2.0
   docker save prom/prometheus:v3.2.0 -o new-app-images.tar
   ```

#### Step B: In the Air-Gap Environment (Import & Deploy)
1. **Load Images into Kubernetes Node containerd** (or push to in-cluster Harbor `cr.chetan.local`):
   ```bash
   # KinD:
   kind load image-archive new-app-images.tar --name gitops-demo-cluster
   # Or K3s:
   sudo k3s ctr images import new-app-images.tar
   ```
2. **Update the in-cluster Chart Secret**:
   Re-apply the `airgap-helm-charts` Secret with the newly added `.tgz` file:
   ```bash
   kubectl create secret generic airgap-helm-charts \
     --from-file=airgap/charts/ \
     -n argocd --dry-run=client -o yaml | kubectl apply -f -
   ```
3. **Declare the Application with Internal `repoURL`**:
   In [05-infra-apps/platform-apps.yaml](../05-infra-apps/platform-apps.yaml), specify the internal chart repo:
   ```yaml
   source:
     repoURL: http://airgap-helm-repo.argocd.svc:8080   # <-- Internal offline server
     chart: kube-prometheus-stack
     targetRevision: 69.3.0
   ```
4. **Push to Forgejo**:
   ```bash
   git add 05-infra-apps/platform-apps.yaml
   git commit -m "feat(infra): add prometheus in airgap mode"
   git push forgejo main
   ```

---

### 3. What if You Bootstrap with Internet Mode, but LATER Disconnect Internet?

This is a common enterprise pattern: **provisioning a cluster in a staging lab with internet access, then shipping it to a disconnected customer site or air-gapped production**.

#### What keeps working automatically with ZERO changes:
1. **All Active Pods**: Running containers keep running without interruption.
2. **Pod Restarts / Node Reboots**: Because all manifests declare explicit version tags (e.g. `:v3.7.13`), containerd caches them locally with `imagePullPolicy: IfNotPresent`. Node reboots will restart pods cleanly without network access.
3. **In-Cluster GitOps**: Developers push to Forgejo (`git push forgejo main`), and Argo CD polls `http://forgejo-http.forgejo.svc.cluster.local:3000` 100% internally.

#### The ONE component that needs transition:
* In online mode, [platform-apps.yaml](../05-infra-apps/platform-apps.yaml) was committed with **public internet URLs** (`https://traefik.github.io/charts`, `https://helm.goharbor.io`).
* When the internet is disconnected, Argo CD's periodic 3-minute poll will attempt to check those public URLs for chart updates.
* It will fail with `ComparisonError: dial tcp ... i/o timeout` (though existing running pods remain untouched).

#### How to "Cut the Cord" (Seamless Transition to Air-Gap):
To decouple Argo CD from the internet cleanly:

1. **Deploy the in-cluster chart server**:
   ```bash
   # Create the chart secret from local airgap/charts/
   kubectl create secret generic airgap-helm-charts \
     --from-file=airgap/charts/ \
     -n argocd --dry-run=client -o yaml | kubectl apply -f -

   # Start the chart web server
   kubectl apply -f 06-argocd/airgap-helm-repo.yaml -n argocd
   ```
2. **Redirect `platform-apps.yaml` to the internal chart server**:
   In `05-infra-apps/platform-apps.yaml`, change all public `repoURL:` fields to:
   ```yaml
   repoURL: http://airgap-helm-repo.argocd.svc:8080
   ```
3. **Commit and push to Forgejo**:
   ```bash
   git add 05-infra-apps/platform-apps.yaml
   git commit -m "chore(airgap): switch helm repoURL to in-cluster airgap chart server"
   git push forgejo main
   ```
4. **Trigger Argo CD hard refresh**:
   ```bash
   kubectl annotate application infra-apps -n argocd argocd.argoproj.io/refresh=hard --overwrite
   ```
Argo CD immediately stops contacting the internet and fetches all charts from `http://airgap-helm-repo.argocd.svc:8080`. The cluster is now permanently 100% autonomous.


