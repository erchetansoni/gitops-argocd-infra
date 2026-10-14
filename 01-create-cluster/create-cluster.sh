#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/kind-cluster-config.yaml"
# ==============================================================================

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# Verify configuration file exists
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "❌ Kind cluster config file not found at: ${CONFIG_FILE}"
  exit 1
fi

########## 🚀 Creating Kind Local Cluster ###########################
K8S_VERSION=$(grep 'image:' "${CONFIG_FILE}" | head -n 1 | awk -F':' '{print $NF}')
echo "🚀 The Kind cluster will be created with Kubernetes version ${K8S_VERSION}"
read -p "Do you want to proceed? (y/n): " user_input

if [[ "$user_input" != "y" && "$user_input" != "Y" ]]; then
  echo "❌ Operation canceled. Please update the Kubernetes version in the kind-cluster-config.yaml file if needed."
  exit 1
fi

echo "🚀 Creating Kind cluster with Kubernetes version ${K8S_VERSION} ..."
CONFIG_FILE_NATIVE="$(to_native_path "${CONFIG_FILE}")"
kind create cluster --config "${CONFIG_FILE_NATIVE}"

# Wait for all pods in kube-system namespace to be Ready
kubectl wait --namespace kube-system \
  --for=condition=Ready pods \
  --all \
  --timeout=180s

echo "✅ Kind cluster created successfully!"
