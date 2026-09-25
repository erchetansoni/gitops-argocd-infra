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
        Browser["🌐 Web Browser\n(app1.chetan.local, app1.dev.chetan.local,\nargocd.chetan.local)"]
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

        subgraph PlatformLayer["🛠️ Platform & Monitoring"]
            MetricsServer["Metrics Server (kube-system namespace)\n(CPU & Memory Metrics)"]
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

    ArgoCD -->|Adopts & Manages| Traefik
    ArgoCD -->|Adopts & Manages| MetricsServer
    ArgoCD -->|Watches & Syncs| AppsRepo

    AppsRepo -.->|ApplicationSet Matrix| MainEnv
    AppsRepo -.->|ApplicationSet Matrix| DevEnv
```

---

## 📂 Repository Directory Layout

Each numbered directory encapsulates a specific stage of the platform bootstrap lifecycle:

| Directory | Purpose | Key Manifests & Scripts |
| :--- | :--- | :--- |
| **[`01-create-cluster`](file:///c:/Projects/My_Projects/GitOps-demo/01-create-cluster/README.md)** | Local Kind Kubernetes cluster | `kind-cluster-config.yaml`, `create-cluster.sh` |
| **[`02-Traefik-Gateway-Controller`](file:///c:/Projects/My_Projects/GitOps-demo/02-Traefik-Gateway-Controller/README.md)** | Gateway API CRDs & Traefik v3 DaemonSet | `install-traefik-gateway-controller.sh`, `traefik-values.yaml` |
| **[`03-Traefik-Gateway-Class`](file:///c:/Projects/My_Projects/GitOps-demo/03-Traefik-Gateway-Class/README.md)** | GatewayClass, Gateway listeners & TLS | `install-gatewayclass_and_gateway.yaml`, `cert/tls-generator/` |
| **[`04-infra-apps`](file:///c:/Projects/My_Projects/GitOps-demo/04-infra-apps/README.md)** | Platform infra apps (Traefik & Metrics Server) | `infra-apps-root.yaml`, `01-traefik-gateway/`, `02-metrics-server/` |
| **[`05-argocd`](file:///c:/Projects/My_Projects/GitOps-demo/05-argocd/README.md)** | Argo CD install, ConfigMaps, HTTPRoute & adoption | `01-install-argocd.sh`, `02-adopt-infra-apps.sh`, `argocd-httproute.yaml` |
| **[`06-apps`](file:///c:/Projects/My_Projects/GitOps-demo/06-apps/README.md)** | Workload Git repo credentials & Root ApplicationSet | `01-install-repo-creds-secret.sh`, `02-install-root-app.sh`, `root-app/` |

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

Follow the sequence from `01` to `06` to stand up the entire platform:

### Step 1: Create the Kind Cluster
```bash
bash 01-create-cluster/create-cluster.sh
```
* Provisions `gitops-demo-cluster` with ports `80` and `443` bound to your localhost.

### Step 2: Install Traefik Gateway API Controller
```bash
bash 02-Traefik-Gateway-Controller/install-traefik-gateway-controller.sh
```
* Installs standard Gateway API CRDs (`v1.6.2`).
* Deploys Traefik v3 DaemonSet with entrypoint HTTP-to-HTTPS redirect enabled.

### Step 3: Deploy GatewayClass, Gateway & TLS Certificates
```bash
bash 03-Traefik-Gateway-Class/install-traefik-gatewayclass.sh
```
* Generates private Root CA and wildcard certificate with SANs (`*.chetan.local`, `*.dev.chetan.local`).
* Creates `domain-certificate-tls-secret` in namespace `default`.
* Creates GatewayClass `traefik` and Gateway `main-gateway`.

### Step 4: Install Argo CD & Expose UI
```bash
bash 05-argocd/01-install-argocd.sh
```
* Installs Argo CD in `argocd` namespace.
* Applies enterprise ConfigMaps (`server.insecure: true`, Kustomize build options, HTTPRoute ignoreDifferences).
* Creates Gateway API route `argocd-server-route` for `https://argocd.chetan.local`.

### Step 5: Adopt Platform Infrastructure Apps
```bash
bash 05-argocd/02-adopt-infra-apps.sh
```
* Seamlessly transfers ownership of Traefik and Metrics Server to Argo CD without terminating running pods.

### Step 6: Connect Workload Repo & Deploy ApplicationSet
```bash
# 1. Configure GitHub token in .env:
cp 06-apps/.env.example 06-apps/.env
# Edit 06-apps/.env with your GitHub Personal Access Token (PAT)

# 2. Apply GitHub repo credentials secret:
bash 06-apps/01-install-repo-creds-secret.sh

# 3. Deploy the root Matrix ApplicationSet:
bash 06-apps/02-install-root-app.sh
```
* Argo CD connects to `https://github.com/erchetansoni/gitops-argocd-apps.git`.
* Discovers all environment folders (`environments/main`, `environments/dev`) and deploys all application microservices automatically.

---

## 🌐 DNS & Local Domain Configuration

Add the following mappings to your local hosts file:
* **Windows**: `C:\Windows\System32\drivers\etc\hosts` (run Notepad as Administrator)
* **Linux / macOS**: `/etc/hosts`

```text
127.0.0.1 argocd.chetan.local
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
   [`03-Traefik-Gateway-Class/cert/tls-generator/client/rootCA.crt`](file:///c:/Projects/My_Projects/GitOps-demo/03-Traefik-Gateway-Class/cert/tls-generator/client/rootCA.crt)
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
```

---

## 🤝 Companion Repository

To configure applications, modify Helm values, or create new environment branches (`dev`, `staging`, `prod`), refer to:  
👉 **[`erchetansoni/gitops-argocd-apps`](https://github.com/erchetansoni/gitops-argocd-apps)**
