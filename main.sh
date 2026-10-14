#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/load-env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/load-env.sh"
fi

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

# Execute Bootstrap Sequence
run_step "01a" "Create / Verify KinD Cluster"              ./01-create-cluster/create-cluster.sh
run_step "01b" "Pre-Load Container Images into KinD"       ./01-create-cluster/load-images-to-kind.sh --pull
run_step "02"  "Install Traefik Gateway Controller"        ./02-traefik-controller/install-traefik-gateway-controller.sh
run_step "03"  "Install Cert-Manager & Root CA"            ./03-cert-manager/install-cert-manager.sh
run_step "04"  "Install Traefik Gateway & TLS Listener"    ./04-traefik-gateway/install-traefik-gatewayclass.sh
run_step "05a" "Install Kubernetes Metrics Server"         ./05-infra-apps/02-metrics-server/install-metrics-server.sh
run_step "05b" "Install Harbor Private Registry"           ./05-infra-apps/03-harbor/install-harbor.sh
run_step "05c" "Install Forgejo In-Cluster Git Service"    ./05-infra-apps/04-forgejo/install-forgejo.sh
run_step "05d" "Sync Local Git Repo to Forgejo"            ./05-infra-apps/04-forgejo/sync-repo-to-forgejo.sh
run_step "05e" "Install Forgejo Actions Runner"            ./05-infra-apps/05-forgejo-runner/install-forgejo-runner.sh
run_step "06a" "Install Argo CD GitOps Server"             ./06-argocd/01-install-argocd.sh
run_step "06b" "Adopt Infrastructure Apps into Argo CD"    ./06-argocd/02-adopt-infra-apps.sh
run_step "06c" "Register Forgejo Git Repo in Argo CD"      ./06-argocd/03-configure-forgejo-repo.sh
run_step "07a" "Install Workload Repo Credentials Secret"  ./07-apps/01-install-repo-creds-secret.sh
run_step "07b" "Install Root ApplicationSet"               ./07-apps/02-install-root-app.sh

# ==============================================================================
# FINAL ACCESS & CREDENTIALS SUMMARY (ALWAYS AT THE END OF EXECUTION)
# ==============================================================================
if [[ -x "${SCRIPT_DIR}/print-summary.sh" ]]; then
  "${SCRIPT_DIR}/print-summary.sh"
fi
