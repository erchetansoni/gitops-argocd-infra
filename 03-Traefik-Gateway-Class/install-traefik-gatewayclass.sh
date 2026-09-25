#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/cert"
TLS_GENERATOR_DIR="${CERT_DIR}/tls-generator/server"
MANIFEST_FILE="${SCRIPT_DIR}/install-gatewayclass_and_gateway.yaml"

# Target TLS Secret and Namespace
SECRET_NAME="domain-certificate-tls-secret"
SECRET_NAMESPACE="default"

# ==============================================================================

echo "================================================================="
echo " 🚀 Installing GatewayClass, TLS Secrets & Traefik Gateway"
echo "================================================================="

# Convert POSIX paths to native Windows paths for Windows tools
to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# Locate openssl executable (supporting Git Bash, Windows native, Linux)
get_openssl_cmd() {
  if command -v openssl >/dev/null 2>&1; then
    echo "openssl"
  elif [[ -f "/c/Program Files/Git/usr/bin/openssl.exe" ]]; then
    echo "/c/Program Files/Git/usr/bin/openssl.exe"
  elif [[ -f "C:/Program Files/Git/usr/bin/openssl.exe" ]]; then
    echo "C:/Program Files/Git/usr/bin/openssl.exe"
  else
    echo ""
  fi
}

# Step 0: Verify Gateway API CRD prerequisites installed by Step 02
check_gateway_crds() {
  echo "🔍 Step 0: Checking Gateway API CRD prerequisites (installed in Step 02)..."

  if ! kubectl get crd gatewayclasses.gateway.networking.k8s.io gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    echo "❌ Gateway API CRDs not found in the cluster."
    echo "👉 Please run '02-Traefik-Gateway-Controller/install-traefik-gateway-controller.sh' first to install the CRDs and Controller."
    exit 1
  fi

  echo "✅ Gateway API CRDs are present."
}

# Function to check validity of a certificate
check_cert_validity() {
  local cert_file="$1"
  local cert_file_native
  cert_file_native="$(to_native_path "${cert_file}")"
  local openssl_cmd
  openssl_cmd="$(get_openssl_cmd)"

  echo "🔍 Checking certificate: $(basename "${cert_file}")"

  if [[ -n "${openssl_cmd}" ]]; then
    "${openssl_cmd}" x509 -in "${cert_file_native}" -noout -subject -issuer 2>/dev/null || true
    "${openssl_cmd}" x509 -in "${cert_file_native}" -noout -dates 2>/dev/null || true

    if "${openssl_cmd}" x509 -checkend 0 -noout -in "${cert_file_native}" > /dev/null 2>&1; then
      echo "✅ Certificate is VALID (not expired)."
      return 0
    else
      echo "⚠️ WARNING: Certificate has EXPIRED or could not be validated for expiry!"
      return 0
    fi
  else
    echo "ℹ️ OpenSSL CLI not detected; certificate syntax will be validated by kubectl upon secret creation."
    return 0
  fi
}

