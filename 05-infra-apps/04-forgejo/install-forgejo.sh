#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/forgejo-values.yaml"
NAMESPACE="forgejo"
RELEASE_NAME="forgejo"
CHART_VERSION="17.2.0"
HELM_CHART="oci://code.forgejo.org/forgejo-helm/forgejo"
FORGEJO_HOST="git.chetan.local"
# ==============================================================================

echo "================================================================="
echo " 🦊 Installing Forgejo Git Service (${FORGEJO_HOST})"
echo "================================================================="

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm is not installed. Please install Helm to proceed."
  exit 1
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Forgejo values file not found at: ${VALUES_FILE}"
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

# Locate Forgejo Helm chart (offline local .tgz or online OCI Helm repo)
OFFLINE_CHART=""
for candidate in "${SCRIPT_DIR}"/forgejo-*.tgz "${SCRIPT_DIR}"/../../airgap/charts/forgejo-*.tgz; do
  if [[ -f "$candidate" ]]; then
    OFFLINE_CHART="$candidate"
    break
  fi
done

VERSION_FLAG=()
if [[ -n "${OFFLINE_CHART}" ]]; then
  echo "📦 Offline environment: Using local Forgejo Helm chart: ${OFFLINE_CHART}"
  CHART_SOURCE="$(to_native_path "${OFFLINE_CHART}")"
else
  echo "🌐 Online environment: Using OCI Helm chart: ${HELM_CHART}"
  CHART_SOURCE="${HELM_CHART}"
  VERSION_FLAG=(--version "${CHART_VERSION}")
fi

# Install or upgrade Forgejo
echo "🚀 Installing Forgejo in namespace '${NAMESPACE}'..."
VALUES_FILE_NATIVE="$(to_native_path "${VALUES_FILE}")"
helm upgrade --install "${RELEASE_NAME}" "${CHART_SOURCE}" \
  ${VERSION_FLAG[@]+"${VERSION_FLAG[@]}"} \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE_NATIVE}" \
  --wait \
  --timeout 10m

# Step 2: Wait for rollout of Forgejo deployment to complete
echo "⏳ Waiting for Forgejo deployment rollout to complete..."
kubectl rollout status deployment/"${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=300s || true

echo ""
echo "================================================================="
echo " 🔍 Forgejo Verification & Route Information"
echo "================================================================="
kubectl get httproute -n "${NAMESPACE}" 2>/dev/null || true
echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "================================================================="
echo "🎉 Forgejo successfully deployed!"
echo "   URL:      https://${FORGEJO_HOST}"
echo "   Username: forgejo_admin"
echo "   Password: Forgejo12345"
echo ""
echo "💡 To test Git clone over HTTPS:"
echo "   git clone https://forgejo_admin:Forgejo12345@${FORGEJO_HOST}/forgejo_admin/test-repo.git"
echo "================================================================="
