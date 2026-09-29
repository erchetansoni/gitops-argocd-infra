#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/traefik-values.yaml"
NAMESPACE="traefik"
RELEASE_NAME="traefik"
GATEWAY_API_VERSION="v1.6.2"

# Gateway API CRD Sources (Online URL & Offline Local File)
CRD_ONLINE_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
CRD_OFFLINE_FILE="${SCRIPT_DIR}/k8s-gateway-api-crd-${GATEWAY_API_VERSION}-install.yaml"
# ==============================================================================

echo "########## 🌐 Installing Traefik Gateway Controller ###########################"

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm is not installed. Please install Helm to proceed."
  exit 1
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Traefik values file not found at: ${VALUES_FILE}"
  exit 1
fi

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# Ensure Gateway API CRDs are installed before starting Traefik controller
apply_gateway_crds() {
  echo "🌐 Ensuring Gateway API CRDs are installed..."
  echo "Attempting to apply CRDs from online source:"
  echo "  ${CRD_ONLINE_URL}"

  if kubectl apply -f "${CRD_ONLINE_URL}" 2>/dev/null; then
    echo "✅ Gateway API CRDs applied successfully from online repository."
    return 0
  fi

  echo "⚠️ Online CRD install failed or offline environment detected."
  echo "🔍 Looking for local offline CRD file..."

  local target_offline=""
  if [[ -f "${CRD_OFFLINE_FILE}" ]]; then
    target_offline="${CRD_OFFLINE_FILE}"
  else
    # Fallback search if exact filename version differs
    for candidate in "${SCRIPT_DIR}"/k8s-gateway-api-crd-*-install.yaml; do
      if [[ -f "$candidate" ]]; then
        target_offline="$candidate"
        break
      fi
    done
  fi

  if [[ -n "${target_offline}" && -f "${target_offline}" ]]; then
    local offline_file_native
    offline_file_native="$(to_native_path "${target_offline}")"
    echo "📦 Applying Gateway API CRDs from local file: ${target_offline}..."
    kubectl apply -f "${offline_file_native}"
    echo "✅ Gateway API CRDs applied successfully from local file."
    return 0
  else
    echo "❌ No offline Gateway API CRD file found at: ${CRD_OFFLINE_FILE}"
    return 1
  fi
}

# Install Gateway API CRDs
apply_gateway_crds

# Locate Traefik Helm chart (offline local .tgz or online Helm repo)
OFFLINE_CHART=""
for candidate in "${SCRIPT_DIR}"/traefik-*.tgz "${SCRIPT_DIR}"/../airgap/charts/traefik-*.tgz; do
  if [[ -f "$candidate" ]]; then
    OFFLINE_CHART="$candidate"
    break
  fi
done

if [[ -n "${OFFLINE_CHART}" ]]; then
  echo "📦 Offline environment: Using local Traefik Helm chart: ${OFFLINE_CHART}"
  CHART_SOURCE="$(to_native_path "${OFFLINE_CHART}")"
else
  echo "📦 Adding/Updating Traefik Helm repository..."
  helm repo add traefik https://traefik.github.io/charts --force-update
  helm repo update traefik
  CHART_SOURCE="traefik/traefik"
fi

# Install or upgrade Traefik Gateway Controller
echo "🚀 Installing Traefik Gateway Controller in namespace '${NAMESPACE}'..."
VALUES_FILE_NATIVE="$(to_native_path "${VALUES_FILE}")"
helm upgrade --install "${RELEASE_NAME}" "${CHART_SOURCE}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE_NATIVE}" \
  --wait \
  --timeout 10m

# Wait for Traefik DaemonSet rollout
echo "⏳ Waiting for Traefik DaemonSet to be ready..."
kubectl rollout status daemonset/"${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=300s

# Verify Traefik pods status
echo "🔍 Verifying Traefik pods status..."
kubectl get pods -n "${NAMESPACE}" -o wide

echo "✅ Traefik Gateway Controller installed and verified successfully!"
