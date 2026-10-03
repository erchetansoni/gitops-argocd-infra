#!/usr/bin/env bash

# ==============================================================================
# Script: load-images-to-kind.sh
# Purpose: Pre-load all platform container images into local KinD cluster
#          to eliminate startup delay, bandwidth usage, and CrashLoopBackOff.
# ==============================================================================

set -euo pipefail

# Avoid path mangling in Git Bash on Windows
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGES_FILE="${REPO_ROOT}/airgap/images.yaml"
CONFIG_FILE="${SCRIPT_DIR}/kind-cluster-config.yaml"

# Default cluster name
DEFAULT_CLUSTER="gitops-demo-cluster"
if [[ -f "${CONFIG_FILE}" ]]; then
  cfg_name="$(grep -E '^[[:space:]]*name:' "${CONFIG_FILE}" | head -n 1 | awk '{print $2}' || true)"
  [[ -n "$cfg_name" ]] && DEFAULT_CLUSTER="$cfg_name"
fi

CLUSTER_NAME="${DEFAULT_CLUSTER}"
AUTO_PULL=false
ARCHIVE_PATH=""
LIST_ONLY=false

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

print_usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Pre-loads all platform container images into the local KinD Kubernetes cluster.

Options:
  -n, --name <cluster>    KinD cluster name (default: ${DEFAULT_CLUSTER})
  -p, --pull              Automatically pull missing images from remote registries
  -a, --archive [path]    Load from an image archive (.tar) instead of local Docker
  -l, --list              List all platform images and their local availability
  -h, --help              Show this help message

Examples:
  ./load-images-to-kind.sh
  ./load-images-to-kind.sh --pull
  ./load-images-to-kind.sh --archive ../airgap/airgap-images.tar
  ./load-images-to-kind.sh --name my-custom-cluster
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -p|--pull)
      AUTO_PULL=true
      shift
      ;;
    -a|--archive)
      if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
        ARCHIVE_PATH="$2"
        shift 2
      else
        ARCHIVE_PATH="${REPO_ROOT}/airgap/airgap-images.tar"
        shift
      fi
      ;;
    -l|--list)
      LIST_ONLY=true
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
echo " 🚀 KinD Container Image Pre-Loader"
echo "================================================================="
echo "🎯 Target Cluster: ${CLUSTER_NAME}"

# Verify KinD is installed
if ! command -v kind &>/dev/null; then
  echo "❌ 'kind' CLI is not installed or not in PATH."
  exit 1
fi

# Verify Docker is running
if ! command -v docker &>/dev/null; then
  echo "❌ 'docker' CLI is not installed or not in PATH."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker daemon is not running. Please start Docker Desktop / service."
  exit 1
fi

# Check if target cluster exists
existing_clusters="$(kind get clusters 2>/dev/null || true)"
if ! echo "${existing_clusters}" | grep -wq "${CLUSTER_NAME}"; then
  echo "❌ KinD cluster '${CLUSTER_NAME}' does not exist!"
  echo "💡 Create it first using:"
  echo "   ./01-create-cluster/create-cluster.sh"
  exit 1
fi

# ==============================================================================
# MODE 1: LOAD FROM ARCHIVE TARBALL
# ==============================================================================
if [[ -n "${ARCHIVE_PATH}" ]]; then
  if [[ ! -f "${ARCHIVE_PATH}" ]]; then
    echo "❌ Archive file not found: ${ARCHIVE_PATH}"
    exit 1
  fi
  echo "📦 Loading container images from archive: ${ARCHIVE_PATH}..."
  NATIVE_ARCHIVE="$(to_native_path "${ARCHIVE_PATH}")"
  kind load image-archive "${NATIVE_ARCHIVE}" --name "${CLUSTER_NAME}"
  echo "✅ All images from archive successfully loaded into KinD cluster '${CLUSTER_NAME}'!"
  exit 0
fi

