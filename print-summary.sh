#!/bin/bash
# ==============================================================================
# GitOps Platform - Access & Credentials Summary Tool
# ==============================================================================
# Displays service URLs, login credentials, cluster status, and DNS setup.
# Can be run standalone anytime: ./print-summary.sh
# Or invoked upon script completion/failure: ./print-summary.sh --failed-step "..."
# ==============================================================================

set -uo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/load-env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/load-env.sh"
fi

# Configuration Defaults (from .env or fallbacks)
ARGOCD_HOST="${ARGOCD_HOST:-argocd.${MAIN_DOMAIN:-chetan.local}}"
HARBOR_HOST="${HARBOR_HOST:-cr.${MAIN_DOMAIN:-chetan.local}}"
FORGEJO_HOST="${FORGEJO_HOST:-git.${MAIN_DOMAIN:-chetan.local}}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
FORGEJO_NAMESPACE="${FORGEJO_NAMESPACE:-forgejo}"
HARBOR_NAMESPACE="${HARBOR_NAMESPACE:-harbor}"
FORGEJO_RUNNER_NAMESPACE="${FORGEJO_RUNNER_NAMESPACE:-forgejo-runner}"
FORGEJO_USER="${FORGEJO_USER:-forgejo_admin}"
FORGEJO_PASS="${FORGEJO_PASS:-Forgejo12345}"
FORGEJO_REPO_NAME="${FORGEJO_REPO_NAME:-gitops-argocd-infra}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"

# Parse optional arguments
FAILED_STEP=""
EXIT_CODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --failed-step)
      FAILED_STEP="${2:-}"
      shift 2
      ;;
    --exit-code)
      EXIT_CODE="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# Check if Kubernetes cluster is accessible
K8S_ONLINE=0
if kubectl cluster-info >/dev/null 2>&1; then
  K8S_ONLINE=1
fi

echo ""
if [[ -n "${FAILED_STEP}" ]]; then
  echo "================================================================================="
  echo " ❌ PLATFORM ORCHESTRATION HALTED: ${FAILED_STEP}"
  if [[ -n "${EXIT_CODE}" ]]; then
    echo " ⚠️ Exit Code: ${EXIT_CODE}"
  fi
  echo "================================================================================="
  echo " 💡 Troubleshooting Suggestions:"
  echo "    • View recent cluster events:"
  echo "      kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -n 25"
  echo "    • Check troubled pods:"
  echo "      kubectl get pods -A | grep -E 'Error|CrashLoopBackOff|Pending|Terminating'"
  echo "    • Re-run the specific failed script individually to see verbose logs."
  echo ""
  echo " ℹ️ Below is the access information for services deployed up to this point:"
  echo "---------------------------------------------------------------------------------"
else
  echo "================================================================================="
  echo " 🎉 GITOPS PLATFORM - ACCESS URLS & LOGIN CREDENTIALS SUMMARY"
  echo "================================================================================="
fi

