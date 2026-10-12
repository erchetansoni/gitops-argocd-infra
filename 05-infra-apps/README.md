# 05 - Infrastructure Applications (GitOps Platform Layer)

This directory defines the **platform-level infrastructure applications** managed declaratively by Argo CD using the GitOps pattern.

---

## Overview

In enterprise Kubernetes environments, cluster operations are strictly split into two layers:
1. **Platform / Infra Apps** (this directory): Shared cluster services like Ingress/Gateway controllers, metrics/monitoring, and cert managers managed by the DevOps/Platform team.
2. **Workload Apps** ([07-apps](../07-apps/README.md)): Tenant application microservices managed by development teams.

All platform components are declared in [infra-apps-root.yaml](infra-apps-root.yaml) and synchronized automatically by Argo CD.

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
├── infra-apps-root.yaml                # Root Application manifest containing infra apps
└── README.md                           # Documentation
```

---

## How Infra Apps Are Adopted by Argo CD

Instead of manual `helm install` commands drifting over time, the script [06-argocd/02-adopt-infra-apps.sh](../06-argocd/02-adopt-infra-apps.sh) adopts all running components:

1. Injects Helm release ownership annotations (`meta.helm.sh/release-name` and `app.kubernetes.io/managed-by: Helm`).
2. Applies [infra-apps-root.yaml](infra-apps-root.yaml) using Server-Side Apply (`ServerSideApply=true`).
3. Argo CD automatically assumes declarative control without terminating running pods.

---

## Verification

Check the Argo CD status of infra apps:

```bash
kubectl get applications -n argocd traefik-gateway-controller metrics-server cert-manager harbor
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

## Next Step

With infrastructure apps declared, proceed to:
➡️ [06-argocd](../06-argocd/README.md) to manage Argo CD settings, Gateway routing, and adoption scripts.
