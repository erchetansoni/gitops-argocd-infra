# 03 - Harbor Container Registry

Harbor is an open-source trusted cloud-native container registry that stores, signs, and scans container images and Helm charts. Within this GitOps platform, Harbor acts as the private container registry for internal application images and air-gapped artifacts.

---

## Architecture & Gateway API Routing

* **Subdomain**: `cr.chetan.local`
* **Namespace**: `harbor`
* **Helm Chart**: `harbor/harbor` (`v1.19.2`, App Version `v2.15.2`) from `https://helm.goharbor.io`
* **Gateway**: `main-gateway` in namespace `default` (Traefik Gateway API Controller)
* **TLS**: Terminated at `main-gateway` using the wildcard certificate secret `domain-certificate-tls-secret` (`*.chetan.local`) issued by cert-manager's `local-ca-issuer`.
* **Routing**: The Helm chart natively creates a Gateway API `HTTPRoute` named `harbor-route` in namespace `harbor` that attaches to `main-gateway`:
  * Paths `/api/`, `/service/`, `/v2/`, and `/c/` route to `harbor-core` (port 80).
  * Path `/` routes to `harbor-portal` (port 80).

---

## Components Deployed

| Component | Service Name | Role |
| :--- | :--- | :--- |
| **Portal** | `harbor-portal` | Web UI frontend |
| **Core** | `harbor-core` | API server, authentication, webhook, and token service |
| **Jobservice** | `harbor-jobservice` | Asynchronous task management (replication, scanning, GC) |
| **Registry** | `harbor-registry` | OCI / Docker distribution engine |
| **Registry Controller** | `harbor-registryctl` | Controls registry garbage collection and health status |
| **Database** | `harbor-database` | PostgreSQL metadata database |
| **Cache** | `harbor-redis` | Session cache and job queue |
| **Trivy** | `harbor-trivy` | Container image vulnerability scanner |

---

## Quick Start / Manual Installation

To install Harbor directly with Helm:

```bash
./05-infra-apps/03-harbor/install-harbor.sh
```

The script automatically detects if an offline chart package (`airgap/charts/harbor-1.19.2.tgz`) exists and uses it, or pulls from `https://helm.goharbor.io` if online.

---

## Argo CD GitOps Management

Harbor is managed declaratively by Argo CD via:
* **Root Application List**: Declared in [infra-apps-root.yaml](../infra-apps-root.yaml) under `sync-wave: "2"`.
* **Adoption**: Automatically adopted during [06-argocd/02-adopt-infra-apps.sh](../../06-argocd/02-adopt-infra-apps.sh).

Verify Argo CD application status:

```bash
kubectl get application harbor -n argocd
```

---

## Access & Verification

### 1. Web Portal
* **URL**: [https://cr.chetan.local](https://cr.chetan.local)
* **Default Username**: `admin`
* **Default Password**: `Harbor12345`

### 2. DNS / Hosts Setup
Ensure your local `/etc/hosts` (or `C:\Windows\System32\drivers\etc\hosts`) contains:

```
127.0.0.1 cr.chetan.local
```

### 3. Docker CLI Login
To authenticate using Docker CLI:

```bash
docker login cr.chetan.local -u admin -p Harbor12345
```

> [!NOTE]
> If your workstation Docker daemon does not trust the self-signed local CA, add `cr.chetan.local` to `insecure-registries` in your Docker daemon configuration (`/etc/docker/daemon.json` or Docker Desktop Settings -> Docker Engine):
> ```json
> {
>   "insecure-registries": ["cr.chetan.local"]
> }
> ```
> Or install the cluster Root CA certificate located at `03-cert-manager/cert/ca.crt` into your system trust store or `/etc/docker/certs.d/cr.chetan.local/ca.crt`.

### 4. Push & Pull Verification Test

```bash
# Pull a small test image
docker pull alpine:latest

# Tag image for Harbor
docker tag alpine:latest cr.chetan.local/library/alpine:latest

# Push to Harbor library project
docker push cr.chetan.local/library/alpine:latest

# Pull from Harbor
docker pull cr.chetan.local/library/alpine:latest
```
