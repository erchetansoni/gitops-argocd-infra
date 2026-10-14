#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${ARGOCD_NAMESPACE:-${NAMESPACE:-argocd}}"
SECRET_NAME="${SECRET_NAME:-forgejo-infra-repo-secret}"
FORGEJO_INTERNAL_URL="${FORGEJO_INTERNAL_URL:-http://forgejo-http.forgejo.svc.cluster.local:3000/forgejo_admin/gitops-argocd-infra.git}"
FORGEJO_USER="${FORGEJO_USER:-forgejo_admin}"
FORGEJO_PASS="${FORGEJO_PASS:-Forgejo12345}"

echo "================================================================="
echo " 🔐 Configure In-Cluster Forgejo Repository in Argo CD"
echo "================================================================="
echo "📌 Target Repository: ${FORGEJO_INTERNAL_URL}"
echo "📌 Forgejo User:      ${FORGEJO_USER}"
echo "📌 Secret Name:       ${SECRET_NAME}"
echo "📌 Argo CD Namespace: ${NAMESPACE}"
echo "================================================================="

# Pre-check
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Namespace '${NAMESPACE}' not found. Please install Argo CD first."
  exit 1
fi

echo "🔑 Creating / Updating Argo CD repository secret '${SECRET_NAME}'..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: ${FORGEJO_INTERNAL_URL}
  username: ${FORGEJO_USER}
  password: ${FORGEJO_PASS}
  insecure: "true"
EOF

echo "✅ Secret '${SECRET_NAME}' applied with label 'argocd.argoproj.io/secret-type: repository'."
echo ""
echo "🔍 Testing repository reachability from Argo CD repo-server..."
if kubectl get deployment argocd-repo-server -n "${NAMESPACE}" >/dev/null 2>&1; then
  if kubectl exec -n "${NAMESPACE}" deploy/argocd-repo-server -- git ls-remote "${FORGEJO_INTERNAL_URL}" >/dev/null 2>&1; then
    echo "🎉 SUCCESS: Argo CD repo-server can connect to Forgejo repository directly!"
  else
    echo "⚠️ Repo-server test connection returned non-zero. The repo might still be initializing."
  fi
fi

# Deploy Root App-of-Apps to track Forgejo main branch
APP_OF_APPS="${SCRIPT_DIR}/../05-infra-apps/app-of-apps.yaml"
if [[ -f "${APP_OF_APPS}" ]]; then
  echo ""
  echo "🚀 Deploying Root App-of-Apps (${APP_OF_APPS})..."
  kubectl apply -f "${APP_OF_APPS}"
  echo "✅ Root App-of-Apps 'infra-apps' is actively synchronizing from Forgejo main branch!"
fi

echo "================================================================="
