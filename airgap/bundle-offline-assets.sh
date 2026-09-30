#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/images.yaml" ]]; then
  IMAGES_FILE="${SCRIPT_DIR}/images.yaml"
elif [[ -f "${SCRIPT_DIR}/images.yml" ]]; then
  IMAGES_FILE="${SCRIPT_DIR}/images.yml"
else
  IMAGES_FILE="${SCRIPT_DIR}/images.txt"
fi
OUTPUT_TAR="${SCRIPT_DIR}/airgap-images.tar"
CHARTS_DIR="${SCRIPT_DIR}/charts"

echo "================================================================="
echo " 📦 Air-Gap Asset Bundler (Run on Internet-Connected Machine)"
echo "================================================================="

if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null; then
  echo "❌ Neither Docker nor Podman is installed. Please install one to pull container images."
  exit 1
fi

CONTAINER_CLI="docker"
if ! command -v docker &>/dev/null && command -v podman &>/dev/null; then
  CONTAINER_CLI="podman"
fi

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"
echo "🐳 Using container runtime CLI: ${CONTAINER_CLI} (Target Platform: ${TARGET_PLATFORM})"

# 1. Pull container images
echo ""
echo "⬇️  Pulling all platform images from $(basename "${IMAGES_FILE}")..."
images_to_save=()

if [[ "${IMAGES_FILE}" =~ \.ya?ml$ ]]; then
  # Structured YAML format (images.yaml)
  while IFS= read -r line || [[ -n "$line" ]]; do
    cleaned="$(echo "$line" | sed -e 's/[[:space:]]*#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$cleaned" ]] && continue

    img=""
    if [[ "$cleaned" =~ image:[[:space:]]*[\"\']?([^\"\'[:space:]]+) ]]; then
      img="${BASH_REMATCH[1]}"
    elif [[ "$cleaned" =~ ^-[[:space:]]*[\"\']?([a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+) ]]; then
      img="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$img" ]]; then
      echo "   📥 Pulling: ${img}"
      if [[ "${CONTAINER_CLI}" == "docker" ]]; then
        ${CONTAINER_CLI} pull --platform "${TARGET_PLATFORM}" "${img}"
      else
        ${CONTAINER_CLI} pull "${img}"
      fi
      images_to_save+=("${img}")
    fi
  done < "${IMAGES_FILE}"
else
  # Plain text format (images.txt)
  while IFS= read -r line || [[ -n "$line" ]]; do
    img="$(echo "$line" | sed -e 's/[[:space:]]*#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$img" ]] && continue

    echo "   📥 Pulling: ${img}"
    if [[ "${CONTAINER_CLI}" == "docker" ]]; then
      ${CONTAINER_CLI} pull --platform "${TARGET_PLATFORM}" "${img}"
    else
      ${CONTAINER_CLI} pull "${img}"
    fi
    images_to_save+=("${img}")
  done < "${IMAGES_FILE}"
fi

# 2. Save all images to tar archive
echo ""
OUTPUT_TAR_NATIVE="$(to_native_path "${OUTPUT_TAR}")"
echo "💾 Exporting ${#images_to_save[@]} images to tarball: ${OUTPUT_TAR_NATIVE}..."
if [[ "${CONTAINER_CLI}" == "docker" ]]; then
  # Specify single platform to avoid multi-arch index references without blobs in containerd/kind import
  ${CONTAINER_CLI} save --platform "${TARGET_PLATFORM}" -o "${OUTPUT_TAR_NATIVE}" "${images_to_save[@]}"
else
  ${CONTAINER_CLI} save -o "${OUTPUT_TAR_NATIVE}" "${images_to_save[@]}"
fi
echo "✅ Images exported successfully: $(ls -lh "${OUTPUT_TAR}" 2>/dev/null | awk '{print $5}' || du -h "${OUTPUT_TAR}" 2>/dev/null)"

# 3. Download Helm charts
mkdir -p "${CHARTS_DIR}"
CHARTS_DIR_NATIVE="$(to_native_path "${CHARTS_DIR}")"
echo ""
echo "📦 Ensuring Helm charts are packaged in ${CHARTS_DIR}..."
if command -v helm &>/dev/null; then
  helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null 2>&1 || true
  helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null 2>&1 || true
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  helm pull traefik/traefik --version 41.6.0 -d "${CHARTS_DIR_NATIVE}"
  helm pull jetstack/cert-manager --version v1.21.2 -d "${CHARTS_DIR_NATIVE}"
  helm pull metrics-server/metrics-server --version 3.14.0 -d "${CHARTS_DIR_NATIVE}"
  helm repo index "${CHARTS_DIR_NATIVE}"
  echo "✅ Helm charts saved and repository index.yaml generated."
else
  echo "ℹ️ Helm not found on workstation; using pre-bundled charts if present."
fi

# 4. Download Argo CD offline manifest
ARGOCD_MANIFEST="${SCRIPT_DIR}/../06-argocd/argocd-install-v3.5.3.yaml"
if [[ ! -f "${ARGOCD_MANIFEST}" ]]; then
  echo "📥 Downloading Argo CD v3.5.3 offline install manifest..."
  ARGOCD_MANIFEST_NATIVE="$(to_native_path "${ARGOCD_MANIFEST}")"
  curl -sSL "https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml" -o "${ARGOCD_MANIFEST_NATIVE}"
  sed -i 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/g' "${ARGOCD_MANIFEST}"
  echo "✅ Argo CD manifest saved and configured for offline use (IfNotPresent)."
fi

echo ""
echo "================================================================="
echo "🎉 Air-Gap Bundle Completed Successfully!"
echo "-----------------------------------------------------------------"
echo "Next steps for your 3-Node K3s cluster:"
echo "1. Copy this entire repository and 'airgap/airgap-images.tar' to your"
echo "   air-gapped network (via USB drive or secure jump host)."
echo "2. On each of the 3 K3s nodes, run:"
echo "   sudo bash airgap/load-offline-assets.sh"
echo "================================================================="
