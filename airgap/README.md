# Air-Gapped 3-Node K3s Cluster Deployment Guide

This guide details how to install and operate the entire GitOps platform in a fully **Air-Gapped 3-Node K3s Kubernetes Cluster** with **zero external internet access**.

---

## 🏛️ Architecture Overview

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
│ Local CA     │        │ Harbor       │        │ Forgejo Git  │
│ Zabbix       │        │ Workloads    │        │ Workloads    │
└──────────────┘        └──────────────┘        └──────────────┘
```

* **Traefik Ingress**: Deployed as a `DaemonSet` on ports `80` and `443` across all nodes via Kubernetes Gateway API. Traffic sent to any node IP reaches the Gateway.
* **Storage**: Uses K3s built-in `local-path` provisioner (standard on all K3s nodes).
* **Network & Runtime**: Flannel CNI + embedded `containerd` with offline image tarball import.

---

## 📋 Platform Components & Offline Inventory

All charts and images are pre-bundled in the repository:

| Component | Port / Hostname | Chart Source | Container Image(s) |
| :--- | :--- | :--- | :--- |
| **Traefik Gateway Controller** | `:80`, `:443` | `airgap/charts/traefik-41.6.0.tgz` | `docker.io/traefik:v3.7.13` |
| **Gateway API CRDs** | — | `02-traefik-controller/k8s-gateway-api-crd-v1.6.2-install.yaml` | — |
| **cert-manager** | `local-ca-issuer` | `airgap/charts/cert-manager-v1.21.2.tgz` | `jetstack/cert-manager-controller:v1.21.2` + webhook/cainjector |
| **Metrics Server** | In-Cluster API | `airgap/charts/metrics-server-3.14.0.tgz` | `registry.k8s.io/metrics-server/metrics-server:v0.9.0` |
| **Harbor Registry** | `https://cr.chetan.local` | `airgap/charts/harbor-1.19.2.tgz` | `goharbor/harbor-*`, `registry-photon`, `valkey-photon`, `trivy` |
| **Forgejo Git Service** | `https://git.chetan.local` | `airgap/charts/forgejo-17.2.0.tgz` | `code.forgejo.org/forgejo/forgejo:15.0.10-rootless` |
| **Forgejo Actions Runner**| In-Cluster daemon | `airgap/charts/forgejo-runner-0.7.6.tgz` | `code.forgejo.org/forgejo/runner:12.7.3`, `docker:dind`, `kubectl` |
| **Zabbix Monitoring** | `https://zabbix.chetan.local` | `airgap/charts/zabbix-7.1.0.tgz` | `zabbix/zabbix-*-pgsql:alpine-7.4.15`, `timescaledb:2.17.2-pg16` |
| **Argo CD** | `https://argocd.chetan.local` | `06-argocd/argocd-install-v3.5.3.yaml` | `quay.io/argoproj/argocd:v3.5.3`, `dex:v2.45.1`, `redis:8.2.3` |
| **In-Cluster Helm Repo**| `http://airgap-helm-repo.argocd.svc:8080` | `06-argocd/airgap-helm-repo.yaml` | Backed by `airgap-helm-charts` Secret (zero-latency, no network) |

---

## 🚀 Step-by-Step Installation via SSH

### Step 1: Transfer Assets to Node 1

From your machine with the repository, copy the files to **Node 1** using SCP or SFTP:

```bash
# Tar and transfer to Node 1:
tar -czf gitops-argocd-infra.tar.gz gitops-argocd-infra/
scp gitops-argocd-infra.tar.gz user@<NODE1_IP>:~/

# SSH into Node 1:
ssh user@<NODE1_IP>
tar -xzf gitops-argocd-infra.tar.gz
cd gitops-argocd-infra
```

---

### Step 2: Ensure K3s is Running with Traefik Disabled (CRITICAL)

K3s comes with a built-in legacy Traefik ingress by default. You **must** disable it so our Traefik v3 Gateway Controller can bind to host ports `80` and `443`.

* **If installing K3s fresh**:
  ```bash
  # Node 1 (Server / Control-Plane):
  INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_EXEC="server --disable=traefik" ./install.sh

  # Nodes 2 & 3 (Agents / Workers):
  INSTALL_K3S_SKIP_DOWNLOAD=true K3S_URL="https://<NODE1_IP>:6443" K3S_TOKEN="<TOKEN>" ./install.sh
  ```

