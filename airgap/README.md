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
| **Container Images** | Docker Hub, Quay, GHCR, k8s.io | `airgap/airgap-images.tar` (imported into K3s containerd) |
| **Gateway API CRDs** | `github.com/.../standard-install.yaml` | `02-traefik-controller/k8s-gateway-api-crd-v1.6.2-install.yaml` |
| **Traefik Helm Chart** | `https://traefik.github.io/charts` | `02-traefik-controller/traefik-41.6.0.tgz` |
| **cert-manager Chart** | `https://charts.jetstack.io` | `03-cert-manager/cert-manager-v1.21.2.tgz` |
| **Metrics Server Chart**| `https://kubernetes-sigs.github.io/...` | `05-infra-apps/02-metrics-server/metrics-server-3.14.0.tgz` |
| **Argo CD Manifest** | `raw.githubusercontent.com/...` | `06-argocd/argocd-install-v3.5.3.yaml` |
| **Argo CD Helm Repo** | Public chart repos (`traefik.github.io`, etc.) | In-cluster service `http://airgap-helm-repo.argocd.svc:8080` |

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
sudo bash airgap/load-offline-assets.sh
```

This places `airgap-images.tar` into `/var/lib/rancher/k3s/agent/images/` and imports all platform images directly into K3s containerd (`k8s.io` namespace).

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

2. **Update [07-apps/.env](file:///c:/Projects/My_Projects/gitops-argocd-infra/07-apps/.env)**:
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
