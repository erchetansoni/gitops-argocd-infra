#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/metrics-server-values.yaml"
NAMESPACE="kube-system"
RELEASE_NAME="metrics-server"
CHART_VERSION="3.14.0"
HELM_CHART="metrics-server/metrics-server"
HELM_REPO_URL="https://kubernetes-sigs.github.io/metrics-server/"
# ==============================================================================

echo "================================================================="
echo " 🖥️  Installing Metrics Server"
echo "================================================================="

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm is not installed. Please install Helm to proceed."
  exit 1
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Metrics Server values file not found at: ${VALUES_FILE}"
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

# Locate Metrics Server Helm chart (offline local .tgz or online Helm repo)
OFFLINE_CHART=""
for candidate in "${SCRIPT_DIR}"/metrics-server-*.tgz "${SCRIPT_DIR}"/../../airgap/charts/metrics-server-*.tgz; do
  if [[ -f "$candidate" ]]; then
    OFFLINE_CHART="$candidate"
    break
  fi
done

VERSION_FLAG=()
if [[ -n "${OFFLINE_CHART}" ]]; then
  echo "📦 Offline environment: Using local Metrics Server Helm chart: ${OFFLINE_CHART}"
  CHART_SOURCE="$(to_native_path "${OFFLINE_CHART}")"
else
  echo "📦 Adding/Updating Metrics Server Helm repository..."
  helm repo add metrics-server "${HELM_REPO_URL}" --force-update
  helm repo update metrics-server
  CHART_SOURCE="${HELM_CHART}"
  VERSION_FLAG=(--version "${CHART_VERSION}")
fi

# Install or upgrade Metrics Server
echo "🚀 Installing Metrics Server in namespace '${NAMESPACE}'..."
VALUES_FILE_NATIVE="$(to_native_path "${VALUES_FILE}")"
helm upgrade --install "${RELEASE_NAME}" "${CHART_SOURCE}" \
  ${VERSION_FLAG[@]+"${VERSION_FLAG[@]}"} \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE_NATIVE}" \
  --wait \
  --timeout 5m

# Step 2: Wait for rollout of the deployment to complete
echo "⏳ Waiting for Metrics Server rollout to complete..."
if kubectl rollout status deployment/metrics-server -n "${NAMESPACE}" --timeout=180s; then
  echo "✅ Metrics Server deployment is successfully rolled out!"
else
  echo "❌ Timeout waiting for Metrics Server rollout."
  echo "🔍 Checking pod status and logs..."
  kubectl get pods -n "${NAMESPACE}" -l "app.kubernetes.io/name=metrics-server"
  kubectl logs -n "${NAMESPACE}" -l "app.kubernetes.io/name=metrics-server" --tail=50 || true
  exit 1
fi

# Step 3: Wait for APIService v1beta1.metrics.k8s.io to become Available
echo "⏳ Waiting for metrics.k8s.io APIService to be Available..."
if kubectl wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=120s; then
  echo "✅ APIService v1beta1.metrics.k8s.io is Available!"
else
  echo "⚠️ Warning: APIService v1beta1.metrics.k8s.io condition check timed out."
fi

echo ""
echo "================================================================="
echo " 🔍 Metrics Server Verification"
echo "================================================================="
kubectl get deployment metrics-server -n "${NAMESPACE}"
echo ""
kubectl get apiservice v1beta1.metrics.k8s.io

echo ""
echo "💡 Note: It may take 15-60 seconds for initial node/pod metrics to populate."
echo "   Test using:  kubectl top nodes"
echo "                kubectl top pods -A"
echo "================================================================="
echo "✅ Metrics Server installation completed successfully!"
