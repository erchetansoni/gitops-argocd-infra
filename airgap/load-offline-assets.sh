#!/usr/bin/env bash

# ==============================================================================
# Script: load-offline-assets.sh
# Purpose: Clean old/stale image archives and load offline container images into
#          K3s containerd runtime or local KinD cluster.
# ==============================================================================

set -euo pipefail

# Avoid path mangling in Git Bash on Windows
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR_FILE="${SCRIPT_DIR}/airgap-images.tar"
K3S_IMAGES_DIR="/var/lib/rancher/k3s/agent/images"

SKIP_CLEAN=false
CLEAN_SOURCE=false

print_usage() {
  echo "Usage: $(basename "$0") [OPTIONS]"
  echo ""
  echo "Cleans old/stale image archives and loads offline container images."
  echo ""
  echo "Options:"
  echo "  -s, --skip-clean      Skip the pre-load cleanup phase"
  echo "  -c, --clean-source    Delete the source tarball after successful import (saves node disk space)"
  echo "  -h, --help            Show this help message"
  echo ""
  echo "Examples:"
  echo "  sudo bash $(basename "$0")"
  echo "  sudo bash $(basename "$0") --clean-source"
  echo "  sudo bash $(basename "$0") --skip-clean"
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--skip-clean)
      SKIP_CLEAN=true
      shift
      ;;
    -c|--clean-source)
      CLEAN_SOURCE=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      print_usage
      exit 1
      ;;
  esac
done

echo "================================================================="
echo " 📥 Air-Gap Asset Loader & Cleaner"
echo "================================================================="

# ==============================================================================
# STEP 1: RESOLVE SOURCE IMAGE TARBALL
# ==============================================================================
if [[ ! -f "${TAR_FILE}" ]]; then
  if [[ -f "${SCRIPT_DIR}/airgap-images.tar.gz" ]]; then
    TAR_FILE="${SCRIPT_DIR}/airgap-images.tar.gz"
  elif [[ -f "${SCRIPT_DIR}/airgap-images.tar.zst" ]]; then
    TAR_FILE="${SCRIPT_DIR}/airgap-images.tar.zst"
  else
    echo "❌ Tarball not found in ${SCRIPT_DIR}."
    echo "   Looked for: airgap-images.tar, airgap-images.tar.gz, airgap-images.tar.zst"
    echo "👉 Run ./airgap/bundle-offline-assets.sh first on an internet-connected machine!"
    exit 1
  fi
fi

TAR_NAME="$(basename "${TAR_FILE}")"
echo "📦 Source image tarball: ${TAR_FILE}"

# ==============================================================================
# STEP 2: CLEANING PHASE (Before Loading)
# ==============================================================================
if [[ "${SKIP_CLEAN}" == "false" ]]; then
  echo ""
  echo "================================================================="
  echo " 🧹 Phase 1: Pre-Load Cleanup (Cleaning Stale Archives & Images)"
  echo "================================================================="

  # 1. Clean old/stale image archives in K3s agent images directory
  if [[ -d "${K3S_IMAGES_DIR}" ]]; then
    echo "🔍 Checking for stale image archives in ${K3S_IMAGES_DIR}..."
    stale_found=false
    while IFS= read -r -d $'\0' old_file; do
      # Avoid deleting the exact file if the source is already pointing inside K3S_IMAGES_DIR
      if [[ "$(realpath "${old_file}")" != "$(realpath "${TAR_FILE}")" ]]; then
        echo "   🗑️  Removing old archive: $(basename "${old_file}")"
        rm -f "${old_file}"
        stale_found=true
      fi
    done < <(find "${K3S_IMAGES_DIR}" -maxdepth 1 -type f \( -name "*.tar" -o -name "*.tgz" -o -name "*.tar.gz" -o -name "*.tar.zst" \) -print0 2>/dev/null || true)

    if [[ "${stale_found}" == "false" ]]; then
      echo "   ✨ No stale archives found in ${K3S_IMAGES_DIR}."
    else
      echo "   ✅ Stale image archives cleaned from ${K3S_IMAGES_DIR}."
    fi
  fi

  # 2. Prune dangling/unused container runtime images
  echo "🧹 Pruning dangling container images to reclaim node disk space..."
  if command -v k3s &>/dev/null; then
    k3s crictl rmi --prune >/dev/null 2>&1 || true
    echo "   ✅ K3s crictl dangling images pruned."
  elif command -v crictl &>/dev/null; then
    crictl rmi --prune >/dev/null 2>&1 || true
    echo "   ✅ crictl dangling images pruned."
  elif command -v docker &>/dev/null; then
    docker image prune -f >/dev/null 2>&1 || true
    echo "   ✅ Docker dangling images pruned."
  fi
else
  echo ""
  echo "⏩ Skipping pre-load cleanup (--skip-clean specified)."
fi

# ==============================================================================
# STEP 3: LOADING PHASE
# ==============================================================================
echo ""
echo "================================================================="
echo " 🚀 Phase 2: Loading Container Images"
echo "================================================================="

# Check environment: Local KinD vs K3s Node
if [[ $EUID -ne 0 ]]; then
  if command -v kind &>/dev/null; then
    KIND_CLUSTERS="$(kind get clusters 2>/dev/null || true)"
    if [[ -n "${KIND_CLUSTERS}" ]]; then
      TARGET_CLUSTER="${KIND_CLUSTER_NAME:-gitops-demo-cluster}"
      echo "💡 Local KinD environment detected. Loading into KinD cluster '${TARGET_CLUSTER}'..."
      kind load image-archive "${TAR_FILE}" --name "${TARGET_CLUSTER}"
      echo "✅ Images successfully loaded into KinD cluster '${TARGET_CLUSTER}'!"
      
      if [[ "${CLEAN_SOURCE}" == "true" ]]; then
        echo "🗑️  Removing source tarball: ${TAR_FILE}..."
        rm -f "${TAR_FILE}"
        echo "✅ Source tarball removed."
      fi
      exit 0
    fi
  fi

  echo "❌ This script must be run as root (or with sudo) on each K3s node."
  exit 1
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

# ==============================================================================
# STEP 4: VERIFICATION
# ==============================================================================
echo ""
echo "================================================================="
echo " 🔍 Phase 3: Verifying Imported Images (namespace: k8s.io)"
echo "================================================================="
if command -v k3s &>/dev/null; then
  k3s ctr --namespace k8s.io images list -q | grep -E "traefik|cert-manager|metrics-server|argocd|dex|redis" || true
fi

# ==============================================================================
# STEP 5: OPTIONAL SOURCE TARBALL CLEANUP
# ==============================================================================
if [[ "${CLEAN_SOURCE}" == "true" ]]; then
  echo ""
  echo "================================================================="
  echo " 🧹 Phase 4: Post-Load Source Cleanup (--clean-source specified)"
  echo "================================================================="
  echo "🗑️  Removing source tarball from workstation/repo: ${TAR_FILE}..."
  rm -f "${TAR_FILE}"
  echo "✅ Source tarball deleted to free node storage."
fi

echo ""
echo "================================================================="
echo "✅ Air-Gap image cleanup & loading complete!"
echo "👉 Repeat this on all 3 K3s nodes before deploying the platform."
echo "================================================================="