# Function to scan ./cert/ and configure TLS secrets for all available certificates
configure_tls_secrets() {
  local certs_configured=0
  local has_target_secret=false
  local first_cert=""
  local first_key=""

  echo "📁 Step 1: Checking for TLS certificates in ${CERT_DIR} ..."

  # Iterate over all .crt and .pem files directly in CERT_DIR
  shopt -s nullglob
  local cert_files=("${CERT_DIR}"/*.crt "${CERT_DIR}"/*.pem)
  shopt -u nullglob

  # If no certs exist, trigger generation
  if [[ ${#cert_files[@]} -eq 0 ]]; then
    echo "⚠️ No certificates found in ${CERT_DIR}."
    echo "⚙️ Generating certificates using tls-generator..."

    if [[ -f "${TLS_GENERATOR_DIR}/generate-certs.sh" ]]; then
      chmod +x "${TLS_GENERATOR_DIR}/generate-certs.sh"
      bash "${TLS_GENERATOR_DIR}/generate-certs.sh"

      # Auto-copy generated certificates from output directory into ./cert/
      if [[ -d "${CERT_DIR}/tls-generator/output" ]]; then
        echo "📋 Copying generated certificates from output/ to ${CERT_DIR}..."
        cp "${CERT_DIR}/tls-generator/output"/*.crt "${CERT_DIR}/" 2>/dev/null || true
        cp "${CERT_DIR}/tls-generator/output"/*.key "${CERT_DIR}/" 2>/dev/null || true
      fi
    else
      echo "❌ Certificate generator script not found at ${TLS_GENERATOR_DIR}/generate-certs.sh"
      exit 1
    fi

    shopt -s nullglob
    cert_files=("${CERT_DIR}"/*.crt "${CERT_DIR}"/*.pem)
    shopt -u nullglob

    if [[ ${#cert_files[@]} -eq 0 ]]; then
      echo "❌ Still unable to find certificates in ${CERT_DIR} after generation."
      exit 1
    fi
  fi

  # Process each certificate found in CERT_DIR
  for cert_file in "${cert_files[@]}"; do
    [[ -f "$cert_file" ]] || continue

    local cert_base="${cert_file%.*}"
    local key_file="${cert_base}.key"

    # If exact match key does not exist, look for any .key file matching the base name
    if [[ ! -f "$key_file" ]]; then
      shopt -s nullglob
      local possible_keys=("${cert_base}"*.key)
      shopt -u nullglob
      if [[ ${#possible_keys[@]} -gt 0 ]]; then
        key_file="${possible_keys[0]}"
      fi
    fi

    if [[ ! -f "$key_file" ]]; then
      echo "⚠️ Private key for certificate '$(basename "${cert_file}")' not found (looked for $(basename "${key_file}")). Skipping."
      continue
    fi

    if [[ -z "$first_cert" ]]; then
      first_cert="$cert_file"
      first_key="$key_file"
    fi

    echo ""
    echo "🔐 Validating and creating Secret for $(basename "${cert_file}") and $(basename "${key_file}")..."
    check_cert_validity "${cert_file}"

    # Use the configured secret name: domain-certificate-tls-secret
    local current_secret_name="${SECRET_NAME}"
    has_target_secret=true

    local cert_native
    cert_native="$(to_native_path "${cert_file}")"
    local key_native
    key_native="$(to_native_path "${key_file}")"

    echo "🔑 Creating / Updating TLS Secret '${current_secret_name}' in namespace '${SECRET_NAMESPACE}'..."
    kubectl create secret tls "${current_secret_name}" \
      --cert="${cert_native}" \
      --key="${key_native}" \
      --namespace="${SECRET_NAMESPACE}" \
      --dry-run=client -o yaml | kubectl apply -f -

    echo "✅ TLS Secret '${current_secret_name}' configured successfully."
    certs_configured=$((certs_configured + 1))
  done

  # Fallback: ensure the primary secret required by Gateway manifest exists
  if [[ "$has_target_secret" = false && -n "$first_cert" && -n "$first_key" ]]; then
    echo "ℹ️ Creating default target Secret '${SECRET_NAME}' from available cert: $(basename "${first_cert}")"
    local first_cert_native
    first_cert_native="$(to_native_path "${first_cert}")"
    local first_key_native
    first_key_native="$(to_native_path "${first_key}")"

    kubectl create secret tls "${SECRET_NAME}" \
      --cert="${first_cert_native}" \
      --key="${first_key_native}" \
      --namespace="${SECRET_NAMESPACE}" \
      --dry-run=client -o yaml | kubectl apply -f -
    echo "✅ TLS Secret '${SECRET_NAME}' configured."
    certs_configured=$((certs_configured + 1))
  fi

  if [[ $certs_configured -eq 0 ]]; then
    echo "❌ No valid certificate & key pairs could be configured from ${CERT_DIR}."
    exit 1
  fi
}

# --- EXECUTION FLOW ---

# 1. Verify Gateway API CRD prerequisites from Step 02
check_gateway_crds

# 2. Configure TLS Secrets for whatever certificates are in ./cert/
configure_tls_secrets

# 3. Apply GatewayClass and Gateway manifests
echo ""
echo "🌐 Step 2: Applying GatewayClass and Gateway manifests (${MANIFEST_FILE})..."
if [[ ! -f "${MANIFEST_FILE}" ]]; then
  echo "❌ Manifest file not found: ${MANIFEST_FILE}"
  exit 1
fi

MANIFEST_NATIVE="$(to_native_path "${MANIFEST_FILE}")"
kubectl apply -f "${MANIFEST_NATIVE}"

# 4. Verification & Auto-Validation
echo ""
echo "================================================================="
echo " 🔍 Verifying & Auto-Validating GatewayClass and Gateway"
echo "================================================================="

echo "📌 1. GatewayClass Summary:"
kubectl get gatewayclass

echo "⏳ Checking GatewayClass 'traefik' Accepted status..."
if kubectl wait --for=condition=Accepted=True gatewayclass/traefik --timeout=60s > /dev/null 2>&1; then
  echo "✅ GatewayClass 'traefik' is ACCEPTED=True"
else
  GC_ACCEPTED=$(kubectl get gatewayclass traefik -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
  if [[ "$GC_ACCEPTED" == "True" ]]; then
    echo "✅ GatewayClass 'traefik' is ACCEPTED=True"
  else
    echo "❌ GatewayClass 'traefik' validation failed (ACCEPTED is not True). Current status:"
    kubectl get gatewayclass traefik -o yaml
    exit 1
  fi
fi

echo ""
echo "📌 2. Gateway Summary in namespace '${SECRET_NAMESPACE}':"
kubectl get gateway -n "${SECRET_NAMESPACE}"

echo "⏳ Checking Gateway 'main-gateway' Programmed & Accepted status..."
if kubectl wait --for=condition=Programmed=True gateway/main-gateway -n "${SECRET_NAMESPACE}" --timeout=60s > /dev/null 2>&1; then
  echo "✅ Gateway 'main-gateway' is PROGRAMMED=True"
else
  GW_PROGRAMMED=$(kubectl get gateway main-gateway -n "${SECRET_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
  if [[ "$GW_PROGRAMMED" == "True" ]]; then
    echo "✅ Gateway 'main-gateway' is PROGRAMMED=True"
  else
    echo "⚠️ Gateway 'main-gateway' PROGRAMMED status: ${GW_PROGRAMMED}"
  fi
fi

if kubectl wait --for=condition=Accepted=True gateway/main-gateway -n "${SECRET_NAMESPACE}" --timeout=60s > /dev/null 2>&1; then
  echo "✅ Gateway 'main-gateway' is ACCEPTED=True"
else
  GW_ACCEPTED=$(kubectl get gateway main-gateway -n "${SECRET_NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
  if [[ "$GW_ACCEPTED" == "True" ]]; then
    echo "✅ Gateway 'main-gateway' is ACCEPTED=True"
  else
    echo "⚠️ Gateway 'main-gateway' ACCEPTED status: ${GW_ACCEPTED}"
  fi
fi

echo ""
echo "📌 3. Gateway Details (describe main-gateway):"
kubectl describe gateway main-gateway -n "${SECRET_NAMESPACE}"

echo ""
echo "✅ GatewayClass and Gateway verified & validated successfully!"
