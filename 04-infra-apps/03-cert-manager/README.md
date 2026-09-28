# cert-manager (v1.21.2)

Automates the management and issuance of TLS/SSL certificates from various issuing sources, including Let's Encrypt, HashiCorp Vault, Venafi, and in-cluster CA or self-signed issuers.

---

## Overview

* **Argo CD Application Name**: `cert-manager`
* **Helm Chart**: `jetstack/cert-manager`
* **Chart Version**: `v1.21.2`
* **Namespace**: `cert-manager`
* **Repository**: `https://charts.jetstack.io`

---

## Configuration Highlights

* **CRDs**: Enabled (`crds.enabled: true`) directly via Helm so all CustomResourceDefinitions (`certificates`, `issuers`, `clusterissuers`, `certificaterequests`, etc.) are created and managed declaratively.
* **Gateway API Integration**: Configured with `--enable-gateway-api` to enable cert-manager to monitor Gateway API resources (`Gateway`, `HTTPRoute`) for TLS certificate provisioning.
* **Server-Side Apply**: Configured in Argo CD sync options (`ServerSideApply=true`) to handle large CRD definitions seamlessly without metadata length issues.

---

## Files

* `cert-manager-values.yaml`: Helm values for configuring cert-manager, webhook, and cainjector components.
* `cert-manager-application.yaml`: Individual Argo CD Application manifest.
* `install-cert-manager.sh`: Shell script for manual / pre-Argo CD installation.

---

## Standalone Installation

To install cert-manager manually using Helm:

```bash
bash 04-infra-apps/03-cert-manager/install-cert-manager.sh
```

## GitOps Adoption

cert-manager is declared under [04-infra-apps/infra-apps-root.yaml](../infra-apps-root.yaml) and automatically adopted into Argo CD when running:

```bash
bash 05-argocd/02-adopt-infra-apps.sh
```
