# 05 - Infrastructure Applications (GitOps Platform Layer)

This directory defines the **platform-level infrastructure applications** managed declaratively by Argo CD using the GitOps pattern.

---

## Overview

In enterprise Kubernetes environments, cluster operations are strictly split into two layers:
1. **Platform / Infra Apps** (this directory): Shared cluster services like Ingress/Gateway controllers, metrics/monitoring, and cert managers managed by the DevOps/Platform team.
2. **Workload Apps** ([07-apps](../07-apps/README.md)): Tenant application microservices managed by development teams.

All platform components are declared in [platform-apps.yaml](platform-apps.yaml) and orchestrated continuously via the App-of-Apps parent [app-of-apps.yaml](app-of-apps.yaml) synced from Forgejo.

---

## Applications Managed

### 1. Traefik Gateway Controller (`01-traefik-gateway/`)
* **Argo CD Application Name**: `traefik-gateway-controller`
* **Helm Chart**: `traefik` (`v41.6.0`) from `https://traefik.github.io/charts`
* **Namespace**: `traefik`
* **Configuration Highlights**:
  * Deployed as a DaemonSet binding directly to `hostPort: 80` and `443`.
  * `updateStrategy.rollingUpdate`: `maxUnavailable: 1`, `maxSurge: 0` for safe single-node rolling updates.
  * Entrypoint redirection: Auto-redirects all port `80` traffic to `443` HTTPS.
  * Gateway API provider enabled (`providers.kubernetesGateway.enabled: true`).

### 2. Metrics Server (`02-metrics-server/`)
* **Argo CD Application Name**: `metrics-server`
* **Helm Chart**: `metrics-server` (`v3.14.0`, image `v0.9.0`) from `https://kubernetes-sigs.github.io/metrics-server/`
* **Namespace**: `kube-system`
* **Configuration Highlights**:
  * Configured with `--kubelet-insecure-tls` and `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname` for seamless local Kind cluster operation.
  * Provides `kubectl top nodes` and `kubectl top pods` metrics.

### 3. cert-manager (declared from `03-cert-manager/`)
* **Argo CD Application Name**: `cert-manager`
* **Helm Chart**: `cert-manager` (`v1.21.2`) from `https://charts.jetstack.io`
* **Namespace**: `cert-manager`
* **Configuration Highlights**:
  * `crds.enabled: true` for automatic CustomResourceDefinition management via Helm.
  * Gateway API support enabled (`extraArgs: [--enable-gateway-api]`).
  * ServerSideApply enabled in Argo CD sync options for clean CRD synchronization.

### 4. Harbor Container Registry (`03-harbor/`)
* **Argo CD Application Name**: `harbor`
* **Helm Chart**: `harbor` (`v1.19.2`, app `v2.15.2`) from `https://helm.goharbor.io`
* **Namespace**: `harbor`
* **Host / Subdomain**: `cr.chetan.local`
* **Configuration Highlights**:
  * Gateway API HTTPRoute (`harbor-route`) attached to `main-gateway`.
  * TLS terminated at Gateway using `*.chetan.local` wildcard certificate.
  * Includes Core, Portal, Registry, Jobservice, Database (PostgreSQL), Redis/Valkey, and Trivy scanner.

### 5. Forgejo Git Service (`04-forgejo/`)
* **Argo CD Application Name**: `forgejo`
* **Helm Chart**: `forgejo` (`v17.2.0`, app `v15.0.9`) from `oci://code.forgejo.org/forgejo-helm/forgejo`
* **Namespace**: `forgejo`
* **Host / Subdomain**: `git.chetan.local`
* **Configuration Highlights**:
  * Gateway API HTTPRoute (`forgejo`) attached to `main-gateway`.
  * TLS terminated at Gateway using `*.chetan.local` wildcard certificate.
  * Built-in Forgejo Actions enabled for native in-cluster CI/CD workflows.
  * Persistent storage for repositories and SQLite database.

### 6. Forgejo Actions Runner (`05-forgejo-runner/`)
* **Argo CD Application Name**: `forgejo-runner`
* **Helm Chart**: `forgejo-runner` (`v0.7.6`, app `v12.7.3`) from `oci://codeberg.org/wrenix/helm-charts/forgejo-runner`
* **Namespace**: `forgejo-runner`
* **Configuration Highlights**:
  * Docker-in-Docker (DinD) sidecar architecture (`docker:29.3.1-dind`).
  * Connects internally to Forgejo via cluster service `http://forgejo-http.forgejo.svc.cluster.local:3000`.
  * Synchronized via Argo CD sync-wave `3` after Forgejo (sync-wave `2`) is running.

