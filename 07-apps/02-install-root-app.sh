#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# LOAD CENTRALIZED ENVIRONMENT (.env)
# ==============================================================================
for env_loader in "${SCRIPT_DIR}/load-env.sh" "${SCRIPT_DIR}/../load-env.sh" "${SCRIPT_DIR}/../../load-env.sh"; do
  if [[ -f "${env_loader}" ]]; then
    # shellcheck disable=SC1090
    source "${env_loader}"
    break
  fi
done

# ==============================================================================
# CONFIGURATION VARIABLES (FROM .ENV OR DEFAULTS)
# ==============================================================================
APPLICATIONSET_FILE="${SCRIPT_DIR}/root-app/root-applicationset.yaml"
NAMESPACE="${ARGOCD_NAMESPACE:-${NAMESPACE:-argocd}}"
APPLICATIONSET_NAME="branch-environments"
REPO_SECRET_NAME="${REPO_SECRET_NAME:-repo-creds-secret}"
ARGOCD_HOST="${ARGOCD_HOST:-argocd.chetan.local}"
REPO_URL="${REPO_URL:-${GITHUB_REPO_URL:-https://github.com/erchetansoni/gitops-argocd-apps.git}}"
# ==============================================================================

echo "================================================================="
echo " 🚀 Step 02: Installing Root ApplicationSet (${APPLICATIONSET_NAME})"
echo "================================================================="
echo "📌 Target Repository: ${REPO_URL}"
echo "📌 Namespace:         ${NAMESPACE}"
echo "📌 Argo CD Host:      ${ARGOCD_HOST}"
echo "================================================================="

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# Step 0: Check Prerequisites
echo "🔍 Step 0: Checking Argo CD prerequisites..."

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Namespace '${NAMESPACE}' not found. Please install Argo CD (Step 04) first."
  exit 1
fi

if ! kubectl get deployment argocd-server -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Argo CD server deployment not found in namespace '${NAMESPACE}'."
  exit 1
fi

echo "✅ Argo CD is running in namespace '${NAMESPACE}'."

# Check if Private Repository Secret exists
echo "🔍 Checking repository credentials secret..."
if ! kubectl get secret "${REPO_SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1 && \
   ! kubectl get secret -n "${NAMESPACE}" -l argocd.argoproj.io/secret-type=repository >/dev/null 2>&1; then
  echo "⚠️ WARNING: No repository credentials secret found in namespace '${NAMESPACE}'."
  echo "👉 If your Git repository is private, please run:"
  echo "   ./07-apps/01-install-repo-creds-secret.sh"
else
  echo "✅ Repository credentials secret detected in '${NAMESPACE}'."
fi

# Step 1: Apply Root ApplicationSet
echo ""
echo "📦 Step 1: Applying ApplicationSet manifest (${APPLICATIONSET_FILE})..."

if [[ ! -f "${APPLICATIONSET_FILE}" ]]; then
  echo "❌ ApplicationSet file not found at: ${APPLICATIONSET_FILE}"
  exit 1
fi

# If a custom repo URL is specified via .env, substitute it dynamically
DEFAULT_REPO_URL="https://github.com/erchetansoni/gitops-argocd-apps.git"
if [[ -n "${REPO_URL}" && "${REPO_URL}" != "${DEFAULT_REPO_URL}" ]]; then
  echo "🔄 Updating repoURL in ApplicationSet manifest to '${REPO_URL}'..."
  sed "s|${DEFAULT_REPO_URL}|${REPO_URL}|g" "${APPLICATIONSET_FILE}" | kubectl apply -f -
else
  APPLICATIONSET_NATIVE="$(to_native_path "${APPLICATIONSET_FILE}")"
  kubectl apply -f "${APPLICATIONSET_NATIVE}"
fi

# Step 2: Verify ApplicationSet
echo ""
echo "================================================================="
echo " 🔍 Verifying ApplicationSet and Generated Applications"
echo "================================================================="

echo "📌 1. ApplicationSet Status:"
kubectl get applicationset "${APPLICATIONSET_NAME}" -n "${NAMESPACE}"

echo ""
echo "⏳ Waiting 5 seconds for ApplicationSet controller to discover and generate applications..."
sleep 5

echo ""
echo "📌 2. Generated Applications in namespace '${NAMESPACE}':"
if kubectl get applications -n "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl get applications -n "${NAMESPACE}"
else
  echo "ℹ️ No applications generated yet. Check ApplicationSet controller logs if needed."
fi

# Step 3: Access Information
echo ""
echo "================================================================="
echo " 🎉 Root ApplicationSet Applied Successfully!"
echo "================================================================="
echo ""
echo "🌐 View Applications in Argo CD Dashboard:"
echo "   https://${ARGOCD_HOST}"
echo ""
echo "💡 Useful inspection commands:"
echo "   kubectl get applicationset -n ${NAMESPACE}"
echo "   kubectl get applications -n ${NAMESPACE}"
echo "   kubectl describe applicationset ${APPLICATIONSET_NAME} -n ${NAMESPACE}"
echo "================================================================="
