# 05 - Forgejo Actions Runner

Forgejo Runner is the daemon responsible for executing CI/CD pipelines defined in Forgejo repositories (Forgejo Actions). It is compatible with GitHub Actions workflow syntax (`.forgejo/workflows/*.yaml` or `.github/workflows/*.yaml`).

---

## Architecture & Execution Engine

* **Namespace**: `forgejo-runner`
* **Helm Chart**: `oci://codeberg.org/wrenix/helm-charts/forgejo-runner` (`v0.7.6`, App Version `v12.7.3`)
* **Instance URL**: `http://forgejo-http.forgejo.svc.cluster.local:3000` (Direct in-cluster service discovery)
* **Execution Mode**: **Docker-in-Docker (DinD)** sidecar (`docker:29.3.1-dind`).
  * Runner pod runs two containers:
    1. `runner`: The Forgejo runner process that polls the Forgejo server and orchestrates steps.
    2. `dind`: Privileged Docker daemon hosting isolated containerized job steps.

---

## Supported Runner Labels

The runner registers with the following workflow labels:
* `ubuntu-latest:docker://node:18-bullseye`
* `ubuntu-22.04:docker://node:18-bullseye`
* `docker:docker://docker:dind`

Workflows can target the runner with:

```yaml
jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running CI inside Kubernetes!"
```

---

## Registration & Secrets

The runner uses an initial configuration secret (`forgejo-runner-secret`) in namespace `forgejo-runner`:

| Secret Key | Description | Example |
| :--- | :--- | :--- |
| `CONFIG_NAME` | Runner identifier displayed in Forgejo UI | `k8s-runner` |
| `CONFIG_INSTANCE` | Forgejo instance endpoint | `http://forgejo-http.forgejo.svc.cluster.local:3000` |
| `CONFIG_TOKEN` | Instance or Organization registration token | `<token>` |

The installation script [install-forgejo-runner.sh](install-forgejo-runner.sh) automatically retrieves this token directly from the running Forgejo pod via `kubectl exec` or creates it on demand.

---

## Quick Start / Manual Installation

```bash
# 1. Ensure Forgejo is running first
./05-infra-apps/04-forgejo/install-forgejo.sh

# 2. Deploy Forgejo Runner
./05-infra-apps/05-forgejo-runner/install-forgejo-runner.sh
```

---

## Argo CD GitOps Management

Forgejo Runner is declared in [platform-apps.yaml](../platform-apps.yaml) under `sync-wave: "3"`.
Because `sync-wave: "3"` executes after Forgejo (`sync-wave: "2"`), Forgejo is fully operational before the runner synchronizes.

Verify Argo CD application status:

```bash
kubectl get application forgejo-runner -n argocd
```