### 7. Zabbix Monitoring Platform (`06-zabbix/`)
* **Argo CD Application Name**: `zabbix`
* **Helm Chart**: `helm-zabbix` (`v7.1.0`, app `v7.4.15`) from `https://zabbix-community.github.io/helm-zabbix`
* **Namespace**: `zabbix`
* **Host / Subdomains**:
  * Web UI: `zabbix.chetan.local`
  * Active Server Daemon: `zbx-srv.chetan.local` (Port 10051)
  * Active SQLite3 Proxy: `zbx-proxy.chetan.local` (Port 10051)
  * SNMP Trapper: `zbx-snmp.chetan.local:162/UDP`
* **Configuration Highlights**:
  * **Native High Availability (HA) Cluster**: Dual server nodes (`zabbix-zabbix-server` Active, `zabbix-zabbix-server-standby` Standby) running against TimescaleDB with automated failover via PostgreSQL `ha_node` table coordination.
  * **Decoupled SNMP Trapper (Approach C)**: `zabbix-snmptraps` sidecar container attached directly to the Zabbix Proxy (`zabbix-zabbix-proxy-0`) with `hostPort: 162/UDP`, eliminating server port contention and shared-storage bottlenecks.
  * **Active SQLite3 Zabbix Proxy**: Multi-node cluster configuration via `ZBX_SERVER_HOST: "zabbix-zabbix-server;zabbix-zabbix-server-standby"` with real-time runtime health (shows **Online** green badge in Web UI).
  * **TimescaleDB 2.17.2 & PostgreSQL 16**: High-performance hypertable compression and partitioning with 10Gi persistent storage.
  * **Zabbix Agent 2**: Go-based node agent deployed as a cluster-wide Kubernetes `DaemonSet`.
  * Gateway API HTTPRoute (`zabbix-web`) attached to `main-gateway` with wildcard TLS termination.
* **Documentation & Operations Guide**: See [`06-zabbix/README.md`](06-zabbix/README.md) for how to add network switches (SNMP), PLCs (Modbus TCP/SNMP/MQTT), and hosts (Agent 2), plus complete details on `install-zabbix.sh`, environment variables, arguments, and manifest breakdowns.

---

## File Structure

```
05-infra-apps/
├── 01-traefik-gateway/
│   ├── traefik-application.yaml        # Individual Argo CD Application manifest
│   └── traefik-values.yaml             # Traefik Helm values
├── 02-metrics-server/
│   ├── install-metrics-server.sh       # Pre-install script (used before Argo CD)
│   ├── metrics-server-application.yaml # Individual Argo CD Application manifest
│   └── metrics-server-values.yaml      # Metrics Server Helm values
├── 03-harbor/
│   ├── harbor-application.yaml         # Individual Argo CD Application manifest
│   ├── harbor-values.yaml              # Harbor Helm values (Gateway API HTTPRoute)
│   ├── install-harbor.sh               # Pre-install / standalone install script
│   └── README.md                       # Documentation & Docker push/pull guide
├── 04-forgejo/
│   ├── forgejo-application.yaml        # Individual Argo CD Application manifest
│   ├── forgejo-values.yaml             # Forgejo Helm values (Gateway API HTTPRoute)
│   ├── install-forgejo.sh              # Pre-install / standalone install script
│   ├── sync-repo-to-forgejo.sh         # Seeds gitops-argocd-infra repo and configures dual-remote
│   └── README.md                       # Documentation & Git clone guide
├── 05-forgejo-runner/
│   ├── forgejo-runner-application.yaml # Individual Argo CD Application manifest
│   ├── forgejo-runner-values.yaml      # Forgejo Runner Helm values (DinD sidecar)
│   ├── install-forgejo-runner.sh       # Pre-install / standalone install script
│   └── README.md                       # Documentation & Actions runner guide
├── 06-zabbix/
│   ├── install-zabbix.sh               # Pre-install / standalone install script
│   ├── zabbix-application.yaml         # Individual Argo CD Application manifest
│   ├── zabbix-httproute.yaml           # Gateway API HTTPRoute for zabbix.chetan.local
│   ├── zabbix-values.yaml              # Zabbix Helm values (HA nodes, Proxy SNMP sidecar, TimescaleDB)
│   └── README.md                       # Comprehensive HA architecture & verification guide
├── app-of-apps.yaml                    # Parent Argo CD Application (App-of-Apps) tracking Forgejo main
├── platform-apps.yaml                  # Declarative list of all 7 platform child applications
└── README.md                           # Documentation
```

