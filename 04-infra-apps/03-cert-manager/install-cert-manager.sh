#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/cert-manager-values.yaml"
NAMESPACE="cert-manager"
RELEASE_NAME="cert-manager"
CHART_VERSION="v1.21.2"
HELM_CHART="jetstack/cert-manager"
HELM_REPO_URL="https://charts.jetstack.io"
# ==============================================================================

echo "================================================================="
echo " 🔒 Installing cert-manager (${CHART_VERSION})"
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

echo ""
echo "================================================================="
echo " 🔍 cert-manager Verification"
echo "================================================================="
kubectl get deployment -n "${NAMESPACE}"
echo ""
echo "🔍 Checking cert-manager CustomResourceDefinitions:"
kubectl get crd -l app.kubernetes.io/name=cert-manager 2>/dev/null || kubectl get crd | grep cert-manager || true

echo ""
echo "================================================================="
echo "✅ cert-manager (${CHART_VERSION}) installation completed successfully!"
echo "================================================================="
