# 01 - Create KinD Cluster

This directory provisions the local single-node Kubernetes cluster using [KinD (Kubernetes in Docker)](https://kind.sigs.k8s.io/) configured for ingress and Gateway API routing.

---

## 🏛️ Overview

The cluster is created with host port mappings on ports `80` and `443` so that the ingress controller / Gateway API proxy ([Traefik](../02-traefik-controller/README.md)) can directly bind and accept HTTP and HTTPS traffic from your host machine (`localhost` or `*.chetan.local` domains).

### Key Features
* **Cluster Name**: `gitops-demo-cluster`
* **Kubernetes Version**: `v1.37.0` (via `kindest/node:v1.37.0`)
* **Host Port Bindings**:
  * `hostPort: 80` -> `containerPort: 80` (HTTP)
  * `hostPort: 443` -> `containerPort: 443` (HTTPS)
* **Pre-flight readiness**: Waits until all `kube-system` control plane pods reach the `Ready` condition before completing.

---

## 📂 File Structure

```
01-create-cluster/
├── create-cluster.sh        # Bash / Git Bash cluster creation script
├── create-cluster.ps1       # PowerShell cluster creation script
├── kind-cluster-config.yaml # KinD cluster configuration with hostPort mappings
├── load-images-to-kind.sh   # Pre-load platform images into KinD (Bash / Git Bash)
├── load-images-to-kind.ps1  # Pre-load platform images into KinD (PowerShell)
└── README.md                # Documentation & multi-shell command reference
```

---

## 📋 Prerequisites

Ensure your system has the required tooling installed and running:

* **Docker**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine running
* **KinD CLI**: `kind` installed (`v0.20+` recommended)
* **kubectl**: `kubectl` installed and configured

```bash
# Verify CLI availability
kind version
kubectl version --client
docker version
```

---

## 📋 Multi-Shell Commands Overview

### 1. Cluster Creation

| Shell / Environment | Command |
| :--- | :--- |
| **Windows PowerShell** | `.\01-create-cluster\create-cluster.ps1` *(or with `-Force`)* |
| **Git Bash (Windows)** | `./01-create-cluster/create-cluster.sh` |
| **Linux / macOS (Bash)** | `chmod +x 01-create-cluster/create-cluster.sh && ./01-create-cluster/create-cluster.sh` |
| **Windows CMD** | `powershell -ExecutionPolicy Bypass -File 01-create-cluster\create-cluster.ps1` |
| **Direct KinD CLI** | `kind create cluster --config 01-create-cluster/kind-cluster-config.yaml` |

### 2. Pre-Loading Platform Images into KinD

| Shell / Action | Command |
| :--- | :--- |
| **PowerShell (Preview)** | `.\01-create-cluster\load-images-to-kind.ps1 -ListOnly` |
| **PowerShell (Load & Auto-Pull)** | `.\01-create-cluster\load-images-to-kind.ps1 -Pull` |
| **PowerShell (From Archive Tarball)** | `.\01-create-cluster\load-images-to-kind.ps1 -Archive airgap\airgap-images.tar` |
| **Git Bash (Preview)** | `./01-create-cluster/load-images-to-kind.sh --list` |
| **Git Bash (Load & Auto-Pull)** | `./01-create-cluster/load-images-to-kind.sh --pull` |
| **Git Bash (From Archive Tarball)** | `./01-create-cluster/load-images-to-kind.sh --archive airgap/airgap-images.tar` |
| **Windows CMD** | `powershell -ExecutionPolicy Bypass -File 01-create-cluster\load-images-to-kind.ps1 -Pull` |

---

## 🚀 Execution Commands by Shell (Detailed)

### Step 1: Create the KinD Cluster

#### 🪟 Windows PowerShell
```powershell
# Option A: Using the automated PowerShell script
.\01-create-cluster\create-cluster.ps1

# Option B: Run without confirmation prompt
.\01-create-cluster\create-cluster.ps1 -Force

# Option C: Direct KinD CLI command
kind create cluster --config 01-create-cluster\kind-cluster-config.yaml
```

#### 🌿 Git Bash (Windows)
```bash
# Option A: Using the automated Bash script
./01-create-cluster/create-cluster.sh

# Option B: Run with explicit bash invocation
bash 01-create-cluster/create-cluster.sh

# Option C: Direct KinD CLI command
kind create cluster --config 01-create-cluster/kind-cluster-config.yaml
```

#### 🐧 Linux / macOS (Bash / Zsh)
```bash
# Option A: Make executable and run
chmod +x 01-create-cluster/create-cluster.sh
./01-create-cluster/create-cluster.sh

# Option B: Direct KinD CLI command
kind create cluster --config 01-create-cluster/kind-cluster-config.yaml
```

#### 💻 Windows Command Prompt (CMD)
```cmd
:: Option A: Run via PowerShell
powershell -ExecutionPolicy Bypass -File 01-create-cluster\create-cluster.ps1

:: Option B: Direct KinD CLI command
kind create cluster --config 01-create-cluster\kind-cluster-config.yaml
```

---

### Step 2: (Recommended) Pre-Load Container Images into KinD

Pre-loading all platform container images (Traefik, cert-manager, Metrics Server, Argo CD, Harbor) directly into the KinD node eliminates initial image download delays, network bandwidth bottlenecks, and pod crash loops during application rollout.

#### 🪟 Windows PowerShell
```powershell
# 1. Preview what images are in inventory and what is present in local Docker cache:
.\01-create-cluster\load-images-to-kind.ps1 -ListOnly

# 2. Pre-load images (auto-pulls any missing images from remote registries):
.\01-create-cluster\load-images-to-kind.ps1 -Pull

# 3. Load from an offline tarball archive (fastest if archive is present):
.\01-create-cluster\load-images-to-kind.ps1 -Archive airgap\airgap-images.tar

# 4. Target a custom cluster name:
.\01-create-cluster\load-images-to-kind.ps1 -ClusterName gitops-demo-cluster -Pull
```

#### 🌿 Git Bash (Windows)
```bash
# 1. Preview inventory:
./01-create-cluster/load-images-to-kind.sh --list

# 2. Pre-load images (auto-pulls any missing images):
./01-create-cluster/load-images-to-kind.sh --pull

# 3. Load from an offline tarball archive:
./01-create-cluster/load-images-to-kind.sh --archive airgap/airgap-images.tar

# 4. Target a custom cluster name:
./01-create-cluster/load-images-to-kind.sh --name gitops-demo-cluster --pull
```

#### 🐧 Linux / macOS (Bash / Zsh)
```bash
# 1. Preview inventory:
chmod +x 01-create-cluster/load-images-to-kind.sh
./01-create-cluster/load-images-to-kind.sh --list

# 2. Pre-load images:
./01-create-cluster/load-images-to-kind.sh --pull

# 3. Load from an offline archive:
./01-create-cluster/load-images-to-kind.sh --archive airgap/airgap-images.tar
```

#### 💻 Windows Command Prompt (CMD)
```cmd
:: Preview inventory:
powershell -ExecutionPolicy Bypass -File 01-create-cluster\load-images-to-kind.ps1 -ListOnly

:: Pre-load images with auto-pull:
powershell -ExecutionPolicy Bypass -File 01-create-cluster\load-images-to-kind.ps1 -Pull

:: Load from offline archive:
powershell -ExecutionPolicy Bypass -File 01-create-cluster\load-images-to-kind.ps1 -Archive airgap\airgap-images.tar
```

---

## 🔍 Verification & Inspection

Once the cluster is created and images are pre-loaded, verify the environment:

### Check Cluster Nodes & System Pods
```bash
# Check node status
kubectl get nodes -o wide

# Check kube-system core services
kubectl get pods -n kube-system

# Check cluster info and current context
kubectl cluster-info --context kind-gitops-demo-cluster
```

### Verify Loaded Images Inside KinD Node
KinD runs a `containerd` runtime inside a Docker container. You can inspect images cached inside the KinD node directly:

```bash
# List images cached inside KinD control-plane node
docker exec -it gitops-demo-cluster-control-plane crictl images
```

---

## 🧹 Teardown & Recreate

If you need to delete and recreate your local cluster from scratch:

#### 🪟 Windows PowerShell
```powershell
kind delete cluster --name gitops-demo-cluster
```

#### 🌿 Git Bash / Linux / macOS
```bash
kind delete cluster --name gitops-demo-cluster
```

#### 💻 Windows Command Prompt (CMD)
```cmd
kind delete cluster --name gitops-demo-cluster
```

---

## ➡️ Next Step

Once the cluster is running and images are pre-loaded:
Proceed to **[`02-traefik-controller`](../02-traefik-controller/README.md)** to install the Gateway API CRDs and Traefik controller.
