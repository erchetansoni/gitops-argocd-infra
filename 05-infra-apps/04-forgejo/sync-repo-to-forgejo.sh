#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for env_loader in "${SCRIPT_DIR}/load-env.sh" "${SCRIPT_DIR}/../load-env.sh" "${SCRIPT_DIR}/../../load-env.sh"; do
  if [[ -f "${env_loader}" ]]; then
    # shellcheck disable=SC1090
    source "${env_loader}"
    break
  fi
done

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
FORGEJO_HOST="${FORGEJO_HOST:-git.${MAIN_DOMAIN:-chetan.local}}"
FORGEJO_USER="${FORGEJO_USER:-forgejo_admin}"
FORGEJO_PASS="${FORGEJO_PASS:-Forgejo12345}"
REPO_NAME="${FORGEJO_REPO_NAME:-gitops-argocd-infra}"
REMOTE_NAME="${GIT_REMOTE_NAME:-forgejo}"

echo "================================================================="
echo " 🦊 Sync Local Git Repository to In-Cluster Forgejo"
echo "================================================================="
echo "📌 Forgejo URL:   https://${FORGEJO_HOST}"
echo "📌 Forgejo User:  ${FORGEJO_USER}"
echo "📌 Repo Name:     ${REPO_NAME}"
echo "📌 Git Remote:    ${REMOTE_NAME}"
echo "================================================================="

# Step 1: Wait for Forgejo API to be healthy
echo "⏳ Checking Forgejo service health..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -k -s --connect-timeout 2 "https://${FORGEJO_HOST}/api/v1/version" >/dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [[ ${RETRY_COUNT} -ge ${MAX_RETRIES} ]]; then
    echo "❌ Forgejo API did not become healthy in time at https://${FORGEJO_HOST}"
    exit 1
  fi
  echo "   Waiting for Forgejo API at https://${FORGEJO_HOST} (${RETRY_COUNT}/${MAX_RETRIES})..."
  sleep 3
done
echo "✅ Forgejo is healthy!"

# Step 2: Ensure the repository exists in Forgejo
echo ""
echo "🔍 Checking if repository '${REPO_NAME}' exists in Forgejo..."
HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${FORGEJO_USER}:${FORGEJO_PASS}" "https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_USER}/${REPO_NAME}" || true)

if [[ "${HTTP_STATUS}" == "200" ]]; then
  echo "✅ Repository '${FORGEJO_USER}/${REPO_NAME}' already exists in Forgejo."
else
  echo "📦 Creating repository '${FORGEJO_USER}/${REPO_NAME}' via Forgejo API..."
  CREATE_PAYLOAD=$(cat <<EOF
{
  "name": "${REPO_NAME}",
  "description": "GitOps Infrastructure & Platform Repository",
  "private": false,
  "auto_init": false,
  "default_branch": "main"
}
EOF
)
  CREATE_RES=$(curl -k -s -w "\n%{http_code}" -u "${FORGEJO_USER}:${FORGEJO_PASS}" \
    -H "Content-Type: application/json" \
    -X POST "https://${FORGEJO_HOST}/api/v1/user/repos" \
    -d "${CREATE_PAYLOAD}")

  RES_CODE=$(echo "${CREATE_RES}" | tail -n1)
  if [[ "${RES_CODE}" =~ ^20[0-1]$ ]]; then
    echo "✅ Repository '${FORGEJO_USER}/${REPO_NAME}' created successfully!"
  else
    echo "⚠️ Create repo returned HTTP ${RES_CODE}. Response: ${CREATE_RES}"
  fi
fi

# Step 3: Configure Git Remote without touching existing remotes (like origin / GitHub)
cd "${REPO_ROOT}"

FORGEJO_REMOTE_URL="https://${FORGEJO_USER}:${FORGEJO_PASS}@${FORGEJO_HOST}/${FORGEJO_USER}/${REPO_NAME}.git"

# Disable SSL verification specifically for local domain git.chetan.local
git config "http.https://${FORGEJO_HOST}/.sslVerify" false

if git remote | grep -wq "${REMOTE_NAME}"; then
  echo "🔄 Updating existing remote '${REMOTE_NAME}' URL..."
  git remote set-url "${REMOTE_NAME}" "${FORGEJO_REMOTE_URL}"
else
  echo "➕ Adding Git remote '${REMOTE_NAME}'..."
  git remote add "${REMOTE_NAME}" "${FORGEJO_REMOTE_URL}"
fi

echo "📋 Current configured Git remotes:"
git remote -v

# Step 4: Push active branch and main to Forgejo
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo ""
echo "🚀 Pushing active branch '${CURRENT_BRANCH}' to Forgejo remote '${REMOTE_NAME}'..."
git push "${REMOTE_NAME}" "${CURRENT_BRANCH}:${CURRENT_BRANCH}" --force
if [[ "${CURRENT_BRANCH}" != "main" ]]; then
  echo "🚀 Also syncing '${CURRENT_BRANCH}' to Forgejo 'main' branch..."
  git push "${REMOTE_NAME}" "${CURRENT_BRANCH}:main" --force
fi

echo ""
echo "================================================================="
echo "🎉 Repository successfully pushed to Forgejo!"
echo "   Forgejo Web URL: https://${FORGEJO_HOST}/${FORGEJO_USER}/${REPO_NAME}"
echo "   Clone URL:       https://${FORGEJO_HOST}/${FORGEJO_USER}/${REPO_NAME}.git"
echo "   In-Cluster URL:  http://forgejo-http.forgejo.svc.cluster.local:3000/${FORGEJO_USER}/${REPO_NAME}.git"
echo "================================================================="
