#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/harbor-values.yaml"
NAMESPACE="harbor"
RELEASE_NAME="harbor"
CHART_VERSION="1.19.2"
HELM_CHART="harbor/harbor"
HELM_REPO_URL="https://helm.goharbor.io"
HARBOR_HOST="cr.chetan.local"
# ==============================================================================

echo "================================================================="
echo " 🐳 Installing Harbor Container Registry (${HARBOR_HOST})"
echo "================================================================="

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm is not installed. Please install Helm to proceed."
  exit 1
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Harbor values file not found at: ${VALUES_FILE}"
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

# Locate Harbor Helm chart (offline local .tgz or online Helm repo)
OFFLINE_CHART=""
for candidate in "${SCRIPT_DIR}"/harbor-*.tgz "${SCRIPT_DIR}"/../../airgap/charts/harbor-*.tgz; do
  if [[ -f "$candidate" ]]; then
    OFFLINE_CHART="$candidate"
    break
  fi
done

VERSION_FLAG=()
if [[ -n "${OFFLINE_CHART}" ]]; then
  echo "📦 Offline environment: Using local Harbor Helm chart: ${OFFLINE_CHART}"
  CHART_SOURCE="$(to_native_path "${OFFLINE_CHART}")"
else
  echo "📦 Adding/Updating Harbor Helm repository..."
  helm repo add harbor "${HELM_REPO_URL}" --force-update
  helm repo update harbor
  CHART_SOURCE="${HELM_CHART}"
  VERSION_FLAG=(--version "${CHART_VERSION}")
fi

# Install or upgrade Harbor
echo "🚀 Installing Harbor in namespace '${NAMESPACE}'..."
VALUES_FILE_NATIVE="$(to_native_path "${VALUES_FILE}")"
helm upgrade --install "${RELEASE_NAME}" "${CHART_SOURCE}" \
  ${VERSION_FLAG[@]+"${VERSION_FLAG[@]}"} \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE_NATIVE}" \
  --wait \
  --timeout 10m

# Step 2: Wait for rollout of the deployments to complete
echo "⏳ Waiting for Harbor deployments rollout to complete..."
for d in core portal jobservice registry; do
  if kubectl get deployment "${RELEASE_NAME}-${d}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "   Checking deployment: ${RELEASE_NAME}-${d}..."
    kubectl rollout status deployment/"${RELEASE_NAME}-${d}" -n "${NAMESPACE}" --timeout=180s || true
  fi
done

echo ""
echo "================================================================="
echo " 🔍 Harbor Verification & Route Information"
echo "================================================================="
kubectl get httproute -n "${NAMESPACE}" 2>/dev/null || true
echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "================================================================="
echo "🎉 Harbor successfully deployed!"
echo "   URL:      https://${HARBOR_HOST}"
echo "   Username: admin"
echo "   Password: Harbor12345"
echo ""
echo "💡 To test container registry login:"
echo "   docker login ${HARBOR_HOST} -u admin -p Harbor12345"
echo "================================================================="
