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
    echo "   Using environment variables or default prompts."
  fi
}

load_env "${SCRIPT_DIR}"

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