# ------------------------------------------------------------------------------
# 1. Argo CD
# ------------------------------------------------------------------------------
echo ""
echo "🐙 1. ARGO CD (GitOps Controller & Web UI)"
echo "   -----------------------------------------------------------------------------"
if [[ ${K8S_ONLINE} -eq 1 ]] && kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  ARGOCD_POD_STATUS=$(kubectl get pods -n "${ARGOCD_NAMESPACE}" -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
  echo "   Status:      🟢 Ready (${ARGOCD_POD_STATUS})"
else
  echo "   Status:      ⚪ Not yet running / not installed"
fi
echo "   URL:         https://${ARGOCD_HOST}"
echo "   Username:    admin"

ARGOCD_PWD=""
if [[ ${K8S_ONLINE} -eq 1 ]] && kubectl get secret argocd-initial-admin-secret -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  ARGOCD_PWD=$(kubectl get secret argocd-initial-admin-secret -n "${ARGOCD_NAMESPACE}" -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || true)
fi

if [[ -n "${ARGOCD_PWD}" ]]; then
  echo "   Password:    ${ARGOCD_PWD}"
else
  echo "   Password:    (Initial secret rotated/deleted. Check your customized password)"
fi
echo "   CLI Login:   argocd login ${ARGOCD_HOST} --username admin --insecure"

# ------------------------------------------------------------------------------
# 2. Forgejo Git Service
# ------------------------------------------------------------------------------
echo ""
echo "🦊 2. FORGEJO (In-Cluster Git Service & Actions)"
echo "   -----------------------------------------------------------------------------"
if [[ ${K8S_ONLINE} -eq 1 ]] && kubectl get deployment forgejo -n "${FORGEJO_NAMESPACE}" >/dev/null 2>&1; then
  FORGEJO_POD_STATUS=$(kubectl get pods -n "${FORGEJO_NAMESPACE}" -l app.kubernetes.io/name=forgejo -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
  echo "   Status:      🟢 Ready (${FORGEJO_POD_STATUS})"
else
  echo "   Status:      ⚪ Not yet running / not installed"
fi
echo "   Web UI:      https://${FORGEJO_HOST}"
echo "   Username:    ${FORGEJO_USER}"
echo "   Password:    ${FORGEJO_PASS}"
echo "   Clone URL:   https://${FORGEJO_HOST}/${FORGEJO_USER}/${FORGEJO_REPO_NAME}.git"
echo "   Internal:    http://forgejo-http.${FORGEJO_NAMESPACE}.svc.cluster.local:3000/${FORGEJO_USER}/${FORGEJO_REPO_NAME}.git"

# ------------------------------------------------------------------------------
# 3. Harbor Container Registry
# ------------------------------------------------------------------------------
echo ""
echo "🚢 3. HARBOR (Private Container & OCI Registry)"
echo "   -----------------------------------------------------------------------------"
if [[ ${K8S_ONLINE} -eq 1 ]] && kubectl get deployment harbor-core -n "${HARBOR_NAMESPACE}" >/dev/null 2>&1; then
  HARBOR_POD_STATUS=$(kubectl get pods -n "${HARBOR_NAMESPACE}" -l app=harbor,component=core -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
  echo "   Status:      🟢 Ready (${HARBOR_POD_STATUS})"
else
  echo "   Status:      ⚪ Not yet running / not installed"
fi
echo "   Web UI:      https://${HARBOR_HOST}"
echo "   Username:    admin"
echo "   Password:    ${HARBOR_ADMIN_PASSWORD}"
echo "   Docker CLI:  docker login ${HARBOR_HOST} -u admin -p ${HARBOR_ADMIN_PASSWORD}"

# ------------------------------------------------------------------------------
# 4. Traefik Gateway API
# ------------------------------------------------------------------------------
echo ""
echo "🚦 4. TRAEFIK GATEWAY API"
echo "   -----------------------------------------------------------------------------"
if [[ ${K8S_ONLINE} -eq 1 ]] && kubectl get gateway main-gateway -n default >/dev/null 2>&1; then
  ROUTE_COUNT=$(kubectl get httproute -A --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  echo "   Gateway:     🟢 Active ('main-gateway' on Ports 80 & 443, Routes: ${ROUTE_COUNT})"
else
  echo "   Gateway:     ⚪ Not yet ready"
fi

# ------------------------------------------------------------------------------
# 5. Local Hosts / DNS Entry Requirement
# ------------------------------------------------------------------------------
echo ""
echo "🌐 5. LOCAL DNS / HOSTS RESOLUTION"
echo "   -----------------------------------------------------------------------------"
echo "   Ensure local domains resolve to 127.0.0.1:"
echo "   • Windows (Run PowerShell as Administrator):"
echo "     Add-Content -Path C:\\Windows\\System32\\drivers\\etc\\hosts -Value \"127.0.0.1 ${ARGOCD_HOST} ${FORGEJO_HOST} ${HARBOR_HOST}\""
echo ""
echo "   • Linux / macOS:"
echo "     echo \"127.0.0.1 ${ARGOCD_HOST} ${FORGEJO_HOST} ${HARBOR_HOST}\" | sudo tee -a /etc/hosts"

# ------------------------------------------------------------------------------
# 6. Applications & Workloads
# ------------------------------------------------------------------------------
if [[ ${K8S_ONLINE} -eq 1 ]] && kubectl get applicationset -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
  APP_COUNT=$(kubectl get applications -n "${ARGOCD_NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  echo ""
  echo "📦 6. GITOPS APPLICATIONS"
  echo "   -----------------------------------------------------------------------------"
  echo "   Root ApplicationSet: branch-environments"
  echo "   Active Applications: ${APP_COUNT} managed by Argo CD"
fi

echo ""
echo "================================================================================="
echo " 💡 Quick Commands:"
echo "    • View all pods:       kubectl get pods -A"
echo "    • View all routes:     kubectl get httproute -A"
echo "    • View Argo CD apps:   kubectl get applications -n ${ARGOCD_NAMESPACE}"
echo "    • Re-display summary:  ./print-summary.sh"
echo "================================================================================="
echo ""
