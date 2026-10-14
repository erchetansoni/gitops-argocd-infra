# 04 - Forgejo Git Service

Forgejo is a lightweight, self-hosted, community-driven Git forge (a soft-fork of Gitea). Within this GitOps platform, Forgejo acts as the internal Git repository server providing source control, code review, webhook integration with Argo CD, and built-in CI/CD pipelines via **Forgejo Actions**.

---

## Architecture & Gateway API Routing

* **Subdomain**: `git.chetan.local`
* **Namespace**: `forgejo`
* **Helm Chart**: `oci://code.forgejo.org/forgejo-helm/forgejo` (`v17.2.0`, App Version `v15.0.9`)
* **Gateway**: `main-gateway` in namespace `default` (Traefik Gateway API Controller)
* **TLS**: Terminated at `main-gateway` using the wildcard certificate secret `domain-certificate-tls-secret` (`*.chetan.local`) issued by cert-manager's `local-ca-issuer`.
* **Routing**: The Helm chart natively creates a Gateway API `HTTPRoute` named `forgejo` in namespace `forgejo` attached to `main-gateway` for host `git.chetan.local`.

---

## Components Deployed

| Component | Service Name | Port | Role |
| :--- | :--- | :--- | :--- |
| **Forgejo Server** | `forgejo-http` | `3000` (HTTP) | Web UI, REST API, Git smart HTTP clone/push, Actions dispatcher |
| **Forgejo SSH** | `forgejo-ssh` | `22` (SSH) | Git SSH clone/push daemon |
| **Persistence** | `forgejo-data` PVC | `10Gi` | Repository storage, SQLite metadata, and Git LFS assets |

---

## Default Credentials

* **Web URL**: [https://git.chetan.local](https://git.chetan.local)
* **Admin Username**: `forgejo_admin`
* **Admin Password**: `Forgejo12345`
* **Admin Email**: `admin@chetan.local`

---

## Quick Start / Manual Installation

To install Forgejo directly using Helm:

```bash
./05-infra-apps/04-forgejo/install-forgejo.sh
```

The script automatically detects if an offline chart package (`airgap/charts/forgejo-17.2.0.tgz`) exists and uses it, or pulls from `oci://code.forgejo.org/forgejo-helm/forgejo` when online. It also polls `https://git.chetan.local/api/v1/version` to guarantee the API is fully healthy before reporting success.

---

## 🔄 Seeding the GitOps Repository (`sync-repo-to-forgejo.sh`)

Once Forgejo is healthy, run the repo sync script to publish this platform infrastructure repository into Forgejo:

```bash
./05-infra-apps/04-forgejo/sync-repo-to-forgejo.sh
```

### What this script automates:
1. **Health Verification**: Confirms the Forgejo REST API is responding at `https://git.chetan.local/api/v1/version`.
2. **Repository Creation**: Queries `/api/v1/repos/forgejo_admin/gitops-argocd-infra`. If not present, creates it via `POST /api/v1/user/repos` (with `auto_init: false`).
3. **Dual-Remote Git Configuration**: Configures Git on your workstation so both GitHub and Forgejo are active remotes:
   * **`origin`**: Preserved untouched pointing to GitHub (for cloud backup & team collaboration).
   * **`forgejo`**: Added pointing to `https://forgejo_admin:Forgejo12345@git.chetan.local/forgejo_admin/gitops-argocd-infra.git`.
4. **SSL Bypass for Local Domain**: Automatically configures `git config http.https://git.chetan.local/.sslVerify false` so Git CLI push/fetch operations work seamlessly with the local self-signed CA.
5. **Branch Synchronization**: Pushes the current active working branch directly to Forgejo, and mirrors it into Forgejo's `main` branch.

### Daily Dual-Remote Workflow

```bash
# Push to in-cluster Forgejo (triggers local Argo CD sync instantly, works offline):
git push forgejo main

# Push to GitHub (cloud backup / PR review):
git push origin main
```

---

## 🌐 Network Endpoints: External vs. Internal

Forgejo serves Git repositories across two network boundaries:

| Context | URL | Use Case |
| :--- | :--- | :--- |
| **External (Host Workstation & Browser)** | `https://git.chetan.local/forgejo_admin/gitops-argocd-infra.git` | Browser web UI, local developer `git push/pull` over HTTPS via Traefik Gateway |
| **Internal (In-Cluster Kubernetes Services)** | `http://forgejo-http.forgejo.svc.cluster.local:3000/forgejo_admin/gitops-argocd-infra.git` | Argo CD repo-server and Forgejo Actions Runner polling and cloning without hairpin DNS or TLS overhead |

---

## Argo CD GitOps Management

Forgejo is declared in [infra-apps-root.yaml](../infra-apps-root.yaml) under `sync-wave: "2"`.
It is synchronized alongside other platform infrastructure applications during cluster bootstrapping or via `06-argocd/02-adopt-infra-apps.sh`.

Verify Argo CD application status:

```bash
kubectl get application forgejo -n argocd
```

To configure Argo CD to authenticate with and sync from Forgejo, run:

```bash
./06-argocd/03-configure-forgejo-repo.sh
```

---

## Generating Runner Tokens for CI/CD

To register a Forgejo Actions runner (`forgejo-runner`), an instance-level registration token is required:

```bash
kubectl exec -n forgejo deployment/forgejo -c forgejo -- forgejo actions generate-runner-token
```

This token is used by [05-forgejo-runner](../05-forgejo-runner/README.md) to register the runner automatically.

