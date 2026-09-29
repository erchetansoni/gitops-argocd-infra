#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/cert-manager-values.yaml"
CLUSTER_ISSUER_FILE="${SCRIPT_DIR}/cluster-issuer.yaml"
NAMESPACE="cert-manager"
RELEASE_NAME="cert-manager"
CHART_VERSION="v1.21.2"
HELM_CHART="jetstack/cert-manager"
HELM_REPO_URL="https://charts.jetstack.io"

# Root CA paths
ROOT_CA_DIR="${SCRIPT_DIR}/../04-traefik-gateway/cert/tls-generator/ca-store"
ROOT_CA_CRT="${ROOT_CA_DIR}/rootCA.crt"
ROOT_CA_KEY="${ROOT_CA_DIR}/rootCA.key"
TLS_GEN_SCRIPT="${SCRIPT_DIR}/../04-traefik-gateway/cert/tls-generator/server/generate-certs.sh"
# ==============================================================================

echo "================================================================="
echo " 🔒 Installing cert-manager (${CHART_VERSION}) & ClusterIssuer"
echo "================================================================="

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm is not installed. Please install Helm to proceed."
  exit 1
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ cert-manager values file not found at: ${VALUES_FILE}"
  exit 1
fi

# Helper function to convert POSIX paths to native Windows paths when needed
to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# Add and update cert-manager Helm repository
echo "📦 Adding/Updating cert-manager Helm repository..."
helm repo add jetstack "${HELM_REPO_URL}" --force-update
helm repo update jetstack

# Install or upgrade cert-manager
echo "🚀 Installing cert-manager in namespace '${NAMESPACE}'..."
VALUES_FILE_NATIVE="$(to_native_path "${VALUES_FILE}")"
helm upgrade --install "${RELEASE_NAME}" "${HELM_CHART}" \
  --version "${CHART_VERSION}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE_NATIVE}" \
  --wait \
  --timeout 5m

# Step 2: Wait for rollout of deployments to complete
echo "⏳ Waiting for cert-manager deployments rollout to complete..."
for deploy in cert-manager cert-manager-webhook cert-manager-cainjector; do
  echo "   Waiting for deployment/${deploy}..."
  if kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout=180s; then
    echo "   ✅ ${deploy} deployment is successfully rolled out!"
  else
    echo "   ❌ Timeout waiting for ${deploy} rollout."
    kubectl get pods -n "${NAMESPACE}"
    exit 1
  fi
done

# Step 3: Configure Root CA Secret for cert-manager
echo ""
echo "🔑 Step 3: Setting up Root CA secret for ClusterIssuer..."
if [[ ! -f "${ROOT_CA_CRT}" || ! -f "${ROOT_CA_KEY}" ]]; then
  echo "⚠️ Root CA not found in ${ROOT_CA_DIR}. Generating CA..."
  if [[ -f "${TLS_GEN_SCRIPT}" ]]; then
    chmod +x "${TLS_GEN_SCRIPT}"
    bash "${TLS_GEN_SCRIPT}"
  else
    echo "❌ Certificate generation script not found at ${TLS_GEN_SCRIPT}"
    exit 1
  fi
fi

if [[ -f "${ROOT_CA_CRT}" && -f "${ROOT_CA_KEY}" ]]; then
  echo "🔐 Injecting Root CA into Kubernetes Secret 'local-root-ca-secret' in '${NAMESPACE}'..."
  CA_CRT_NATIVE="$(to_native_path "${ROOT_CA_CRT}")"
  CA_KEY_NATIVE="$(to_native_path "${ROOT_CA_KEY}")"
  kubectl create secret tls local-root-ca-secret \
    --cert="${CA_CRT_NATIVE}" \
    --key="${CA_KEY_NATIVE}" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "✅ Root CA secret 'local-root-ca-secret' created/updated."
else
  echo "❌ Failed to locate Root CA certificate and key files."
  exit 1
fi

# Step 4: Apply ClusterIssuer manifest
if [[ -f "${CLUSTER_ISSUER_FILE}" ]]; then
  echo ""
  echo "📜 Step 4: Applying ClusterIssuer (${CLUSTER_ISSUER_FILE})..."
  CLUSTER_ISSUER_NATIVE="$(to_native_path "${CLUSTER_ISSUER_FILE}")"
  kubectl apply -f "${CLUSTER_ISSUER_NATIVE}"

  echo "⏳ Waiting for ClusterIssuer 'local-ca-issuer' to become Ready..."
  if kubectl wait --for=condition=Ready clusterissuer/local-ca-issuer --timeout=60s > /dev/null 2>&1; then
    echo "✅ ClusterIssuer 'local-ca-issuer' is READY=True"
  else
    echo "⚠️ Checking ClusterIssuer status:"
    kubectl get clusterissuer local-ca-issuer -o wide || true
  fi
fi

echo ""
echo "================================================================="
echo " 🔍 cert-manager Verification"
echo "================================================================="
kubectl get deployment -n "${NAMESPACE}"
echo ""
kubectl get clusterissuer
echo ""
echo "================================================================="
echo "✅ cert-manager (${CHART_VERSION}) & ClusterIssuer setup complete!"
echo "================================================================="
