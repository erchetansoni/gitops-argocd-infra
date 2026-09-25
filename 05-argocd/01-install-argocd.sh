#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_VERSION="3.5.3"
ARGOCD_NAMESPACE="argocd"
ARGOCD_HOST="argocd.chetan.local"
ARGOCD_SERVER_DEPLOYMENT="argocd-server"
ARGOCD_INITIAL_ADMIN_SECRET="argocd-initial-admin-secret"
HTTPROUTE_FILE="${SCRIPT_DIR}/argocd-httproute.yaml"
ARGOCD_CONFIGMAPS_FILE="${SCRIPT_DIR}/argocd-configmaps.yaml"
# ==============================================================================

echo "================================================================="
echo " 🚀 Installing & Publishing Argo CD (https://${ARGOCD_HOST})"
echo "================================================================="

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# Step 0: Check Gateway API prerequisite
echo "🔍 Step 0: Checking Gateway API prerequisite ('main-gateway' in namespace default)..."
if ! kubectl get gateway main-gateway -n default >/dev/null 2>&1; then
  echo "⚠️ WARNING: 'main-gateway' not found in namespace 'default'."
  echo "👉 Ensure Step 03 (03-Traefik-Gateway-Class) has been executed so the Gateway is available."
else
  echo "✅ Gateway 'main-gateway' is available."
fi

# Step 1: Create namespace and install Argo CD manifests
echo ""
echo "📦 Step 1: Installing Argo CD version v${ARGOCD_VERSION} in namespace '${ARGOCD_NAMESPACE}'..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${ARGOCD_NAMESPACE}" \
  --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGOCD_VERSION}/manifests/install.yaml"

# Step 2: Configure Argo CD ConfigMaps (insecure mode & kustomize build options)
echo ""
echo "⚙️ Step 2: Applying Argo CD configurations from '${ARGOCD_CONFIGMAPS_FILE}'..."
kubectl apply -n "${ARGOCD_NAMESPACE}" --server-side --force-conflicts -f "$(to_native_path "${ARGOCD_CONFIGMAPS_FILE}")"


# Step 3: Wait for Argo CD server deployment rollout
echo ""
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-600s}"
echo "⏳ Step 3: Waiting for '${ARGOCD_SERVER_DEPLOYMENT}' to be ready (timeout: ${ROLLOUT_TIMEOUT})..."
# Ensure deployment is created
for i in {1..30}; do
  if kubectl get deployment -n "${ARGOCD_NAMESPACE}" "${ARGOCD_SERVER_DEPLOYMENT}" > /dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! kubectl rollout status deployment "${ARGOCD_SERVER_DEPLOYMENT}" -n "${ARGOCD_NAMESPACE}" --timeout="${ROLLOUT_TIMEOUT}"; then
  echo ""
  echo "⚠️ Rollout timed out or failed! Current Pod status in '${ARGOCD_NAMESPACE}':"
  kubectl get pods -n "${ARGOCD_NAMESPACE}"
  echo ""
  echo "🔍 Recent events:"
  kubectl get events -n "${ARGOCD_NAMESPACE}" --sort-by='.metadata.creationTimestamp' | tail -n 10
  exit 1
fi
echo "✅ Argo CD server deployment is ready!"

# Step 4: Apply HTTPRoute to expose Argo CD through main-gateway
echo ""
echo "🌐 Step 4: Applying Gateway API HTTPRoute (${HTTPROUTE_FILE})..."
if [[ ! -f "${HTTPROUTE_FILE}" ]]; then
  echo "❌ HTTPRoute manifest not found at: ${HTTPROUTE_FILE}"
  exit 1
fi

HTTPROUTE_NATIVE="$(to_native_path "${HTTPROUTE_FILE}")"
kubectl apply -n "${ARGOCD_NAMESPACE}" --server-side --force-conflicts -f "${HTTPROUTE_NATIVE}"

# Step 5: Verification & Auto-Validation
echo ""
echo "================================================================="
echo " 🔍 Verifying HTTPRoute Status"
echo "================================================================="
echo "⏳ Checking HTTPRoute 'argocd-server-route' Accepted status..."
ROUTE_ACCEPTED=$(kubectl get httproute argocd-server-route -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
if [[ "$ROUTE_ACCEPTED" == "True" ]]; then
  echo "✅ HTTPRoute 'argocd-server-route' is ACCEPTED=True by Traefik Gateway!"
else
  echo "ℹ️ Current HTTPRoute status: ${ROUTE_ACCEPTED}"
fi
kubectl get httproute -n "${ARGOCD_NAMESPACE}"

echo ""
echo "📌 Gateway Listener status on 'main-gateway':"
kubectl get gateway main-gateway -n default

# Step 6: Access Information
echo ""
echo "================================================================="
echo " 🎉 Argo CD Installation & Publishing Complete!"
echo "================================================================="
echo ""
echo "🌐 Access URL:"
echo "   https://${ARGOCD_HOST}"
echo ""
echo "📝 Hosts file requirement (if not already added):"
echo "   127.0.0.1 ${ARGOCD_HOST}"
echo ""
echo "👤 Username: admin"
echo "🔑 Password:"
if kubectl get secret "${ARGOCD_INITIAL_ADMIN_SECRET}" -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  ADMIN_PWD=$(kubectl get secret "${ARGOCD_INITIAL_ADMIN_SECRET}" -n "${ARGOCD_NAMESPACE}" -o jsonpath="{.data.password}" | base64 -d)
  echo "   ${ADMIN_PWD}"
else
  echo "   (Initial admin secret '${ARGOCD_INITIAL_ADMIN_SECRET}' not found. It may have already been rotated.)"
fi
echo "================================================================="
