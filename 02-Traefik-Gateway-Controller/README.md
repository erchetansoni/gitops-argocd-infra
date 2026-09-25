# 02 - Traefik Gateway Controller

This directory installs the **Kubernetes Gateway API CRDs** and deploys **Traefik v3** as the Gateway API controller.

---

## Overview

Kubernetes Gateway API is the modern successor to Ingress. Rather than using legacy Ingress objects, Traefik is deployed with `providers.kubernetesGateway.enabled: true` and operates as a cluster-wide DaemonSet binding directly to ports `80` and `443`.

### Key Capabilities
* **Standard Gateway API CRDs**: Version `v1.6.2` installed via online release or local offline fallback manifest (`k8s-gateway-api-crd-v1.6.2-install.yaml`).
* **Global HTTP to HTTPS Redirection**: Automatically redirects all incoming port `80` traffic to port `443` (`https://`) with `301 Moved Permanently` at the entrypoint level:
  ```yaml
  ports:
    web:
      http:
        redirections:
          entryPoint:
            to: websecure
            scheme: https
            permanent: true
  ```
* **HostPort DaemonSet Strategy**: Configured with `maxUnavailable: 1` and `maxSurge: 0` so rolling updates succeed cleanly on single-node Kind clusters without hostPort collisions.
* **Security & Observability**: Runs as non-root user (`65532`), drops all Linux capabilities except `NET_BIND_SERVICE`, enables access logging, and exposes Prometheus metrics.

---

## File Structure

```
02-Traefik-Gateway-Controller/
├── install-traefik-gateway-controller.sh    # Installs Gateway CRDs and Traefik via Helm
├── k8s-gateway-api-crd-v1.6.2-install.yaml   # Offline Gateway API CRDs
├── traefik-values.yaml                     # Helm values for Traefik controller DaemonSet
└── README.md                               # Documentation
```

---

## Prerequisites

* Active Kubernetes cluster running (from [01-create-cluster](file:///c:/Projects/My_Projects/GitOps-demo/01-create-cluster/README.md))
* [Helm](https://helm.sh/docs/intro/install/) CLI installed
* `kubectl` configured with cluster context

---

## Quickstart

Run the installer:

```bash
bash 02-Traefik-Gateway-Controller/install-traefik-gateway-controller.sh
```

### Verification

Check Gateway API CRDs:
```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Check the running Traefik DaemonSet:
```bash
kubectl get daemonset -n traefik
kubectl get pods -n traefik
```

---

## Next Step

Once Traefik is running, configure the GatewayClass, Gateway listeners, and TLS certificates in:
➡️ [03-Traefik-Gateway-Class](file:///c:/Projects/My_Projects/GitOps-demo/03-Traefik-Gateway-Class/README.md)
