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
  echo "👉 Ensure Step 04 (04-traefik-gateway) has been executed so the Gateway is available."
else
  echo "✅ Gateway 'main-gateway' is available."
fi

# Step 1: Pre-configure Argo CD ConfigMaps (insecure mode & kustomize build options)
echo ""
echo "⚙️ Step 1: Pre-configuring Argo CD ConfigMaps in namespace '${ARGOCD_NAMESPACE}'..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n "${ARGOCD_NAMESPACE}" --server-side --force-conflicts -f "$(to_native_path "${ARGOCD_CONFIGMAPS_FILE}")"

# Step 2: Install Argo CD manifests
echo ""
echo "📦 Step 2: Installing Argo CD version v${ARGOCD_VERSION} in namespace '${ARGOCD_NAMESPACE}'..."

# Locate Argo CD manifest (offline local file or online URL)
OFFLINE_ARGOCD_MANIFEST=""
if [[ -f "${SCRIPT_DIR}/argocd-install-v${ARGOCD_VERSION}.yaml" ]]; then
  OFFLINE_ARGOCD_MANIFEST="${SCRIPT_DIR}/argocd-install-v${ARGOCD_VERSION}.yaml"
elif compgen -G "${SCRIPT_DIR}/argocd-install-*.yaml" >/dev/null; then
  candidates=( "${SCRIPT_DIR}"/argocd-install-*.yaml )
  OFFLINE_ARGOCD_MANIFEST="${candidates[0]}"
fi

if [[ -n "${OFFLINE_ARGOCD_MANIFEST}" && -f "${OFFLINE_ARGOCD_MANIFEST}" && "${INSTALL_MODE:-}" == "airgap" ]]; then
  echo "📦 Air-Gap environment: Applying local Argo CD manifest: ${OFFLINE_ARGOCD_MANIFEST}"
  ARGOCD_SOURCE="$(to_native_path "${OFFLINE_ARGOCD_MANIFEST}")"
else
  echo "🌐 Applying Argo CD manifest (release v${ARGOCD_VERSION})..."
  if [[ "${INSTALL_MODE:-}" == "online" ]]; then
    ARGOCD_SOURCE="https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGOCD_VERSION}/manifests/install.yaml"
  elif [[ -n "${OFFLINE_ARGOCD_MANIFEST}" && -f "${OFFLINE_ARGOCD_MANIFEST}" ]]; then
    ARGOCD_SOURCE="$(to_native_path "${OFFLINE_ARGOCD_MANIFEST}")"
  else
    ARGOCD_SOURCE="https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGOCD_VERSION}/manifests/install.yaml"
  fi
fi

kubectl apply -n "${ARGOCD_NAMESPACE}" \
  --server-side --force-conflicts \
  -f "${ARGOCD_SOURCE}"

# Re-apply configurations to ensure server.insecure: "true" persists after manifest apply
kubectl apply -n "${ARGOCD_NAMESPACE}" --server-side --force-conflicts -f "$(to_native_path "${ARGOCD_CONFIGMAPS_FILE}")"

# Ensure imagePullPolicy is IfNotPresent across all Argo CD workloads for offline reliability
for res in $(kubectl -n "${ARGOCD_NAMESPACE}" get deployments,statefulsets -o name 2>/dev/null || true); do
  kubectl -n "${ARGOCD_NAMESPACE}" patch "$res" --type=json -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "IfNotPresent"}]' 2>/dev/null || true
done
kubectl -n "${ARGOCD_NAMESPACE}" patch deployment argocd-dex-server --type=json -p='[{"op": "replace", "path": "/spec/template/spec/initContainers/0/imagePullPolicy", "value": "IfNotPresent"}]' 2>/dev/null || true

# Trigger rolling restart of argocd-server to guarantee it loads server.insecure: "true" from argocd-cmd-params-cm
kubectl rollout restart deployment "${ARGOCD_SERVER_DEPLOYMENT}" -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1 || true


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
