#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../04-infra-apps/infra-apps-root.yaml" ]]; then
  INFRA_MANIFEST="${SCRIPT_DIR}/../04-infra-apps/infra-apps-root.yaml"
else
  INFRA_MANIFEST="${SCRIPT_DIR}/infra-apps-root.yaml"
fi
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

echo "================================================================="
echo " 🌐 Adopting Infrastructure Apps into Argo CD"
echo "================================================================="

# Pre-checks
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Namespace '${NAMESPACE}' not found. Please install Argo CD (Step 04) first."
  exit 1
fi

if [[ ! -f "${INFRA_MANIFEST}" ]]; then
  echo "❌ Manifest not found at: ${INFRA_MANIFEST}"
  exit 1
fi

# Pre-adoption cleanup for legacy / duplicate resources
if kubectl get deployment metrics-server -n kube-system -o jsonpath='{.spec.selector.matchLabels.k8s-app}' 2>/dev/null | grep -q "metrics-server"; then
  echo "🧹 Removing legacy metrics-server deployment with immutable selector to enable Helm adoption..."
  kubectl delete deployment metrics-server -n kube-system --wait=false
fi

if kubectl get daemonset traefik-gateway-controller -n traefik >/dev/null 2>&1; then
  echo "🧹 Removing orphaned duplicate traefik-gateway-controller daemonset..."
  kubectl delete daemonset traefik-gateway-controller -n traefik --ignore-not-found
fi

echo "📦 Applying declarative Infra Applications into Argo CD (${NAMESPACE})..."
INFRA_MANIFEST_NATIVE="$(to_native_path "${INFRA_MANIFEST}")"
kubectl apply -f "${INFRA_MANIFEST_NATIVE}" -n "${NAMESPACE}"

echo ""
echo "⏳ Checking Argo CD Application statuses..."
sleep 3
kubectl get applications -n "${NAMESPACE}" -l argocd.argoproj.io/instance 2>/dev/null || kubectl get applications -n "${NAMESPACE}"

echo ""
echo "================================================================="
echo "✅ Infrastructure apps registered with Argo CD!"
echo "   - Traefik Gateway Controller (traefik-gateway-controller)"
echo "   - Metrics Server (metrics-server)"
echo "   - cert-manager (cert-manager)"
echo "================================================================="

