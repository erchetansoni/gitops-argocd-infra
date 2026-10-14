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
REPO_URL="${REPO_URL:-${GITHUB_REPO_URL:-https://github.com/erchetansoni/gitops-argocd-apps.git}}"
REPO_SECRET_NAME="${REPO_SECRET_NAME:-repo-creds-secret}"
NAMESPACE="${ARGOCD_NAMESPACE:-${NAMESPACE:-argocd}}"
GITHUB_USER="${GITHUB_USERNAME:-${GITHUB_USER:-erchetansoni}}"

echo "================================================================="
echo " 🔐 Step 01: Configure Private GitHub Repo Secret in Argo CD"
echo "================================================================="
echo "📌 Target Repository: ${REPO_URL}"
echo "📌 GitHub User:       ${GITHUB_USER}"
echo "📌 Secret Name:       ${REPO_SECRET_NAME}"
echo "📌 Namespace:         ${NAMESPACE}"
echo "================================================================="

# Check if namespace exists
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Namespace '${NAMESPACE}' does not exist. Please install Argo CD first (Step 04)."
  exit 1
fi

# Determine GitHub Token (Priority: CLI argument > .env / Environment > Interactive prompt)
GITHUB_TOKEN="${1:-${GITHUB_TOKEN:-}}"

if [[ -n "${GITHUB_TOKEN}" ]]; then
  echo "🔑 Using GitHub Token from .env / environment variable."
else
  echo "👉 GitHub Personal Access Token (PAT) not found in .env or arguments."
  read -s -p "Enter GitHub Personal Access Token (PAT): " GITHUB_TOKEN
  echo ""
fi

if [[ -z "${GITHUB_TOKEN}" ]]; then
  echo "❌ GitHub Token cannot be empty."
  exit 1
fi

echo ""
echo "🔑 Creating / Updating Secret '${REPO_SECRET_NAME}' in namespace '${NAMESPACE}'..."

kubectl create secret generic "${REPO_SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --type=Opaque \
  --from-literal=type=git \
  --from-literal=url="${REPO_URL}" \
  --from-literal=username="${GITHUB_USER}" \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Label the secret so Argo CD recognizes it as a repository credential
kubectl label secret "${REPO_SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo ""
echo "✅ Secret '${REPO_SECRET_NAME}' configured with label 'argocd.argoproj.io/secret-type: repository'!"

echo ""
echo "📌 Configured Repository Secret Details:"
kubectl get secret "${REPO_SECRET_NAME}" -n "${NAMESPACE}" --show-labels

echo ""
echo "================================================================="
echo "🎉 Argo CD can now authenticate with: ${REPO_URL}"
echo "👉 Next step: Run ./07-apps/02-install-root-app.sh"
echo "================================================================="
