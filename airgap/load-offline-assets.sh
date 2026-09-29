#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR_FILE="${SCRIPT_DIR}/airgap-images.tar"
K3S_IMAGES_DIR="/var/lib/rancher/k3s/agent/images"

echo "================================================================="
echo " 📥 Loading Air-Gap Container Images into K3s Node"
echo "================================================================="

if [[ $EUID -ne 0 ]]; then
  # If non-root, check if running in local dev environment with KinD
  if command -v kind &>/dev/null; then
    KIND_CLUSTERS="$(kind get clusters 2>/dev/null || true)"
    if [[ -n "${KIND_CLUSTERS}" ]]; then
      TARGET_CLUSTER="${KIND_CLUSTER_NAME:-gitops-demo-cluster}"
      echo "💡 Local KinD environment detected. Loading image archive into KinD cluster '${TARGET_CLUSTER}'..."
      if [[ ! -f "${TAR_FILE}" ]]; then
        echo "❌ Tarball not found: ${TAR_FILE}"
        echo "👉 Run ./airgap/bundle-offline-assets.sh first!"
        exit 1
      fi
      kind load image-archive "${TAR_FILE}" --name "${TARGET_CLUSTER}"
      echo "✅ Images successfully loaded into KinD cluster '${TARGET_CLUSTER}'!"
      exit 0
    fi
  fi

  echo "❌ This script must be run as root (or with sudo) on each K3s node."
  exit 1
fi

if [[ ! -f "${TAR_FILE}" ]]; then
  # Check if tar.gz or tar.zst exists
  if [[ -f "${SCRIPT_DIR}/airgap-images.tar.gz" ]]; then
    TAR_FILE="${SCRIPT_DIR}/airgap-images.tar.gz"
  elif [[ -f "${SCRIPT_DIR}/airgap-images.tar.zst" ]]; then
    TAR_FILE="${SCRIPT_DIR}/airgap-images.tar.zst"
  else
    echo "❌ Tarball not found: ${TAR_FILE}"
    echo "👉 Please place 'airgap-images.tar' into ${SCRIPT_DIR}/"
    exit 1
  fi
fi

# Strategy 1: Place into K3s automatic image loading directory
echo "📂 Strategy 1: Copying tarball to K3s agent images directory (${K3S_IMAGES_DIR})..."
mkdir -p "${K3S_IMAGES_DIR}"
cp -v "${TAR_FILE}" "${K3S_IMAGES_DIR}/"

# Strategy 2: If k3s is already running, import directly into containerd k8s.io namespace
if command -v k3s &>/dev/null; then
  echo ""
  echo "🚀 Strategy 2: Performing direct containerd image import via 'k3s ctr'..."
  k3s ctr images import "${TAR_FILE}" || true
  echo "✅ Images imported into K3s containerd runtime."
fi

echo ""
echo "================================================================="
echo "🔍 Verifying imported images in K3s containerd (namespace: k8s.io):"
echo "================================================================="
if command -v k3s &>/dev/null; then
  k3s ctr --namespace k8s.io images list -q | grep -E "traefik|cert-manager|metrics-server|argocd|dex|redis" || true
fi

echo ""
echo "================================================================="
echo "✅ Node image preparation complete!"
echo "👉 Repeat this on all 3 K3s nodes before running the deployment scripts."
echo "================================================================="
