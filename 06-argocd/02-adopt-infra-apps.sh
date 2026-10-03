#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../05-infra-apps/infra-apps-root.yaml" ]]; then
  INFRA_MANIFEST="${SCRIPT_DIR}/../05-infra-apps/infra-apps-root.yaml"
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

has_internet() {
  if curl -s --connect-timeout 2 --max-time 3 "https://1.1.1.1" >/dev/null 2>&1 || \
     curl -s --connect-timeout 2 --max-time 3 "https://www.google.com" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Determine mode if not already set by main.sh
if [[ -z "${INSTALL_MODE:-}" ]]; then
  if has_internet; then
    INSTALL_MODE="online"
  else
    INSTALL_MODE="airgap"
  fi
fi

echo "================================================================="
echo " 🌐 Adopting Infrastructure Apps into Argo CD (${INSTALL_MODE^^} Mode)"
echo "================================================================="

# Pre-checks
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "❌ Namespace '${NAMESPACE}' not found. Please install Argo CD first."
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

if [[ "${INSTALL_MODE}" == "airgap" ]]; then
  CHARTS_DIR="${SCRIPT_DIR}/../airgap/charts"
  AIRGAP_REPO_MANIFEST="${SCRIPT_DIR}/airgap-helm-repo.yaml"

  echo "📦 Air-Gap Mode: Setting up in-cluster Helm chart repository..."
  if [[ -d "${CHARTS_DIR}" ]] && compgen -G "${CHARTS_DIR}/*.tgz" >/dev/null; then
    if [[ ! -f "${CHARTS_DIR}/index.yaml" ]]; then
      if command -v helm &>/dev/null; then
        helm repo index "$(to_native_path "${CHARTS_DIR}")" 2>/dev/null || true
        sed -i -E '/^[[:space:]]*(created|generated):/d' "${CHARTS_DIR}/index.yaml" 2>/dev/null || true
      fi
    fi

    if [[ -f "${CHARTS_DIR}/index.yaml" ]]; then
      echo "🔐 Publishing air-gap charts into secret 'airgap-helm-charts' in '${NAMESPACE}'..."
      secret_args=()
      for f in "${CHARTS_DIR}"/*; do
        [[ -f "$f" ]] && secret_args+=( "--from-file=$(basename "$f")=$(to_native_path "$f")" )
      done
      kubectl create secret generic airgap-helm-charts "${secret_args[@]}" -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply --server-side --force-conflicts -f -

      if [[ -f "${AIRGAP_REPO_MANIFEST}" ]]; then
        echo "🚀 Starting in-cluster air-gap Helm chart server..."
        kubectl apply -f "$(to_native_path "${AIRGAP_REPO_MANIFEST}")" -n "${NAMESPACE}"
        kubectl rollout status deployment airgap-helm-repo -n "${NAMESPACE}" --timeout=60s >/dev/null 2>&1 || true
        echo "✅ In-cluster Helm repository is running at http://airgap-helm-repo.${NAMESPACE}.svc:8080"
      fi
    fi
  fi

  echo "📦 Air-Gap Mode: Dynamically configuring Argo CD Applications with internal repoURL (http://airgap-helm-repo.${NAMESPACE}.svc:8080)..."
  sed -E 's|repoURL:\s*https?://[^[:space:]]+|repoURL: http://airgap-helm-repo.'"${NAMESPACE}"'.svc:8080|g' "${INFRA_MANIFEST}" | \
    kubectl apply -f - -n "${NAMESPACE}"

else
  echo "🌐 Internet Mode: Applying Infra Applications using original online Helm repository URLs..."
  INFRA_MANIFEST_NATIVE="$(to_native_path "${INFRA_MANIFEST}")"
  kubectl apply -f "${INFRA_MANIFEST_NATIVE}" -n "${NAMESPACE}"
fi

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
echo "   - Harbor Container Registry (harbor)"
echo "================================================================="

