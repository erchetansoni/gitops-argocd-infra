#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# FUNCTION: LOAD .ENV FILES SAFELY (HANDLES WINDOWS CRLF & QUOTES)
# ==============================================================================
load_env() {
  local script_dir="$1"
  local loaded=0

  parse_env_file() {
    local file="$1"
    [[ ! -f "${file}" ]] && return
    echo "📄 Sourcing environment variables from: ${file}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
      # Strip carriage return and leading/trailing whitespace
      line="$(echo "${line}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      # Skip comments and empty lines
      [[ -z "${line}" || "${line}" =~ ^# ]] && continue
      # Match KEY=VALUE
      if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        local key="${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        # Strip matching surrounding double or single quotes
        if [[ "${val}" =~ ^\"(.*)\"$ ]] || [[ "${val}" =~ ^\'(.*)\'$ ]]; then
          val="${BASH_REMATCH[1]}"
        fi
        export "${key}=${val}"
      fi
    done < "${file}"
    loaded=1
  }

  # Load root .env first (if present)
  parse_env_file "${script_dir}/../.env"
  # Load local 05-apps/.env (overrides root .env if present)
  parse_env_file "${script_dir}/.env"

  if [[ ${loaded} -eq 0 ]]; then
    echo "ℹ️  No .env file found (checked root .env and ${script_dir}/.env)."
    echo "   Using environment variables or script defaults."
  fi
}

load_env "${SCRIPT_DIR}"

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
  echo "   ./06-apps/01-install-repo-creds-secret.sh"
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
