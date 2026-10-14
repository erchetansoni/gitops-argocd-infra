# ☸️ GitOps Kubernetes Infrastructure & Platform Control Plane

[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.37.0-blue?logo=kubernetes)](https://kubernetes.io/)
[![Kind](https://img.shields.io/badge/Kind-v0.29.0-blue?logo=docker)](https://kind.sigs.k8s.io/)
[![Traefik](https://img.shields.io/badge/Traefik-v3.7.13-24A1C1?logo=traefik)](https://traefik.io/)
[![Gateway API](https://img.shields.io/badge/Gateway_API-v1.2.1-326CE5?logo=kubernetes)](https://gateway-api.sigs.k8s.io/)
[![Argo CD](https://img.shields.io/badge/Argo_CD-v3.0.0-orange?logo=argo)](https://argo-cd.readthedocs.io/)

This repository (**`erchetansoni/gitops-argocd-infra`**) is the declarative infrastructure and platform control plane for the GitOps Kubernetes environment. It provisions the cluster foundation, ingress/gateway controller, internal PKI/TLS certificates, platform services, and Argo CD.

Workload microservices and per-environment manifests live in the companion repository:  
👉 **[`erchetansoni/gitops-argocd-apps`](https://github.com/erchetansoni/gitops-argocd-apps)**

---

## 🏛️ High-Level GitOps Architecture

```mermaid
flowchart TB
    subgraph Host["🖥️ Host Machine (Browser & Workstation)"]
        Browser["🌐 Web Browser & Docker CLI\n(app1.chetan.local, app1.dev.chetan.local,\nargocd.chetan.local, cr.chetan.local, git.chetan.local)"]
        HostsFile["📄 /etc/hosts or Windows hosts\n(127.0.0.1 *.chetan.local)"]
        RootCATrust["🔒 Trusted Root CA Store\n(Avgol Internal Root CA)"]
    end

    subgraph GitRepos["🐙 GitHub Repositories"]
        InfraRepo["📦 erchetansoni/gitops-argocd-infra\n(This Repository - Cluster & Platform)"]
        AppsRepo["📦 erchetansoni/gitops-argocd-apps\n(Apps, Helm Charts & Environments)"]
    end

    subgraph Cluster["☸️ Kind Kubernetes Cluster (gitops-demo-cluster)"]
        subgraph Ports["HostPort Bindings"]
            P80["Port 80 (HTTP)"]
            P443["Port 443 (HTTPS)"]
        end

        subgraph IngressLayer["🌐 Gateway API & Ingress (traefik namespace)"]
            Traefik["Traefik v3.7 Controller (DaemonSet)\n• Auto HTTP-to-HTTPS 301 Redirect\n• Gateway API Provider"]
            GatewayClass["GatewayClass: traefik"]
            MainGateway["Gateway: main-gateway (default namespace)\n• Listener :80 (HTTP)\n• Listener :443 https-chetan (*.chetan.local)\n• Listener :443 https-dev (*.dev.chetan.local)"]
            TLSSecret["Secret: domain-certificate-tls-secret\n(Wildcard SANs: *.chetan.local, *.dev.chetan.local)"]
        end

        subgraph PlatformLayer["🛠️ Platform & Infrastructure Apps"]
            MetricsServer["Metrics Server (kube-system namespace)\n(CPU & Memory Metrics)"]
            HarborRegistry["Harbor Registry (harbor namespace)\n(cr.chetan.local OCI Registry)"]
            ForgejoService["Forgejo Git Service (forgejo namespace)\n(git.chetan.local Git & Actions)"]
            ForgejoRunner["Forgejo Actions Runner (forgejo-runner)\n(DinD CI/CD Runner)"]
            ArgoCD["Argo CD Control Plane (argocd namespace)\n(App-of-Apps & ApplicationSets)"]
        end

        subgraph WorkloadNamespaces["🚀 Deployed Applications"]
            subgraph MainEnv["Namespace: main"]
                MainApp1["app1 (blue/green)\napp1.chetan.local"]
                MainApp2["app2 (httpbin)\napp2.chetan.local"]
                MainApp3["app3 (kuar)\napp3.chetan.local"]
            end
            subgraph DevEnv["Namespace: dev"]
                DevApp1["app1\napp1.dev.chetan.local"]
                DevApp2["app2\napp2.dev.chetan.local"]
                DevApp3["app3\napp3.dev.chetan.local"]
            end
        end
    end

    Browser -->|HTTP :80| P80
    Browser -->|HTTPS :443| P443
    P80 -->|301 Redirect to HTTPS| Traefik
    P443 --> Traefik
    Traefik --> MainGateway
    MainGateway --> TLSSecret
    MainGateway -->|HTTPRoute: argocd.chetan.local| ArgoCD
    MainGateway -->|HTTPRoute: cr.chetan.local| HarborRegistry
    MainGateway -->|HTTPRoute: git.chetan.local| ForgejoService
    ForgejoRunner -.->|Polls & Executes| ForgejoService

    ArgoCD -->|Adopts & Manages| Traefik
    ArgoCD -->|Adopts & Manages| MetricsServer
    ArgoCD -->|Adopts & Manages| HarborRegistry
    ArgoCD -->|Adopts & Manages| ForgejoService
    ArgoCD -->|Adopts & Manages| ForgejoRunner
    ArgoCD -->|Watches & Syncs| AppsRepo

    AppsRepo -.->|ApplicationSet Matrix| MainEnv
    AppsRepo -.->|ApplicationSet Matrix| DevEnv
```

---

## 📂 Repository Directory Layout

Each numbered directory encapsulates a specific stage of the platform bootstrap lifecycle:

| Directory | Purpose | Key Manifests & Scripts |
| :--- | :--- | :--- |
| **[`01-create-cluster`](file:///c:/Projects/My_Projects/gitops-argocd-infra/01-create-cluster/README.md)** | Local Kind Kubernetes cluster | `kind-cluster-config.yaml`, `create-cluster.sh`, `load-images-to-kind.sh/.ps1` |
| **[`02-traefik-controller`](file:///c:/Projects/My_Projects/gitops-argocd-infra/02-traefik-controller/README.md)** | Gateway API CRDs & Traefik v3 DaemonSet | `install-traefik-gateway-controller.sh`, `traefik-values.yaml` |
| **[`03-cert-manager`](file:///c:/Projects/My_Projects/gitops-argocd-infra/03-cert-manager/README.md)** | cert-manager v1.21.2 & ClusterIssuer | `install-cert-manager.sh`, `cluster-issuer.yaml` |
| **[`04-traefik-gateway`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/README.md)** | GatewayClass, Gateway listeners & TLS Certificate | `install-gatewayclass_and_gateway.yaml`, `cert/tls-generator/` |
| **[`05-infra-apps`](file:///c:/Projects/My_Projects/gitops-argocd-infra/05-infra-apps/README.md)** | Platform infra apps (App-of-Apps parent and platform applications) | `app-of-apps.yaml`, `platform-apps.yaml`, `02-metrics-server/`, `03-harbor/`, `04-forgejo/`, `05-forgejo-runner/` |
| **[`06-argocd`](file:///c:/Projects/My_Projects/gitops-argocd-infra/06-argocd/README.md)** | Argo CD install, ConfigMaps, HTTPRoute, adoption & Forgejo repo secret | `01-install-argocd.sh`, `02-adopt-infra-apps.sh`, `03-configure-forgejo-repo.sh`, `argocd-httproute.yaml` |
| **[`07-apps`](file:///c:/Projects/My_Projects/gitops-argocd-infra/07-apps/README.md)** | Workload Git repo credentials & Root ApplicationSet | `01-install-repo-creds-secret.sh`, `02-install-root-app.sh`, `root-app/` |

---

## 📋 Prerequisites

Before running the bootstrap scripts, ensure your workstation has:

1. **Docker Desktop** (or Docker Engine) running.
2. **[Kind CLI](https://kind.sigs.k8s.io/)** (`kind version >= 0.20`).
3. **[kubectl](https://kubernetes.io/docs/tasks/tools/)** (`>= v1.28`).
4. **[Helm 3](https://helm.sh/)** (`>= v3.12`).
5. **OpenSSL** (available via Git Bash or Linux).
6. **Bash shell** (Git Bash on Windows or native bash on Linux/macOS).

---

## 🚀 End-to-End Setup Guide

You can run the entire platform bring-up automatically with a single command via [main.sh](file:///c:/Projects/My_Projects/gitops-argocd-infra/main.sh):

```bash
bash main.sh
```

Or execute the numbered stages sequentially:

### Step 1: Create the Kind Cluster
```bash
bash 01-create-cluster/create-cluster.sh
```
* Provisions `gitops-demo-cluster` with ports `80` and `443` bound to your localhost.

### Step 2: Pre-load Day-0 Platform Container Images
```bash
bash 01-create-cluster/load-images-to-kind.sh --pull
```
* Pre-loads all platform container images (Traefik, cert-manager, Metrics Server, Harbor, Forgejo, Forgejo Runner, and Argo CD) directly into the KinD node's containerd cache.
* **Why this matters**: Eliminates image pull timeouts, allows 100% offline startup, and avoids the circular dependency of pulling Harbor from Harbor.

### Step 3: Install Traefik Gateway API Controller
```bash
bash 02-traefik-controller/install-traefik-gateway-controller.sh
```
* Installs standard Gateway API CRDs (`v1.6.2`).
* Deploys Traefik v3 DaemonSet with entrypoint HTTP-to-HTTPS redirect enabled.

### Step 4: Install cert-manager & ClusterIssuer
```bash
bash 03-cert-manager/install-cert-manager.sh
```
* Deploys cert-manager `v1.21.2` with CRDs and Gateway API integration.
* Injects Root CA into `local-root-ca-secret` and configures `ClusterIssuer/local-ca-issuer`.

### Step 5: Deploy GatewayClass, Gateway & TLS Certificate
```bash
bash 04-traefik-gateway/install-traefik-gatewayclass.sh
```
* Deploys GatewayClass `traefik` and Gateway `main-gateway`.
* Declares `Certificate/domain-wildcard-cert`, which cert-manager automatically signs and populates into `domain-certificate-tls-secret`.

### Step 6: Install Metrics Server
```bash
bash 05-infra-apps/02-metrics-server/install-metrics-server.sh
```
* Installs Metrics Server for cluster resource metrics (`kubectl top nodes`, `kubectl top pods`).

### Step 7: Install Harbor Container Registry
```bash
bash 05-infra-apps/03-harbor/install-harbor.sh
```
* Deploys Harbor Registry, PostgreSQL, Valkey/Redis, Jobservice, Portal, and Trivy.
* Exposes UI and registry API at `https://cr.chetan.local`.
* Automatically verifies API health status via `https://cr.chetan.local/api/v2.0/health`.

### Step 8: Install Forgejo Git Service & Seed GitOps Repository
```bash
bash 05-infra-apps/04-forgejo/install-forgejo.sh
bash 05-infra-apps/04-forgejo/sync-repo-to-forgejo.sh
```
* Deploys Forgejo Git service at `https://git.chetan.local`.
* Confirms API health at `/api/v1/version`.
* Automatically creates `forgejo_admin/gitops-argocd-infra` repository.
* Configures dual-remote Git (`origin` = GitHub, `forgejo` = in-cluster) and pushes the active working branch.

### Step 9: Install Forgejo Actions Runner
```bash
bash 05-infra-apps/05-forgejo-runner/install-forgejo-runner.sh
```
* Deploys the Forgejo Actions runner with Docker-in-Docker (DinD) sidecar.
* Connects internally to Forgejo for native in-cluster CI/CD pipelines.

### Step 10: Install Argo CD, Adopt Platform Apps & Configure Repo
```bash
bash 06-argocd/01-install-argocd.sh
bash 06-argocd/02-adopt-infra-apps.sh
bash 06-argocd/03-configure-forgejo-repo.sh
```
* Installs Argo CD in `argocd` namespace and exposes UI via `https://argocd.chetan.local`.
* Adopts all 6 platform applications (`traefik`, `metrics-server`, `cert-manager`, `harbor`, `forgejo`, `forgejo-runner`) into declarative GitOps control.
* Configures `Secret/forgejo-infra-repo-secret` for in-cluster GitOps synchronization via `http://forgejo-http.forgejo.svc.cluster.local:3000/...`.

### Step 11: Connect Workload Repo & Deploy ApplicationSet
```bash
# 1. Configure GitHub token in .env:
cp 07-apps/.env.example 07-apps/.env
# Edit 07-apps/.env with your GitHub Personal Access Token (PAT)

# 2. Apply GitHub repo credentials secret:
bash 07-apps/01-install-repo-creds-secret.sh

# 3. Deploy the root Matrix ApplicationSet:
bash 07-apps/02-install-root-app.sh
```
* Argo CD connects to `https://github.com/erchetansoni/gitops-argocd-apps.git`.
* Discovers all environment folders (`environments/main`, `environments/dev`) and deploys all application microservices automatically.

---

## 🔄 Dual-Remote GitOps Workflow (`origin` vs `forgejo`)

A key advantage of this architecture is that your local workstation repository is linked to **both** your remote GitHub repository and your in-cluster Forgejo service simultaneously:

```text
 workstation (git commit)
        │
        ├──► git push origin main   ──► GitHub (Cloud backup, PR review, team sharing)
        │
        └──► git push forgejo main  ──► In-Cluster Forgejo (Instant local Argo CD sync, 0 latency, offline)
```

* **Zero GitHub Rate Limiting**: Argo CD polls in-cluster Forgejo every 3 minutes with zero risk of hitting GitHub API rate-limits or PAT token expiration.
* **100% Offline / Air-Gap Operation**: Even if your external Internet goes down, local commits pushed to `forgejo` immediately trigger Argo CD reconciliations.
* **Inspect remotes at any time**:
  ```bash
  git remote -v
  ```

---

## 🐳 Day-0 Platform Bootstrap vs Day-1/Day-2 Container Image Architecture

To avoid the common architectural trap ("chicken-and-egg") where Kubernetes cannot start a local registry because it needs the registry to pull the registry image:

| Stage | Responsibility | Mechanism |
| :--- | :--- | :--- |
| **Day 0 (Platform Bootstrap)** | Core infrastructure pods (Traefik, cert-manager, Metrics Server, Harbor, Forgejo, Argo CD) | Pre-loaded into KinD node containerd runtime via `load-images-to-kind.sh` with `imagePullPolicy: IfNotPresent` |
| **Day 1 / Day 2 (Workloads & CI/CD)** | Application microservices, custom container builds, and Helm charts | Pushed to and served by **Harbor** (`cr.chetan.local`) |

---

## 📖 Complete Scripts, Arguments & Environment Variables Reference

Every script in this repository supports configurable environment variables, command-line arguments, and flags for customization across development, CI/CD, and air-gapped production:

### 1. Orchestration Script

| Script | Purpose | Arguments / Flags | Environment Variables (with Defaults) | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`main.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/main.sh)** | End-to-end automated platform bootstrap (Steps 01 to 06) | None | `INSTALL_MODE`: `"online"` or `"airgap"` *(Auto-detected via connectivity check if unset)* | `INSTALL_MODE=airgap ./main.sh` |

---

### 2. Cluster Creation & Image Preloading

| Script | Purpose | Arguments / Flags | Environment Variables (with Defaults) | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`01-create-cluster/create-cluster.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/01-create-cluster/create-cluster.sh)** | Creates single-node KinD cluster with hostPort 80/443 | None | Uses `01-create-cluster/kind-cluster-config.yaml` | `./01-create-cluster/create-cluster.sh` |
| **[`01-create-cluster/create-cluster.ps1`](file:///c:/Projects/My_Projects/gitops-argocd-infra/01-create-cluster/create-cluster.ps1)** | PowerShell version of cluster creation | `-Force` (`-f`): Suppress confirmation prompt if cluster already exists | None | `.\01-create-cluster\create-cluster.ps1 -Force` |
| **[`01-create-cluster/load-images-to-kind.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/01-create-cluster/load-images-to-kind.sh)** | Pre-loads container images into KinD containerd cache | `-p, --pull`: Auto-pull missing images<br>`-a, --archive [path]`: Load from tar archive<br>`-n, --name [cluster]`: KinD cluster name<br>`-l, --list`: Preview missing/present images<br>`-h, --help`: Show help | `DEFAULT_CLUSTER`: `"gitops-demo-cluster"`<br>`IMAGES_FILE`: `airgap/images.yaml` | `./01-create-cluster/load-images-to-kind.sh --pull`<br>`./load-images-to-kind.sh --archive airgap/airgap-images.tar` |
| **[`01-create-cluster/load-images-to-kind.ps1`](file:///c:/Projects/My_Projects/gitops-argocd-infra/01-create-cluster/load-images-to-kind.ps1)** | PowerShell version of image loader | `-Pull`: Pull missing images<br>`-Archive [path]`: Load from tarball<br>`-Name [cluster]`: Cluster name<br>`-ListOnly`: Preview cache | None | `.\01-create-cluster\load-images-to-kind.ps1 -Pull` |

---

### 3. Gateway, Ingress & TLS Controllers

| Script | Purpose | Arguments / Flags | Environment Variables (with Defaults) | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`02-traefik-controller/install-traefik-gateway-controller.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/02-traefik-controller/install-traefik-gateway-controller.sh)** | Installs Gateway API CRDs & Traefik v3 DaemonSet | None | `NAMESPACE`: `"traefik"`<br>`RELEASE_NAME`: `"traefik"`<br>`GATEWAY_API_VERSION`: `"v1.6.2"`<br>`HELM_REPO_URL`: `"https://traefik.github.io/charts"` | `NAMESPACE=custom-traefik ./install-traefik-gateway-controller.sh` |
| **[`03-cert-manager/install-cert-manager.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/03-cert-manager/install-cert-manager.sh)** | Installs cert-manager & injects local Root CA | None | `NAMESPACE`: `"cert-manager"`<br>`RELEASE_NAME`: `"cert-manager"`<br>`CHART_VERSION`: `"v1.21.2"`<br>`HELM_REPO_URL`: `"https://charts.jetstack.io"` | `./03-cert-manager/install-cert-manager.sh` |
| **[`04-traefik-gateway/install-traefik-gatewayclass.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/install-traefik-gatewayclass.sh)** | Deploys GatewayClass, Gateway, & Wildcard TLS Cert | None | `SECRET_NAME`: `"domain-certificate-tls-secret"`<br>`SECRET_NAMESPACE`: `"default"` | `./04-traefik-gateway/install-traefik-gatewayclass.sh` |

---

### 4. Custom TLS & Root CA Generation / Trust Store Setup

| Script | Purpose | Arguments / Flags | Environment Variables / Parameters | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`04-traefik-gateway/cert/tls-generator/server/generate-certs.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/cert/tls-generator/server/generate-certs.sh)** | Generates 10-yr Root CA & 5-yr Wildcard TLS Cert (`*.chetan.local`) | None | `MAIN_DOMAIN`: `"chetan.local"`<br>`CA_VALIDITY_DAYS`: `3650`<br>`CERT_VALIDITY_DAYS`: `1825`<br>`CA_COMMON_NAME`: `"Local Root CA"` | `bash 04-traefik-gateway/cert/tls-generator/server/generate-certs.sh` |
| **[`04-traefik-gateway/cert/tls-generator/server/generate-certs.ps1`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/cert/tls-generator/server/generate-certs.ps1)** | Windows PowerShell version of certificate generator | None | Configurable variables inside script (`$MainDomain`, `$CaValidityDays`) | `powershell -File .\04-traefik-gateway\cert\tls-generator\server\generate-certs.ps1` |
| **[`04-traefik-gateway/cert/tls-generator/client/install-ca-linux.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/cert/tls-generator/client/install-ca-linux.sh)** | Installs Root CA into Debian/Ubuntu/RHEL/Arch trust store | Requires `sudo` | Expects `rootCA.crt` in script directory | `sudo bash ./install-ca-linux.sh` |
| **[`04-traefik-gateway/cert/tls-generator/client/install-ca-windows.ps1`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/cert/tls-generator/client/install-ca-windows.ps1)** | Imports Root CA into Windows `Trusted Root Certification Authorities` | Requires Administrator | Expects `rootCA.crt` in script directory | `.\install-ca-windows.ps1` |
| **[`04-traefik-gateway/cert/tls-generator/client/uninstall-ca-linux.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/cert/tls-generator/client/uninstall-ca-linux.sh)** | Removes Root CA from Linux system trust store | Requires `sudo` | Removes `avgol-internal-root-ca.crt` | `sudo bash ./uninstall-ca-linux.sh` |
| **[`04-traefik-gateway/cert/tls-generator/client/uninstall-ca-windows.ps1`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/cert/tls-generator/client/uninstall-ca-windows.ps1)** | Removes Root CA from Windows `Trusted Root Certification Authorities` | `-CaCommonName [string]` (Default: `"Avgol Internal Root CA"`) | Requires Administrator | `.\uninstall-ca-windows.ps1 -CaCommonName "Local Root CA"` |

---

### 5. Platform Infrastructure Applications

| Script | Purpose | Arguments / Flags | Environment Variables (with Defaults) | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`05-infra-apps/02-metrics-server/install-metrics-server.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/05-infra-apps/02-metrics-server/install-metrics-server.sh)** | Deploys Metrics Server for `kubectl top` | None | `NAMESPACE`: `"kube-system"`<br>`RELEASE_NAME`: `"metrics-server"`<br>`CHART_VERSION`: `"3.14.0"` | `./install-metrics-server.sh` |
| **[`05-infra-apps/03-harbor/install-harbor.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/05-infra-apps/03-harbor/install-harbor.sh)** | Installs Harbor Registry & verifies `/api/v2.0/health` | None | `NAMESPACE`: `"harbor"`<br>`RELEASE_NAME`: `"harbor"`<br>`CHART_VERSION`: `"1.19.2"`<br>`HARBOR_HOST`: `"cr.chetan.local"`<br>`HELM_REPO_URL`: `"https://helm.goharbor.io"` | `HARBOR_HOST=cr.mydomain.local ./install-harbor.sh` |
| **[`05-infra-apps/04-forgejo/install-forgejo.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/05-infra-apps/04-forgejo/install-forgejo.sh)** | Installs Forgejo Git service & verifies `/api/v1/version` | None | `NAMESPACE`: `"forgejo"`<br>`RELEASE_NAME`: `"forgejo"`<br>`CHART_VERSION`: `"17.2.0"`<br>`FORGEJO_HOST`: `"git.chetan.local"` | `./install-forgejo.sh` |
| **[`05-infra-apps/04-forgejo/sync-repo-to-forgejo.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/05-infra-apps/04-forgejo/sync-repo-to-forgejo.sh)** | Seeds repo via API, configures dual-remote, pushes branch | None | `FORGEJO_HOST`: `"git.chetan.local"`<br>`FORGEJO_USER`: `"forgejo_admin"`<br>`FORGEJO_PASS`: `"Forgejo12345"`<br>`FORGEJO_REPO_NAME`: `"gitops-argocd-infra"`<br>`GIT_REMOTE_NAME`: `"forgejo"` | `./sync-repo-to-forgejo.sh` |
| **[`05-infra-apps/05-forgejo-runner/install-forgejo-runner.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/05-infra-apps/05-forgejo-runner/install-forgejo-runner.sh)** | Generates runner token from pod & deploys DinD runner | None | `NAMESPACE`: `"forgejo-runner"`<br>`RELEASE_NAME`: `"forgejo-runner"`<br>`CHART_VERSION`: `"0.7.6"`<br>`FORGEJO_NAMESPACE`: `"forgejo"`<br>`FORGEJO_INSTANCE_URL`: `"http://forgejo-http.forgejo.svc.cluster.local:3000"`<br>`RUNNER_SECRET_NAME`: `"forgejo-runner-secret"` | `./install-forgejo-runner.sh` |

---

### 6. Argo CD & GitOps Control Plane

| Script | Purpose | Arguments / Flags | Environment Variables (with Defaults) | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`06-argocd/01-install-argocd.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/06-argocd/01-install-argocd.sh)** | Installs Argo CD, applies configmaps & exposes UI | None | `ARGOCD_NAMESPACE` / `NAMESPACE`: `"argocd"`<br>`ARGOCD_HOST`: `"argocd.chetan.local"`<br>`ARGOCD_VERSION`: `"3.5.3"` | `./01-install-argocd.sh` |
| **[`06-argocd/02-adopt-infra-apps.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/06-argocd/02-adopt-infra-apps.sh)** | Adopts 6 infra apps; deploys `airgap-helm-repo` if offline | None | `ARGOCD_NAMESPACE` / `NAMESPACE`: `"argocd"`<br>`INSTALL_MODE`: `"online"` or `"airgap"`<br>`INFRA_MANIFEST`: auto-detects `platform-apps.yaml` | `INSTALL_MODE=airgap ./02-adopt-infra-apps.sh` |
| **[`06-argocd/03-configure-forgejo-repo.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/06-argocd/03-configure-forgejo-repo.sh)** | Creates repo secret, tests connectivity & applies `app-of-apps.yaml` | None | `ARGOCD_NAMESPACE` / `NAMESPACE`: `"argocd"`<br>`FORGEJO_INTERNAL_URL`: `"http://forgejo-http.forgejo.svc.cluster.local:3000/forgejo_admin/gitops-argocd-infra.git"`<br>`FORGEJO_USER`: `"forgejo_admin"`<br>`FORGEJO_PASS`: `"Forgejo12345"`<br>`SECRET_NAME`: `"forgejo-infra-repo-secret"` | `./03-configure-forgejo-repo.sh` |

---

### 7. Workload Applications (`07-apps`)

| Script | Purpose | Arguments / Flags | Environment Variables (from `.env` or Shell) | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`07-apps/01-install-repo-creds-secret.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/07-apps/01-install-repo-creds-secret.sh)** | Configures private GitHub PAT secret in Argo CD | `$1`: Optional GitHub PAT token | `REPO_URL` / `GITHUB_REPO_URL`: `"https://github.com/erchetansoni/gitops-argocd-apps.git"`<br>`GITHUB_USER` / `GITHUB_USERNAME`: `"erchetansoni"`<br>`GITHUB_TOKEN`: PAT string<br>`REPO_SECRET_NAME`: `"repo-creds-secret"`<br>`ARGOCD_NAMESPACE`: `"argocd"` | `./01-install-repo-creds-secret.sh ghp_yourToken` |
| **[`07-apps/02-install-root-app.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/07-apps/02-install-root-app.sh)** | Deploys root Matrix ApplicationSet for branch envs | None | `APPLICATIONSET_FILE`: `root-app/root-applicationset.yaml`<br>`ARGOCD_NAMESPACE`: `"argocd"`<br>`REPO_URL`: Dynamic repoURL substitution | `./02-install-root-app.sh` |

---

### 8. Offline Packaging, Node Loading & Image Cleanup

| Script | Purpose | Arguments / Flags | Environment Variables (with Defaults) | Example Usage |
| :--- | :--- | :--- | :--- | :--- |
| **[`airgap/bundle-offline-assets.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/airgap/bundle-offline-assets.sh)** | Pulls images & packages `airgap-images.tar` | None | `TARGET_PLATFORM`: `"linux/amd64"`<br>`IMAGES_FILE`: auto-detects `images.yaml`<br>`OUTPUT_TAR`: `airgap/airgap-images.tar` | `./airgap/bundle-offline-assets.sh` |
| **[`airgap/load-offline-assets.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/airgap/load-offline-assets.sh)** | Imports image tarball into K3s containerd nodes | `-c, --clean-source`: Delete tarball after load<br>`-s, --skip-clean`: Skip cleanup phase<br>`-h, --help`: Show help | `TAR_FILE`: `airgap/airgap-images.tar`<br>`K3S_IMAGES_DIR`: `/var/lib/rancher/k3s/agent/images` | `sudo ./airgap/load-offline-assets.sh --clean-source` |
| **[`airgap/clean-offline-assets.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/airgap/clean-offline-assets.sh)** | Deletes tarballs inside `airgap/` directory | Forwards all arguments to `clean-images.sh` | None | `./airgap/clean-offline-assets.sh --dry-run` |
| **[`clean-images.sh`](file:///c:/Projects/My_Projects/gitops-argocd-infra/clean-images.sh)** | Interactive/CLI disk cleanup of all image tarballs | `-d, --dry-run`: Preview reclaimed bytes<br>`-f, --force`: Skip confirmation prompt<br>`-h, --help`: Show help<br>`[DIRECTORY]`: Target path (default: root) | None | `./clean-images.sh --dry-run`<br>`./clean-images.sh --force ./airgap` |
| **[`clean-images.ps1`](file:///c:/Projects/My_Projects/gitops-argocd-infra/clean-images.ps1)** | PowerShell version of disk archive cleanup | `-DryRun` (`-d`): Preview without deleting<br>`-Force` (`-f`): Skip prompt<br>`-Path [string]`: Target directory path | None | `.\clean-images.ps1 -DryRun`<br>`.\clean-images.ps1 -Path .\airgap -Force` |



---

## 🌐 DNS & Local Domain Configuration

Add the following mappings to your local hosts file:
* **Windows**: `C:\Windows\System32\drivers\etc\hosts` (run Notepad as Administrator)
* **Linux / macOS**: `/etc/hosts`

```text
127.0.0.1 argocd.chetan.local
127.0.0.1 cr.chetan.local
127.0.0.1 git.chetan.local
127.0.0.1 app1.chetan.local
127.0.0.1 app2.chetan.local
127.0.0.1 app3.chetan.local
127.0.0.1 app1.dev.chetan.local
127.0.0.1 app2.dev.chetan.local
127.0.0.1 app3.dev.chetan.local
```

---

## 🔒 Trusting the Root CA (Green Lock in Browser)

To eliminate browser security warnings on `*.chetan.local` and `*.dev.chetan.local`:

1. Locate the Root CA certificate:
   [`04-traefik-gateway/cert/tls-generator/client/rootCA.crt`](file:///c:/Projects/My_Projects/gitops-argocd-infra/04-traefik-gateway/cert/tls-generator/client/rootCA.crt)
2. Double-click the file -> **Install Certificate...** -> select **Local Machine** -> **Next**.
3. Choose **Place all certificates in the following store** -> click **Browse**.
4. Select **Trusted Root Certification Authorities** -> **OK** -> **Finish**.
5. Restart your browser.

---

## 🔍 Verification & Inspection Commands

```bash
# Check all Argo CD Applications
kubectl get applications -n argocd

# Check Gateway and HTTPRoutes
kubectl get gateway,httproute -A

# Test HTTP to HTTPS redirection (returns HTTP 301)
curl -s -D - -H "Host: app1.chetan.local" http://127.0.0.1/
curl -s -D - -H "Host: app1.dev.chetan.local" http://127.0.0.1/

# Test HTTPS endpoints directly
curl -k https://app1.chetan.local/
curl -k https://app1.dev.chetan.local/
curl -k https://argocd.chetan.local/
curl -k https://cr.chetan.local/
curl -k https://git.chetan.local/

# Test Harbor Docker Registry CLI Login
docker login cr.chetan.local -u admin -p Harbor12345

# Test Forgejo Git HTTP Clone
git clone https://admin:Forgejo12345@git.chetan.local/admin/test-repo.git
```

---

## 🌍 Multi-Cloud & On-Premises Deployment Guide

While this repository defaults to a local **KinD** cluster with Docker port-mapping, the Gateway API and GitOps structure seamlessly scale to multi-node clusters across **AWS**, **GCP**, and on-premises **Proxmox VE**.

### Summary of Differences Across Targets

| Feature | KinD (Local Dev) | GCP (GKE) | AWS (EKS) | Proxmox VE (Bare-metal / VMs) |
| :--- | :--- | :--- | :--- | :--- |
| **Cluster Topology** | 1 Docker node | 3+ GKE worker nodes | 3+ EKS worker nodes | 3+ VMs (e.g. Talos / k3s / kubeadm) |
| **Service Type** | `ClusterIP` + `hostPort: 80/443` | `LoadBalancer` (Cloud NLB) | `LoadBalancer` (AWS NLB) | `LoadBalancer` (via MetalLB or Cilium BGP) |
| **Traefik hostPort** | `80` & `443` enabled | Disabled | Disabled | Optional (or use MetalLB VIP) |
| **External Access / IP** | `127.0.0.1` | GCP External Static/Ephemeral IP | AWS NLB DNS name (`*.elb.amazonaws.com`) | Dedicated LAN VIP (e.g. `192.168.1.200`) |
| **DNS Resolution** | Workstation `/etc/hosts` | Cloud DNS (`*.yourdomain.com` -> IP) | Route 53 (`*.yourdomain.com` -> NLB) | Pi-hole / pfSense / Local DNS Server |
| **TLS Certificates** | Local Root CA via `cert-manager` (`03-cert-manager`) | `cert-manager` + Let's Encrypt / Commercial | `cert-manager` or AWS ACM | `cert-manager` (Let's Encrypt / Commercial) |

---

### 1. ☁️ Google Cloud Platform (GCP - GKE)

1. **Traefik Service (`traefik-values.yaml`)**:
   Set `service.spec.type: LoadBalancer` and remove `hostPort`. GCP will provision a Passthrough Network Load Balancer (TCP):
   ```yaml
   service:
     enabled: true
     spec:
       type: LoadBalancer
       externalTrafficPolicy: Local
   ports:
     web:
       port: 80
       containerPort: 80
       exposedPort: 80
       # hostPort: 80   <-- Remove
     websecure:
       port: 443
       containerPort: 443
       exposedPort: 443
       # hostPort: 443  <-- Remove
   ```

2. **DNS & TLS**:
   * Get the external IP via `kubectl get svc traefik -n traefik`.
   * In **Google Cloud DNS**, create a wildcard `A` record: `*.yourdomain.com` pointing to the LoadBalancer IP.
   * Deploy `cert-manager` with a Let's Encrypt `ClusterIssuer` using the GCP Cloud DNS solver.

---

### 2. 🟧 Amazon Web Services (AWS - EKS)

1. **Traefik Service (`traefik-values.yaml`)**:
   Deploy the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) and annotate the service for an external Network Load Balancer (NLB):
   ```yaml
   service:
     enabled: true
     spec:
       type: LoadBalancer
       annotations:
         service.beta.kubernetes.io/aws-load-balancer-type: "external"
         service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
         service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
   ```

2. **DNS & TLS**:
   * In **Route 53**, create an `A` (Alias) record: `*.yourdomain.com` pointing to the AWS NLB DNS.
   * Traefik can terminate TLS using a wildcard cert issued via `cert-manager` (Route 53 DNS-01 challenge) or offload TLS directly at the NLB using AWS Certificate Manager (ACM).

---

### 3. 🖥️ Proxmox VE (HomeLab / Private Cloud)

When running a 3-node Kubernetes cluster inside Proxmox (e.g., using **Talos Linux**, **k3s**, or **Ubuntu + kubeadm** VMs):

1. **Bare-metal Load Balancer (MetalLB / Cilium)**:
   Proxmox does not natively provide a cloud load balancer. Install **[MetalLB](https://metallb.io/installation/)** in Layer 2 mode to assign IPs from your home/homelab subnet:
   ```yaml
   apiVersion: metallb.io/v1beta1
   kind: IPAddressPool
   metadata:
     name: proxmox-ip-pool
     namespace: metallb-system
   spec:
     addresses:
       - 192.168.1.200-192.168.1.210  # Range on your Proxmox LAN
   ---
   apiVersion: metallb.io/v1beta1
   kind: L2Advertisement
   metadata:
     name: proxmox-l2-advert
     namespace: metallb-system
   ```

2. **Traefik Service (`traefik-values.yaml`)**:
   ```yaml
   service:
     enabled: true
     spec:
       type: LoadBalancer
       loadBalancerIP: 192.168.1.200  # MetalLB assigns this Virtual IP
   ```

3. **DNS & Routing in Proxmox**:
   * In your local network router (pfSense, OPNsense, UniFi, Pi-hole, or dnsmasq), point `*.chetan.local` or `*.yourhomelab.net` to `192.168.1.200`.
   * Any client on your local WiFi/LAN can now access `https://app1.yourhomelab.net` without modifying workstation `hosts` files!

---

### 4. 🔒 Air-Gapped 3-Node K3s Cluster

When moving from local KinD to a production **3-node K3s cluster with no internet access**:
* **Complete Guide**: Refer to **[`airgap/README.md`](airgap/README.md)**.
* **Pre-bundled Assets**:
  * Run `bash airgap/bundle-offline-assets.sh` on a connected machine to export all 9 platform container images into `airgap/airgap-images.tar` and package Helm charts.
  * Load images on all 3 K3s nodes with `sudo bash airgap/load-offline-assets.sh` (automatically cleans stale archives and prunes dangling images before loading, with `--clean-source` option to free node disk space).
  * Clean local image tarballs (`*.tar`, `*.tgz`, `*.tar.gz`, `*.tar.zst`) at any time using `./clean-images.sh` or `.\clean-images.ps1`.
* **K3s Requirement**: Install K3s with `--disable=traefik` to prevent K3s default Traefik from conflicting with Gateway API.

* All deployment scripts (`02-traefik-controller`, `03-cert-manager`, `05-infra-apps`, `06-argocd`) automatically detect and use the local `.tgz` charts and offline manifests without internet connectivity.

---

## 💳 Managing Commercial / Paid Certificates in Production

When purchasing commercial SSL/TLS certificates (DigiCert, Sectigo, GlobalSign, GoDaddy, etc.) for real production domains (`*.yourdomain.com`):

### 1. Bundle Certificate Chain
Always combine the server certificate and the intermediate CA bundle into a full-chain file:
```bash
cat your_domain.crt ca-bundle.crt > fullchain.crt
```

### 2. Deployment Options
* **Direct Secret (Manual / Non-GitOps)**:
  ```bash
  kubectl create secret tls domain-certificate-tls-secret \
    --cert=fullchain.crt \
    --key=your_domain.key \
    --namespace=default
  ```
* **GitOps-Safe (Bitnami Sealed Secrets / External Secrets Operator)**:
  Never commit `your_domain.key` in plaintext. Encrypt via `kubeseal` into a `SealedSecret` or sync directly from AWS Secrets Manager / Azure Key Vault / GCP Secret Manager using the **External Secrets Operator (ESO)**.
* **Automated Renewal via cert-manager (ACME + EAB)**:
  Commercial CAs (Sectigo, DigiCert, ZeroSSL) support ACME with External Account Binding (EAB), allowing cert-manager to negotiate and rotate paid certificates automatically before expiration.

*For complete configuration manifests, see [03-cert-manager/README.md](03-cert-manager/README.md) and [04-traefik-gateway/README.md](04-traefik-gateway/README.md).*

---

## 🤝 Companion Repository

To configure applications, modify Helm values, or create new environment branches (`dev`, `staging`, `prod`), refer to:  
👉 **[`erchetansoni/gitops-argocd-apps`](https://github.com/erchetansoni/gitops-argocd-apps)**


