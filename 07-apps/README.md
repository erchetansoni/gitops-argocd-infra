# 07 - Apps Layer (Workload Repository Integration)

This directory connects Argo CD to the workload repository ([`erchetansoni/gitops-argocd-apps`](https://github.com/erchetansoni/gitops-argocd-apps)) and deploys the root **ApplicationSet**.

---

## Overview

In the two-repository GitOps architecture:
* **Infrastructure Repository** (`gitops-argocd-infra`): Configures the cluster, Traefik, certificates, and Argo CD.
* **Workload Repository** (`gitops-argocd-apps`): Houses application Helm charts and per-environment overlays (`environments/main`, `environments/dev`).

This directory connects the two by:
1. Creating private repository authentication credentials in Argo CD ([01-install-repo-creds-secret.sh](01-install-repo-creds-secret.sh)).
2. Deploying the dynamic matrix ApplicationSet ([02-install-root-app.sh](02-install-root-app.sh)).

---

## File Structure

```
07-apps/
├── .env.example                     # Sample environment file
├── 01-install-repo-creds-secret.sh  # Script to configure GitHub credentials in Argo CD
├── 02-install-root-app.sh           # Script to deploy the root ApplicationSet
├── github-repo-secret.template.yaml # Declarative Secret template (for CI/CD or SealedSecrets)
├── root-app/
│   ├── README.md                    # Detailed documentation on Matrix generator
│   └── root-applicationset.yaml     # ApplicationSet manifest
└── README.md                        # Documentation
```

---

## 🔐 GitHub Access Token Setup

To allow Argo CD to pull manifests from your private repository `https://github.com/erchetansoni/gitops-argocd-apps.git`:

### Recommended: Fine-Grained Personal Access Token (PAT)
1. Navigate to: **[https://github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new)**
2. **Token name:** `gitops-argocd-apps-reader`
3. **Repository access:** Select **Only select repositories** -> `erchetansoni/gitops-argocd-apps`
4. **Permissions:**
   * **Contents**: `Read-only`
   * **Metadata**: `Read-only` (automatic)
5. Generate and copy the token (`github_pat_...`).

---

## Quickstart

### Step 1: Configure `.env`
Copy the sample file and update your credentials:
```bash
cp 07-apps/.env.example 07-apps/.env
```

Ensure `.env` contains:
```env
REPO_URL="https://github.com/erchetansoni/gitops-argocd-apps.git"
GITHUB_USERNAME="erchetansoni"
GITHUB_TOKEN="github_pat_xxxxxxxxxxxxxxxxxxxx"
REPO_SECRET_NAME="repo-creds-secret"
ARGOCD_NAMESPACE="argocd"
ARGOCD_HOST="argocd.chetan.local"
```

### Step 2: Configure Credentials in Argo CD
```bash
bash 07-apps/01-install-repo-creds-secret.sh
```

### Step 3: Deploy the Root ApplicationSet
```bash
bash 07-apps/02-install-root-app.sh
```

---

## How Applications Are Generated

The root ApplicationSet uses a **Matrix Generator**:
$$\text{Environments (environments/*)} \times \text{Apps (app1, app2, app3)}$$

* For every folder inside `environments/` in `gitops-argocd-apps`:
  * `environments/main` -> Generates `main-app1`, `main-app2`, `main-app3` in the `main` namespace.
  * `environments/dev`  -> Generates `dev-app1`, `dev-app2`, `dev-app3` in the `dev` namespace.
* Adding a new environment (e.g. `environments/staging`) automatically deploys all applications to that new namespace without editing the root ApplicationSet!

---

## Verification

Check connected repositories in Argo CD:
```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

Check generated applications:
```bash
kubectl get applications -n argocd
```

View in Argo CD UI: [https://argocd.chetan.local](https://argocd.chetan.local)