* **If K3s is already installed**:
  Check if Traefik is running:
  ```bash
  kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
  ```
  If found, remove the packaged manifest and restart K3s:
  ```bash
  sudo rm -f /var/lib/rancher/k3s/server/manifests/traefik.yaml
  # Add '--disable=traefik' to /etc/systemd/system/k3s.service ExecStart if needed, then:
  sudo systemctl daemon-reload && sudo systemctl restart k3s
  ```

---

### Step 3: Load Container Images on ALL 3 Nodes

Because Kubernetes schedules pods across all 3 nodes, every node needs the container images in its local containerd storage.

1. **On Node 1**:
   ```bash
   sudo bash airgap/load-offline-assets.sh
   ```

2. **On Node 2 & Node 3**:
   Copy the tarball from Node 1 to Node 2 and Node 3:
   ```bash
   # From Node 1:
   scp airgap/airgap-images.tar user@<NODE2_IP>:/tmp/
   scp airgap/airgap-images.tar user@<NODE3_IP>:/tmp/

   # SSH to Node 2 & Node 3 and import into K3s containerd:
   ssh user@<NODE2_IP> "sudo k3s ctr images import /tmp/airgap-images.tar && rm -f /tmp/airgap-images.tar"
   ssh user@<NODE3_IP> "sudo k3s ctr images import /tmp/airgap-images.tar && rm -f /tmp/airgap-images.tar"
   ```

---

### Step 4: Configure Local DNS Resolution on Node 1

During setup, helper scripts (`sync-repo-to-forgejo.sh`, validation checks) call internal domain endpoints like `https://git.chetan.local`. Add them to `/etc/hosts` on **Node 1**:

```bash
sudo bash -c 'cat <<EOF >> /etc/hosts
127.0.0.1 argocd.chetan.local git.chetan.local cr.chetan.local zabbix.chetan.local
EOF'
```

---

### Step 5: Run Platform Orchestrator on Node 1

Run the dedicated K3s platform installation script:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
chmod +x install-k3s-platform.sh
./install-k3s-platform.sh
```

#### What `install-k3s-platform.sh` executes automatically:
1. Verifies K3s cluster nodes and Kubeconfig.
2. Applies Gateway API CRDs (`v1.6.2`) and deploys Traefik v3 Gateway Controller (`DaemonSet` on ports 80/443).
3. Installs `cert-manager` and issues the self-signed local Root CA & Gateway certificate (`*.chetan.local`).
4. Deploys Traefik Gateway & HTTPS Listener.
5. Deploys Kubernetes Metrics Server (CPU/Memory metrics for `kubectl top`).
6. Deploys Harbor Private OCI Registry (`cr.chetan.local`).
7. Deploys Forgejo Git Service (`git.chetan.local`) and initializes Git repository.
8. Deploys Forgejo Actions Runner (CI/CD daemon).
9. Deploys Zabbix Monitoring Stack (`zabbix.chetan.local`).
10. Installs Argo CD (`argocd.chetan.local`).
11. Starts the in-cluster `airgap-helm-repo` static chart service (`http://airgap-helm-repo.argocd.svc:8080`) and adopts all infra apps into Argo CD.
12. Registers Forgejo internal Git repository in Argo CD.
13. Displays complete access URLs and default credentials.

---

## 🌐 External Access from LAN Clients

To access the platform web consoles from your laptop/workstation on the same LAN:

Add the following to your workstation's hosts file (`/etc/hosts` or `C:\Windows\System32\drivers\etc\hosts`), pointing to **any** of the 3 K3s node IPs (or a VIP / DNS server):

```text
192.168.1.10 argocd.chetan.local git.chetan.local cr.chetan.local zabbix.chetan.local
```

### Access URLs:
* **Argo CD**: `https://argocd.chetan.local` (Username: `admin`)
* **Forgejo Git**: `https://git.chetan.local` (Username: `forgejo_admin`)
* **Harbor Registry**: `https://cr.chetan.local` (Username: `admin`)
* **Zabbix**: `https://zabbix.chetan.local` (Username: `Admin`)

---

## 🔍 Verification Commands

```bash
# 1. Verify all 3 nodes are Ready:
kubectl get nodes -o wide

# 2. Verify Traefik DaemonSet is running on all 3 nodes:
kubectl get daemonset -n traefik

# 3. Verify all pods across all namespaces are Running:
kubectl get pods -A

# 4. Check Argo CD applications sync status:
kubectl get applications -n argocd
```
