# 01 - Create Kind Cluster

This directory provisions the local single-node Kubernetes cluster using [Kind (Kubernetes in Docker)](https://kind.sigs.k8s.io/) configured for ingress routing.

---

## Overview

The cluster is created with host port mappings on ports `80` and `443` so that the ingress controller / Gateway API proxy ([Traefik](file:///c:/Projects/My_Projects/GitOps-demo/02-Traefik-Gateway-Controller)) can directly accept HTTP and HTTPS traffic from your host machine (`localhost` or custom `.local` domains).

### Key Features
* **Cluster Name**: `gitops-demo-cluster`
* **Kubernetes Version**: `v1.37.0` (via `kindest/node:v1.37.0`)
* **Port Bindings**:
  * `hostPort: 80` -> `containerPort: 80` (HTTP)
  * `hostPort: 443` -> `containerPort: 443` (HTTPS)
* **Pre-flight readiness**: Waits until all `kube-system` pods are in `Ready` state before completing.

---

## File Structure

```
01-create-cluster/
├── create-cluster.sh        # Bash script to automate cluster creation
├── kind-cluster-config.yaml # Kind cluster manifest with port forward rules
└── README.md                # Documentation
```

---

## Prerequisites

* [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker daemon running
* [Kind CLI](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) installed
* [kubectl](https://kubernetes.io/docs/tasks/tools/) installed

---

## Quickstart

Run the creation script from the project root or from this directory:

```bash
bash 01-create-cluster/create-cluster.sh
```

### Manual Creation

Alternatively, you can apply the Kind configuration directly:

```bash
kind create cluster --config 01-create-cluster/kind-cluster-config.yaml
```

Verify that the cluster node is ready:

```bash
kubectl get nodes
```

---

## Next Step

Once the cluster is up and running, proceed to:
➡️ [02-Traefik-Gateway-Controller](file:///c:/Projects/My_Projects/GitOps-demo/02-Traefik-Gateway-Controller/README.md) to install the Kubernetes Gateway API CRDs and Traefik controller.
