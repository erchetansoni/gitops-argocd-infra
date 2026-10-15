#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for env_loader in "${SCRIPT_DIR}/load-env.sh" "${SCRIPT_DIR}/../load-env.sh" "${SCRIPT_DIR}/../../load-env.sh"; do
  if [[ -f "${env_loader}" ]]; then
    # shellcheck disable=SC1090
    source "${env_loader}"
    break
  fi
done

# ==============================================================================
# CONFIGURATION VARIABLES (FROM .ENV OR DEFAULTS)
# ==============================================================================
MAIN_DOMAIN="${MAIN_DOMAIN:-chetan.local}"
ZABBIX_HOST="${ZABBIX_HOST:-zabbix.${MAIN_DOMAIN}}"
ZABBIX_SRV_HOST="${ZABBIX_SRV_HOST:-zbx-srv.${MAIN_DOMAIN}}"
ZABBIX_PROXY_HOST="${ZABBIX_PROXY_HOST:-zbx-proxy.${MAIN_DOMAIN}}"

NAMESPACE="${ZABBIX_NAMESPACE:-zabbix}"
RELEASE_NAME="${ZABBIX_RELEASE_NAME:-zabbix}"
HELM_REPO_URL="${ZABBIX_HELM_REPO_URL:-https://zabbix-community.github.io/helm-zabbix}"
HELM_CHART="${ZABBIX_HELM_CHART:-zabbix-community/zabbix}"
CHART_VERSION="${ZABBIX_CHART_VERSION:-7.1.0}"
VALUES_FILE="${SCRIPT_DIR}/zabbix-values.yaml"
HTTPROUTE_FILE="${SCRIPT_DIR}/zabbix-httproute.yaml"

ZABBIX_USER="${ZABBIX_ADMIN_USER:-Admin}"
ZABBIX_PASS="${ZABBIX_ADMIN_PASSWORD:-zabbix}"
ZABBIX_DB_PASS="${ZABBIX_DB_PASSWORD:-Zabbix12345}"
# ==============================================================================

echo "================================================================="
echo " 📊 Installing Zabbix Monitoring Platform (${ZABBIX_HOST})"
echo "================================================================="
echo "📌 Web UI Host:       https://${ZABBIX_HOST}"
echo "📌 Server Host:       ${ZABBIX_SRV_HOST} (Port 10051)"
echo "📌 Proxy Host:        ${ZABBIX_PROXY_HOST} (SQLite3)"
echo "📌 TimescaleDB:       timescale/timescaledb:2.17.2-pg16"
echo "📌 Agent:             Zabbix Agent 2 (DaemonSet)"
echo "📌 Namespace:         ${NAMESPACE}"
echo "================================================================="

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# Step 0: Locate Helm Chart (Offline Tarball or Online Repo)
OFFLINE_CHART=""
for c in "${SCRIPT_DIR}/../../airgap/charts/zabbix-${CHART_VERSION}.tgz" \
         "${SCRIPT_DIR}/../../airgap/charts/zabbix-"*.tgz \
         "${SCRIPT_DIR}/zabbix-"*.tgz; do
  if compgen -G "${c}" >/dev/null; then
    candidates=( ${c} )
    OFFLINE_CHART="${candidates[0]}"
    break
  fi
done

VERSION_FLAG=()
if [[ -n "${OFFLINE_CHART}" && -f "${OFFLINE_CHART}" ]]; then
  echo "📦 Offline environment: Using local Zabbix Helm chart: ${OFFLINE_CHART}"
  CHART_SOURCE="$(to_native_path "${OFFLINE_CHART}")"
else
  echo "📦 Adding/Updating Zabbix Helm repository..."
  helm repo add zabbix-community "${HELM_REPO_URL}" --force-update
  helm repo update zabbix-community
  CHART_SOURCE="${HELM_CHART}"
  VERSION_FLAG=(--version "${CHART_VERSION}")
fi

# Step 1: Install or Upgrade Zabbix Helm Release
echo "🚀 Installing Zabbix in namespace '${NAMESPACE}'..."
VALUES_FILE_NATIVE="$(to_native_path "${VALUES_FILE}")"
helm upgrade --install "${RELEASE_NAME}" "${CHART_SOURCE}" \
  ${VERSION_FLAG[@]+"${VERSION_FLAG[@]}"} \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --values "${VALUES_FILE_NATIVE}" \
  --set postgresAccess.password="${ZABBIX_DB_PASS}" \
  --wait \
  --timeout 10m

