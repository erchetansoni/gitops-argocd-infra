# Custom TLS Certificate Generator & Client Trust Manager

A standalone PKI solution for generating private Root Certificate Authorities (CA) and long-lived Wildcard TLS certificates (5–10 years) for local Kubernetes Gateway API routing without relying on external ACME/Let's Encrypt or public DNS validation.

---

## Directory Structure

```text
03-Traefik-Gateway-Class/cert/tls-generator/
├── README.md
├── server/
│   ├── generate-certs.sh       # Bash script (Git Bash / Linux)
│   └── generate-certs.ps1      # PowerShell script (Windows Server)
├── client/
│   └── rootCA.crt              # Exported Root CA certificate to install on host PCs
├── ca-store/                   # Stores private Root CA key & cert (reused across runs)
│   ├── rootCA.key
│   └── rootCA.crt
└── output/                     # Generated server certificate & private key
    ├── wildcard_.chetan.local.crt
    └── wildcard_.chetan.local.key
```

---

## 1. Generating Certificates

### On Git Bash / Linux
```bash
cd 03-Traefik-Gateway-Class/cert/tls-generator/server
chmod +x generate-certs.sh
./generate-certs.sh
```

### On Windows (PowerShell)
```powershell
cd 03-Traefik-Gateway-Class\cert\tls-generator\server
.\generate-certs.ps1
```

### What Happens:
1. **Root CA Reuse or Creation**:
   * If `ca-store/rootCA.key` and `ca-store/rootCA.crt` already exist, the script **reuses the existing Root CA** so client workstations do NOT have to reinstall certificates.
   * If missing, a new private Root CA valid for **10 Years (3650 days)** is generated.
2. **Wildcard Server Certificate Generation**:
   * Generates a 2048-bit server private key.
   * Generates a CSR and signs it with the Root CA for **5 Years (1825 days)**.
   * Injects Subject Alternative Names (SANs) for all environments:
     ```bash
     SAN_DOMAINS=(
         "*.chetan.local"
         "chetan.local"
         "*.dev.chetan.local"
         "*.stage.chetan.local"
         "*.staging.chetan.local"
         "*.test.chetan.local"
         "*.prod.chetan.local"
         "localhost"
     )
     ```
3. **Outputs**:
   * Writes `wildcard_.chetan.local.crt` and `wildcard_.chetan.local.key` to `output/`.
   * Automatically copies `rootCA.crt` to `client/rootCA.crt`.

---

## 2. Installing the Root CA on Windows Host (Browser Trust)

To enable the green lock 🔒 and eliminate `NET::ERR_CERT_COMMON_NAME_INVALID` or "Not secure" warnings in Chrome and Edge:

1. Double-click `client/rootCA.crt` (or press `Win + R` -> `certmgr.msc`).
2. Click **Install Certificate...**
3. Select **Local Machine** (requires Admin) -> click **Next**.
4. Choose **Place all certificates in the following store** -> click **Browse...**
5. Select **Trusted Root Certification Authorities** -> click **OK** -> **Next** -> **Finish**.
6. Restart Google Chrome / Microsoft Edge.

---

## 3. Updating the Kubernetes TLS Secret

After generating new certificates, copy them to `03-Traefik-Gateway-Class/cert/` and update the secret:

```bash
cp 03-Traefik-Gateway-Class/cert/tls-generator/output/* 03-Traefik-Gateway-Class/cert/

kubectl create secret tls domain-certificate-tls-secret \
  --cert=03-Traefik-Gateway-Class/cert/wildcard_.chetan.local.crt \
  --key=03-Traefik-Gateway-Class/cert/wildcard_.chetan.local.key \
  --namespace=default \
  --dry-run=client -o yaml | kubectl apply -f -
```