# ==============================================================================
# MODE 2: LOAD FROM LOCAL DOCKER DAEMON
# ==============================================================================
if [[ ! -f "${IMAGES_FILE}" ]]; then
  echo "❌ Images inventory file not found at: ${IMAGES_FILE}"
  exit 1
fi

echo "📋 Reading image inventory from: airgap/images.yaml"
images=()
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^[[:space:]]*image:[[:space:]]*[\"\']?([^\"\'[:space:]]+) ]]; then
    images+=("${BASH_REMATCH[1]}")
  fi
done < "${IMAGES_FILE}"

if [[ ${#images[@]} -eq 0 ]]; then
  echo "❌ No images found in ${IMAGES_FILE}."
  exit 1
fi

echo "🔍 Found ${#images[@]} platform images in inventory."
echo ""

echo "📋 Querying local Docker daemon for cached images..."
local_images="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)"

present_images=()
missing_images=()

for img in "${images[@]}"; do
  stripped_img="${img#docker.io/}"
  if echo "${local_images}" | grep -Fxq "${img}"; then
    present_images+=("$img")
    [[ "${LIST_ONLY}" == "true" ]] && echo "  ✅ Present:  $img"
  elif echo "${local_images}" | grep -Fxq "${stripped_img}"; then
    present_images+=("$stripped_img")
    [[ "${LIST_ONLY}" == "true" ]] && echo "  ✅ Present:  $stripped_img (matches $img)"
  else
    missing_images+=("$img")
    [[ "${LIST_ONLY}" == "true" ]] && echo "  ❌ Missing:  $img"
  fi
done

if [[ "${LIST_ONLY}" == "true" ]]; then
  echo ""
  echo "Summary: ${#present_images[@]} present locally, ${#missing_images[@]} missing from Docker daemon."
  exit 0
fi

# Handle missing images
if [[ ${#missing_images[@]} -gt 0 ]]; then
  echo "⚠️  Found ${#missing_images[@]} image(s) missing from local Docker cache:"
  for m in "${missing_images[@]}"; do
    echo "   - $m"
  done
  echo ""

  if [[ "${AUTO_PULL}" == "true" ]]; then
    echo "⬇️  Pulling missing images automatically (--pull flag specified)..."
    for m in "${missing_images[@]}"; do
      echo "   📥 Pulling: $m"
      docker pull "$m"
      present_images+=("$m")
    done
    missing_images=()
  else
    echo "💡 You can pull them automatically using: $(basename "$0") --pull"
    read -r -p "👉 Would you like to pull missing images now? [y/N]: " confirm_pull
    if [[ "$confirm_pull" =~ ^[yY]([eE][sS])?$ ]]; then
      for m in "${missing_images[@]}"; do
        echo "   📥 Pulling: $m"
        docker pull "$m"
        present_images+=("$m")
      done
      missing_images=()
    else
      echo "ℹ️  Continuing with ${#present_images[@]} available image(s)..."
    fi
  fi
fi

if [[ ${#present_images[@]} -eq 0 ]]; then
  echo "❌ No images available to load into KinD."
  exit 1
fi

echo ""
echo "🚀 Loading ${#present_images[@]} image(s) into KinD cluster '${CLUSTER_NAME}'..."
echo "⏳ This may take 1-3 minutes depending on disk speed..."

# Load images in batches to prevent command line length issues while maintaining speed
batch_size=5
total=${#present_images[@]}
for ((i=0; i<total; i+=batch_size)); do
  batch=("${present_images[@]:i:batch_size}")
  echo "   📦 Loading batch ($((i+1))-$((i+${#batch[@]})) of ${total}):"
  for b in "${batch[@]}"; do
    echo "      • $b"
  done
  kind load docker-image "${batch[@]}" --name "${CLUSTER_NAME}"
done

echo ""
echo "================================================================="
echo "🎉 Successfully loaded ${#present_images[@]} images into KinD '${CLUSTER_NAME}'!"
echo "   All pods (Traefik, cert-manager, Metrics Server, Argo CD, Harbor)"
echo "   will now start instantly without network delays or image pull timeouts."
echo "================================================================="
