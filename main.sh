#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# INTERNET DETECTION & INSTALLATION MODE SELECTION
# ==============================================================================
has_internet() {
  if curl -s --connect-timeout 2 --max-time 3 "https://1.1.1.1" >/dev/null 2>&1 || \
     curl -s --connect-timeout 2 --max-time 3 "https://www.google.com" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

echo "================================================================="
echo " 🚀 GitOps Platform Orchestrator (main.sh)"
echo "================================================================="

if [[ -z "${INSTALL_MODE:-}" ]]; then
  echo "🔍 Checking internet connectivity..."
  if has_internet; then
    echo "🌐 Internet connection is ACTIVE."
    echo ""
    echo "Select Installation Mode:"
    echo "  1) Internet Mode (Default - use online Helm repos & container registries)"
    echo "  2) Air-Gap Mode  (Offline - use local image tarballs & in-cluster Helm repo)"
    echo ""
    read -r -p "👉 Choose mode [1/2] (Default: 1): " choice
    if [[ "${choice:-1}" == "2" ]]; then
      export INSTALL_MODE="airgap"
      echo "📦 Proceeding in AIR-GAP (Offline) Mode."
    else
      export INSTALL_MODE="online"
      echo "🌐 Proceeding in INTERNET (Online) Mode."
    fi
  else
    echo "🔌 No Internet connection detected!"
    echo "⚡ Automatically proceeding in AIR-GAP (Offline) Mode without prompt."
    export INSTALL_MODE="airgap"
  fi
else
  echo "ℹ️ Using pre-set INSTALL_MODE='${INSTALL_MODE}'"
fi
echo "================================================================="
echo ""

./01-create-cluster/create-cluster.sh
./02-traefik-controller/install-traefik-gateway-controller.sh
./03-cert-manager/install-cert-manager.sh
./04-traefik-gateway/install-traefik-gatewayclass.sh
./05-infra-apps/02-metrics-server/install-metrics-server.sh
./05-infra-apps/03-harbor/install-harbor.sh
./06-argocd/01-install-argocd.sh
./06-argocd/02-adopt-infra-apps.sh
# ./07-apps/01-install-repo-creds-secret.sh
# ./07-apps/02-install-root-app.sh