---

## How Infra Apps Are Managed (App-of-Apps Pattern)

Instead of manual `helm install` commands drifting over time, the platform uses the **GitOps App-of-Apps** pattern:

1. **Child Applications List** (`platform-apps.yaml`): Declares the desired configuration, charts, and values for all 7 infrastructure apps.
2. **Parent Orchestrator** (`app-of-apps.yaml`): A top-level Argo CD Application (`metadata.name: infra-apps`) that continuously watches the in-cluster Forgejo repository on branch `main`.
3. **Adoption**: The script [06-argocd/02-adopt-infra-apps.sh](../06-argocd/02-adopt-infra-apps.sh) injects Helm ownership annotations and applies [platform-apps.yaml](platform-apps.yaml) via Server-Side Apply.
4. **Continuous Sync**: When [06-argocd/03-configure-forgejo-repo.sh](../06-argocd/03-configure-forgejo-repo.sh) applies [app-of-apps.yaml](app-of-apps.yaml), Argo CD establishes a live GitOps feedback loop. Any commit pushed to Forgejo `main` automatically updates the cluster.

---

## Verification

Check the Argo CD status of infra apps:

```bash
kubectl get applications -n argocd
# Output:
# traefik-gateway-controller   Synced   Healthy
# metrics-server               Synced   Healthy
# cert-manager                 Synced   Healthy
# harbor                       Synced   Healthy
# forgejo                      Synced   Healthy
# forgejo-runner               Synced   Healthy
# zabbix                       Synced   Healthy
```

Verify that Metrics Server is working:

```bash
kubectl top nodes
kubectl top pods -A
```

Verify cert-manager deployments:

```bash
kubectl get deployment -n cert-manager
kubectl get crd -l app.kubernetes.io/name=cert-manager
```

---

## 🛠️ How to Upgrade, Downgrade, or Adjust Any Platform App

With the **App-of-Apps** orchestrator in place, you **never** run manual `helm upgrade` or `kubectl apply` commands. Everything is driven by Git pushes to your in-cluster Forgejo repository:

### The 3-Step Modification Workflow:

1. **Edit `platform-apps.yaml` locally**:
   * *To upgrade/downgrade an app*: Change `targetRevision` under the app's `source:` block (e.g., change `targetRevision: 3.14.0` to `3.13.0` for `metrics-server`).
   * *To adjust Helm values*: Edit the `valuesObject:` section (e.g., change replicas, memory/CPU requests, or log levels).
2. **Commit and push to Forgejo**:
   ```bash
   git add 05-infra-apps/platform-apps.yaml
   git commit -m "chore: upgrade metrics-server to 3.14.0"
   git push forgejo main
   ```
### Adding a Brand New Infrastructure Application:

* **In Online Mode**: Append a new `Application` block under `items:` in [platform-apps.yaml](platform-apps.yaml) with the official public `repoURL: https://...`, then `git push forgejo main`. Argo CD deploys it instantly.
* **In Air-Gap Mode**: First download the `.tgz` package into `airgap/charts/`, import the container images, update the `airgap-helm-charts` Secret, and set `repoURL: http://airgap-helm-repo.argocd.svc:8080`.
* **Disconnecting Internet Post-Bootstrap**: For a detailed walkthrough on taking an online cluster completely offline without errors, see [airgap/README.md#3-what-if-you-bootstrap-with-internet-mode-but-later-disconnect-internet](../airgap/README.md#3-what-if-you-bootstrap-with-internet-mode-but-later-disconnect-internet).

---

## 🛡️ Self-Healing & Drift Detection in Action

Every platform application has `selfHeal: true` configured:

```yaml
syncPolicy:
  automated:
    prune: false
    selfHeal: true
```

### What happens if a resource is deleted or modified manually?
If an engineer or automated script deletes a resource directly:
```bash
kubectl delete deployment metrics-server -n kube-system
```
1. Argo CD's application controller detects a discrepancy between the cluster state (`NotFound`) and the desired state declared in Git.
2. Within seconds, Argo CD triggers an automated **Self-Heal**.
3. It re-applies the missing manifest, and the pods restart automatically. Manual tampering or accidental deletion is immediately corrected.

---

## Next Step

With infrastructure apps declared, proceed to:
➡️ [06-argocd](../06-argocd/README.md) to manage Argo CD settings, Gateway routing, and adoption scripts.