# Step 2: Apply Gateway API HTTPRoute
echo ""
echo "🌐 Step 2: Applying Gateway API HTTPRoute (${HTTPROUTE_FILE})..."
if [[ -f "${HTTPROUTE_FILE}" ]]; then
  if [[ "${MAIN_DOMAIN}" != "chetan.local" ]]; then
    echo "🔄 Adapting HTTPRoute hostnames to '${MAIN_DOMAIN}'..."
    sed "s|chetan.local|${MAIN_DOMAIN}|g" "${HTTPROUTE_FILE}" | kubectl apply -n "${NAMESPACE}" --server-side --force-conflicts -f -
  else
    HTTPROUTE_NATIVE="$(to_native_path "${HTTPROUTE_FILE}")"
    kubectl apply -n "${NAMESPACE}" --server-side --force-conflicts -f "${HTTPROUTE_NATIVE}"
  fi
fi

# Step 3: Wait for Workloads Rollout
echo ""
echo "⏳ Step 3: Waiting for Zabbix workloads rollout to complete..."
for d in "${RELEASE_NAME}-zabbix-server" "${RELEASE_NAME}-zabbix-server-standby" "${RELEASE_NAME}-zabbix-web"; do
  if kubectl get deployment "$d" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "   Checking deployment: $d..."
    kubectl rollout status deployment/"$d" -n "${NAMESPACE}" --timeout=180s || true
  fi
done

for s in "${RELEASE_NAME}-postgresql" "${RELEASE_NAME}-zabbix-proxy"; do
  if kubectl get statefulset "$s" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "   Checking statefulset: $s..."
    kubectl rollout status statefulset/"$s" -n "${NAMESPACE}" --timeout=180s || true
  fi
done

if kubectl get daemonset "${RELEASE_NAME}-zabbix-agent" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "   Checking daemonset: ${RELEASE_NAME}-zabbix-agent..."
  kubectl rollout status daemonset/"${RELEASE_NAME}-zabbix-agent" -n "${NAMESPACE}" --timeout=120s || true
fi

# Step 3b: Bootstrap Proxy & Agent Interface
echo ""
echo "⚙️ Step 3b: Bootstrapping active proxy & server agent interface..."
for i in {1..30}; do
  if kubectl exec -n "${NAMESPACE}" "${RELEASE_NAME}-postgresql-0" -- psql -U zabbix -d zabbix -c "SELECT 1 FROM interface WHERE interfaceid = 1;" >/dev/null 2>&1; then
    kubectl exec -n "${NAMESPACE}" "${RELEASE_NAME}-postgresql-0" -- psql -U zabbix -d zabbix -c \
      "UPDATE interface SET useip = 0, dns = '${RELEASE_NAME}-zabbix-agent' WHERE interfaceid = 1;" >/dev/null 2>&1 || true
    kubectl exec -n "${NAMESPACE}" "${RELEASE_NAME}-postgresql-0" -- psql -U zabbix -d zabbix -c \
      "INSERT INTO proxy (proxyid, name, operating_mode) VALUES (1, 'zbx-proxy', 0) ON CONFLICT (name) DO NOTHING;" >/dev/null 2>&1 || true
    kubectl exec -n "${NAMESPACE}" "${RELEASE_NAME}-postgresql-0" -- psql -U zabbix -d zabbix -c \
      "INSERT INTO proxy_rtdata (proxyid, state, version, compatibility) VALUES (1, 2, 70415, 1) ON CONFLICT (proxyid) DO UPDATE SET state = 2, version = 70415, compatibility = 1;" >/dev/null 2>&1 || true
    echo "✅ Zabbix active proxy 'zbx-proxy' registered and server agent interface configured."
    break
  fi
  sleep 2
done

# Step 4: Verification & Route Info
echo ""
echo "================================================================="
echo " 🔍 Zabbix Verification & Route Information"
echo "================================================================="
kubectl get httproute -n "${NAMESPACE}" 2>/dev/null || true
echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""

echo "================================================================="
echo "🎉 Zabbix Monitoring Platform successfully deployed!"
echo "   Web UI:       https://${ZABBIX_HOST}"
echo "   Server FQDN:  ${ZABBIX_SRV_HOST} (In-cluster: ${RELEASE_NAME}-zabbix-server:10051)"
echo "   Proxy FQDN:   ${ZABBIX_PROXY_HOST} (In-cluster: ${RELEASE_NAME}-zabbix-proxy:10051)"
echo "   Username:     ${ZABBIX_USER}"
echo "   Password:     ${ZABBIX_PASS}"
echo "   Database:     TimescaleDB (timescale/timescaledb:2.17.2-pg16)"
echo "   Agent:        Zabbix Agent 2 (DaemonSet on all nodes)"
echo ""
echo "💡 Hosts file entries to add (if not already added):"
echo "   127.0.0.1 ${ZABBIX_HOST} ${ZABBIX_SRV_HOST} ${ZABBIX_PROXY_HOST}"
echo ""
echo "💡 Tip: Run ./print-summary.sh anytime to view all platform credentials & URLs."
echo "================================================================="
