#!/usr/bin/env bash

# ==============================================================================
# Script: install-k3s-platform.sh
# Purpose: Orchestrates platform installation on a 3-Node K3s Cluster in Air-Gap
#          or Online mode (skipping KinD cluster provisioning).
# ==============================================================================

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/load-env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/load-env.sh"
fi

# Set default Kubeconfig to K3s standard if not already explicitly set
if [[ -z "${KUBECONFIG:-}" && -f "/etc/rancher/k3s/k3s.yaml" ]]; then
  export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

# Internet detection
has_internet() {
  if curl -s --connect-timeout 2 --max-time 3 "https://1.1.1.1" >/dev/null 2>&1 || \
     curl -s --connect-timeout 2 --max-time 3 "https://www.google.com" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

echo "================================================================="
echo " 🚀 K3s GitOps Platform Orchestrator (Air-Gap / Production)"
echo "================================================================="

if [[ -z "${INSTALL_MODE:-}" ]]; then
  echo "🔍 Checking internet connectivity..."
  if has_internet; then
    echo "🌐 Internet connection is ACTIVE."
    echo ""
    echo "Select Installation Mode:"
    echo "  1) Air-Gap Mode  (Offline - use local image tarballs & in-cluster Helm repo) [Default]"
    echo "  2) Internet Mode (Online - fetch from public registries & Helm repositories)"
    echo ""
    read -r -p "👉 Choose mode [1/2] (Default: 1): " choice
    if [[ "${choice:-1}" == "2" ]]; then
      export INSTALL_MODE="online"
      echo "🌐 Proceeding in INTERNET (Online) Mode."
    else
      export INSTALL_MODE="airgap"
      echo "📦 Proceeding in AIR-GAP (Offline) Mode."
    fi
  else
    echo "🔌 No Internet connection detected!"
    echo "⚡ Automatically proceeding in AIR-GAP (Offline) Mode."
    export INSTALL_MODE="airgap"
  fi
else
  echo "ℹ️ Using pre-set INSTALL_MODE='${INSTALL_MODE}'"
fi

# Verify cluster access
echo "🔍 Verifying Kubernetes cluster connectivity..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "❌ Unable to connect to Kubernetes cluster."
  echo "👉 Make sure KUBECONFIG is set properly (e.g., export KUBECONFIG=/etc/rancher/k3s/k3s.yaml)"
  exit 1
fi
echo "✅ Connected to Kubernetes cluster. Nodes:"
kubectl get nodes -o wide

run_step() {
  local step_num="$1"
  local step_title="$2"
  shift 2

  echo ""
  echo "================================================================="
  echo " ▶️ [Step ${step_num}] ${step_title}"
  echo "================================================================="
  local start_time
  start_time=$(date +%s)

  if ! "$@"; then
    local exit_code=$?
    echo ""
    echo "❌ ERROR: [Step ${step_num}] ${step_title} failed with exit code ${exit_code}!"
    if [[ -x "${SCRIPT_DIR}/print-summary.sh" ]]; then
      "${SCRIPT_DIR}/print-summary.sh" --failed-step "Step ${step_num}: ${step_title}" --exit-code "${exit_code}"
    fi
    exit "${exit_code}"
  fi

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  echo "✅ [Step ${step_num}] ${step_title} finished in ${duration}s"
}

# ------------------------------------------------------------------------------
# Platform Deployment Sequence (K3s Bare Metal / VM)
# ------------------------------------------------------------------------------
run_step "02"  "Install Traefik Gateway Controller"        ./02-traefik-controller/install-traefik-gateway-controller.sh
run_step "03"  "Install Cert-Manager & Root CA"            ./03-cert-manager/install-cert-manager.sh
run_step "04"  "Install Traefik Gateway & TLS Listener"    ./04-traefik-gateway/install-traefik-gatewayclass.sh
run_step "05a" "Install Kubernetes Metrics Server"         ./05-infra-apps/02-metrics-server/install-metrics-server.sh
run_step "05b" "Install Harbor Private Registry"           ./05-infra-apps/03-harbor/install-harbor.sh
run_step "05c" "Install Forgejo In-Cluster Git Service"    ./05-infra-apps/04-forgejo/install-forgejo.sh
run_step "05d" "Sync Local Git Repo to Forgejo"            ./05-infra-apps/04-forgejo/sync-repo-to-forgejo.sh
run_step "05e" "Install Forgejo Actions Runner"            ./05-infra-apps/05-forgejo-runner/install-forgejo-runner.sh
run_step "05f" "Install Zabbix Monitoring Platform"         ./05-infra-apps/06-zabbix/install-zabbix.sh
run_step "06a" "Install Argo CD GitOps Server"             ./06-argocd/01-install-argocd.sh
run_step "06b" "Adopt Infrastructure Apps into Argo CD"    ./06-argocd/02-adopt-infra-apps.sh
run_step "06c" "Register Forgejo Git Repo in Argo CD"      ./06-argocd/03-configure-forgejo-repo.sh

# Optional Workload Apps (if present)
if [[ -f "./07-apps/01-install-repo-creds-secret.sh" && -f "./07-apps/02-install-root-app.sh" ]]; then
  if [[ -n "${REPO_URL:-}" && "${REPO_URL}" != *"your-git-user"* ]]; then
    run_step "07a" "Install Workload Repo Credentials Secret"  ./07-apps/01-install-repo-creds-secret.sh
    run_step "07b" "Install Root ApplicationSet"               ./07-apps/02-install-root-app.sh
  else
    echo ""
    echo "ℹ️ Skipping Step 07 (Workload Apps): REPO_URL in .env is not yet set to a real workload repository."
  fi
fi

# ==============================================================================
# FINAL ACCESS & CREDENTIALS SUMMARY
# ==============================================================================
if [[ -x "${SCRIPT_DIR}/print-summary.sh" ]]; then
  "${SCRIPT_DIR}/print-summary.sh"
fi
