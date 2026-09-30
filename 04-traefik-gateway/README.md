# 04 - Traefik GatewayClass, Gateway & TLS Certificates

This directory configures the **GatewayClass**, the root **Gateway** (`main-gateway`), and generates/manages local **TLS certificates** for multi-environment routing.

---

## Overview

Kubernetes Gateway API separates infrastructure definitions from application routing:
1. **GatewayClass**: Tells the cluster that the `traefik.io/gateway-controller` manages our Gateways.
2. **Gateway (`main-gateway`)**: Defines the physical entrypoint ports (`80` and `443`), listener hostnames, and TLS termination secrets in the `default` namespace.
3. **TLS Certificates**: Custom internal Root CA and a wildcard certificate with Subject Alternative Names (SANs) for all environments (`*.chetan.local`, `*.dev.chetan.local`, etc.).

---

## Gateway Listeners

In [install-gatewayclass_and_gateway.yaml](install-gatewayclass_and_gateway.yaml), `main-gateway` configures three active listeners:

| Listener Name | Protocol | Port | Hostname Filter | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `http` | HTTP | `80` | None (allows all) | Accepts HTTP traffic (auto-redirected to HTTPS by Traefik) |
| `https-chetan` | HTTPS | `443` | `*.chetan.local` | TLS termination for main environment apps (`app1.chetan.local`, `argocd.chetan.local`) |
| `https-dev` | HTTPS | `443` | `*.dev.chetan.local` | TLS termination for dev environment branch apps (`app1.dev.chetan.local`, etc.) |

Both HTTPS listeners terminate TLS using the `domain-certificate-tls-secret` in the `default` namespace and allow route attachment from all namespaces (`allowedRoutes.namespaces.from: All`).

---

## TLS Certificate Architecture & SANs

Under [RFC 6125](https://datatracker.ietf.org/doc/html/rfc6125), wildcard certificates do not cross domain dots (`*.chetan.local` does **not** match `app1.dev.chetan.local`). Therefore, the internal certificate generator issues a certificate with multi-environment SANs:

* `*.chetan.local` (main environment apps)
* `chetan.local` (apex domain)
* `*.dev.chetan.local` (development branch apps)
* `*.stage.chetan.local` & `*.staging.chetan.local` (staging environment apps)
* `*.test.chetan.local` (test environment apps)
* `*.prod.chetan.local` (production apps)
* `localhost`

The Root CA certificate is located at [cert/tls-generator/ca-store/rootCA.crt](cert/tls-generator/ca-store/rootCA.crt). Once installed into your host machine's Trusted Root Certification Authorities store, all subdomains display as fully secure (green lock 🔒) in Chrome and Edge.

---

## File Structure

```
04-traefik-gateway/
├── cert/
│   ├── tls-generator/                  # Internal PKI generator (CA + Server certs)
│   │   ├── ca-store/                   # Private Root CA key & cert (reusable)
│   │   ├── client/                     # Exported rootCA.crt for host trust installation
│   │   ├── output/                     # Generated wildcard server cert and key
│   │   └── server/                     # generate-certs.sh and generate-certs.ps1
│   ├── wildcard_.chetan.local.crt      # Active certificate used by Kubernetes Secret
│   └── wildcard_.chetan.local.key      # Active private key
├── install-gatewayclass_and_gateway.yaml # GatewayClass, Gateway & Certificate CR manifests
├── install-traefik-gatewayclass.sh      # Automated installer & validator script
└── README.md                           # Documentation
```

---

## Quickstart

Run the installer:

```bash
bash 04-traefik-gateway/install-traefik-gatewayclass.sh
```

### What the Script Does:
1. Validates Gateway API CRDs.
2. Checks if `cert-manager` is installed:
   * **If cert-manager is present**: Certificates are managed declaratively via `Certificate/domain-wildcard-cert` and `ClusterIssuer/local-ca-issuer`.
   * **If cert-manager is absent**: Automatically falls back to creating `Secret/domain-certificate-tls-secret` from local `./cert/` files.
3. Applies `GatewayClass`, `Gateway`, and `Certificate` manifests from [install-gatewayclass_and_gateway.yaml](install-gatewayclass_and_gateway.yaml).
4. Verifies `Certificate` readiness (`Ready=True`) and Gateway status (`Accepted=True` and `Programmed=True`).

---

## 💳 Using Commercial / Paid Certificates with Traefik Gateway

If deploying to a public production environment using a paid certificate from DigiCert, Sectigo, GoDaddy, etc.:

1. **Bundle your certificate with intermediate CA chain**:
   ```bash
   cat your_domain.crt ca-bundle.crt > fullchain.crt
   ```

2. **Create the TLS Secret in namespace `default`**:
   ```bash
   kubectl create secret tls domain-certificate-tls-secret \
     --cert=fullchain.crt \
     --key=your_domain.key \
     --namespace=default \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

3. **Update the listener hostname in [install-gatewayclass_and_gateway.yaml](install-gatewayclass_and_gateway.yaml)**:
   ```yaml
   listeners:
     - name: https-prod
       protocol: HTTPS
       port: 443
       hostname: "*.yourdomain.com"
       tls:
         mode: Terminate
         certificateRefs:
           - name: domain-certificate-tls-secret
   ```

4. **Public Trust**: Because commercial certificates chain up to built-in root CAs, all browsers and mobile devices will show a valid lock 🔒 with zero client configuration.

---

## Verification

Check Gateway status:

```bash
kubectl get gatewayclass
kubectl get gateway -n default
kubectl describe gateway main-gateway -n default
```

Verify TLS handshake locally:

```powershell
"" | & "C:\Program Files\Git\usr\bin\openssl.exe" s_client -connect 127.0.0.1:443 -servername app1.chetan.local
"" | & "C:\Program Files\Git\usr\bin\openssl.exe" s_client -connect 127.0.0.1:443 -servername app1.dev.chetan.local
```

---

## Next Step

With the Gateway accepting traffic, proceed to:
➡️ [05-infra-apps](../05-infra-apps/README.md) to manage infrastructure components via GitOps.

