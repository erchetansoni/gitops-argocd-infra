#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/forgejo-runner-values.yaml"
NAMESPACE="forgejo-runner"
RELEASE_NAME="forgejo-runner"
CHART_VERSION="0.7.6"
HELM_CHART="oci://codeberg.org/wrenix/helm-charts/forgejo-runner"
FORGEJO_NAMESPACE="forgejo"
FORGEJO_INSTANCE_URL="http://forgejo-http.${FORGEJO_NAMESPACE}.svc.cluster.local:3000"
RUNNER_SECRET_NAME="forgejo-runner-secret"
# ==============================================================================

echo "================================================================="
echo " 🏃 Installing Forgejo Actions Runner (${RELEASE_NAME})"
echo "================================================================="

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo "❌ Helm is not installed. Please install Helm to proceed."
  exit 1
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "❌ Forgejo Runner values file not found at: ${VALUES_FILE}"
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

# Ensure destination namespace exists
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Step 1: Resolve or Generate Runner Registration Token
RUNNER_TOKEN="${FORGEJO_RUNNER_TOKEN:-}"

if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "🔍 Checking for existing registration secret '${RUNNER_SECRET_NAME}' in namespace '${NAMESPACE}'..."
  EXISTING_TOKEN="$(kubectl get secret "${RUNNER_SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.CONFIG_TOKEN}' 2>/dev/null || true)"
  if [[ -n "${EXISTING_TOKEN}" ]]; then
    RUNNER_TOKEN="$(echo "${EXISTING_TOKEN}" | base64 -d)"
    echo "🔑 Found existing registration token in secret."
  fi
fi

if [[ -z "${RUNNER_TOKEN}" ]]; then
  echo "⏳ Checking if Forgejo instance is running in namespace '${FORGEJO_NAMESPACE}'..."
  if ! kubectl get deployment forgejo -n "${FORGEJO_NAMESPACE}" >/dev/null 2>&1; then
    echo "❌ Forgejo deployment not found in namespace '${FORGEJO_NAMESPACE}'. Please install Forgejo first."
    exit 1
  fi

  echo "🔑 Generating registration token from Forgejo server..."
  # Wait briefly if pod is restarting
  kubectl wait --for=condition=available --timeout=120s deployment/forgejo -n "${FORGEJO_NAMESPACE}" >/dev/null 2>&1 || true

  # Execute inside Forgejo container to generate a runner token
  RUNNER_TOKEN="$(kubectl exec -n "${FORGEJO_NAMESPACE}" deployment/forgejo -c forgejo -- forgejo actions generate-runner-token 2>/dev/null | tr -d '\r\n' || true)"

  if [[ -z "${RUNNER_TOKEN}" ]]; then
    echo "⚠️ Failed to auto-generate token via 'forgejo actions generate-runner-token'."
    echo "👉 Please generate a runner token from Forgejo Web UI (Site Admin -> Actions -> Runners -> Create new runner)"
    read -r -p "Enter Runner Registration Token: " RUNNER_TOKEN
  else
    echo "✅ Successfully generated runner registration token."
  fi
fi

# Step 2: Store / Update Runner Registration Secret
echo "🔐 Configuring secret '${RUNNER_SECRET_NAME}' in namespace '${NAMESPACE}'..."
kubectl create secret generic "${RUNNER_SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  --from-literal=CONFIG_NAME="k8s-runner" \
  --from-literal=CONFIG_INSTANCE="${FORGEJO_INSTANCE_URL}" \
  --from-literal=CONFIG_TOKEN="${RUNNER_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Locate Forgejo Runner Helm chart (offline local .tgz or online OCI Helm repo)
OFFLINE_CHART=""
for candidate in "${SCRIPT_DIR}"/forgejo-runner-*.tgz "${SCRIPT_DIR}"/../../airgap/charts/forgejo-runner-*.tgz; do
  if [[ -f "$candidate" ]]; then
    OFFLINE_CHART="$candidate"
    break
  fi
done

VERSION_FLAG=()
if [[ -n "${OFFLINE_CHART}" ]]; then
  echo "📦 Offline environment: Using local Forgejo Runner Helm chart: ${OFFLINE_CHART}"
  CHART_SOURCE="$(to_native_path "${OFFLINE_CHART}")"
else
  echo "🌐 Online environment: Using OCI Helm chart: ${HELM_CHART}"
  CHART_SOURCE="${HELM_CHART}"
  VERSION_FLAG=(--version "${CHART_VERSION}")
fi

# Step 4: Install or upgrade Forgejo Runner
echo "🚀 Installing Forgejo Runner in namespace '${NAMESPACE}'..."
VALUES_FILE_NATIVE="$(to_native_path "${VALUES_FILE}")"
helm upgrade --install "${RELEASE_NAME}" "${CHART_SOURCE}" \
  ${VERSION_FLAG[@]+"${VERSION_FLAG[@]}"} \
  --namespace "${NAMESPACE}" \
  --values "${VALUES_FILE_NATIVE}" \
  --wait \
  --timeout 10m

# Step 5: Wait for rollout of Forgejo Runner deployment
echo "⏳ Waiting for Forgejo Runner rollout to complete..."
kubectl rollout status deployment/"${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=300s || true

echo ""
echo "================================================================="
echo " 🔍 Forgejo Runner Verification"
echo "================================================================="
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "================================================================="
echo "🎉 Forgejo Actions Runner successfully deployed!"
echo "   Namespace:    ${NAMESPACE}"
echo "   Target Forgejo: ${FORGEJO_INSTANCE_URL}"
echo "   Labels:       ubuntu-latest, ubuntu-22.04, docker"
echo "================================================================="
