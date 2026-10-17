#!/bin/bash
# ==============================================================================
# ☸️ Zabbix Kubernetes Cluster Monitoring Setup Script
#
# This script configures enterprise Kubernetes monitoring in Zabbix:
# - PART 1 (ACTIVE): Local Cluster (Self - where Zabbix runs)
#   Applies read-only RBAC, deploys kube-state-metrics, extracts the ServiceAccount
#   token, and registers host 'k8s-local-cluster' with template 'Kubernetes cluster state by HTTP'.
#
# - PART 2 (COMMENTED OUT): Remote Kubernetes Cluster (AWS EKS, GKE, AKS, Edge)
#   Ready-to-use template for adding external/remote Kubernetes clusters using
#   the recommended secure Zabbix Proxy pattern (mTLS over TCP 10051).
# ==============================================================================

set -euo pipefail

export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${ZABBIX_NAMESPACE:-zabbix}"
ZABBIX_WEB_INTERNAL="http://zabbix-zabbix-web.zabbix.svc/api_jsonrpc.php"
ZABBIX_USER="${ZABBIX_ADMIN_USER:-Admin}"
ZABBIX_PASS="${ZABBIX_ADMIN_PASSWORD:-zabbix}"
MANIFEST_FILE="${SCRIPT_DIR}/zabbix-k8s-monitoring.yaml"

echo "================================================================="
echo " ☸️  Setting up Kubernetes Monitoring in Zabbix"
echo "================================================================="

to_native_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$p"
  else
    echo "$p"
  fi
}

# ==============================================================================
# PART 1: LOCAL CLUSTER MONITORING (ACTIVE & AUTOMATED)
# ==============================================================================
echo ""
echo "🚀 [PART 1/2] Setting up Local Cluster Monitoring (Self)..."

# 1. Apply Kubernetes Monitoring Manifests (RBAC + kube-state-metrics)
if [[ -f "${MANIFEST_FILE}" ]]; then
  echo "📦 Applying Zabbix RBAC & kube-state-metrics manifests..."
  MANIFEST_NATIVE="$(to_native_path "${MANIFEST_FILE}")"
  kubectl apply -n "${NAMESPACE}" -f "${MANIFEST_NATIVE}"
else
  echo "❌ Error: Manifest file '${MANIFEST_FILE}' not found!"
  exit 1
fi

# 2. Wait for kube-state-metrics rollout
echo "⏳ Waiting for zabbix-kube-state-metrics deployment..."
kubectl rollout status deployment/zabbix-kube-state-metrics -n "${NAMESPACE}" --timeout=120s

# 3. Extract the Long-Lived ServiceAccount Token
echo "🔑 Extracting zabbix-service-account token..."
K8S_TOKEN=""
for i in {1..15}; do
  TOKEN_B64=$(kubectl get secret zabbix-service-account-token -n "${NAMESPACE}" -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [[ -n "${TOKEN_B64}" ]]; then
    K8S_TOKEN=$(echo "${TOKEN_B64}" | base64 -d)
    break
  fi
  sleep 2
done

if [[ -z "${K8S_TOKEN}" ]]; then
  echo "❌ Failed to extract ServiceAccount token from secret 'zabbix-service-account-token'."
  exit 1
fi
echo "✅ ServiceAccount token successfully retrieved."

# 4. Authenticate with Zabbix API
echo "🔐 Logging into Zabbix API..."
SERVER_POD=$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')

LOGIN_JSON=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "user.login",
  "params": {
    "username": "${ZABBIX_USER}",
    "password": "${ZABBIX_PASS}"
  },
  "id": 1
}
EOF
)

AUTH_TOKEN=$(kubectl exec -n "${NAMESPACE}" "${SERVER_POD}" -c zabbix-server -- \
  wget -qO- --post-data="${LOGIN_JSON}" --header="Content-Type: application/json" "${ZABBIX_WEB_INTERNAL}" | grep -o '"result":"[^"]*' | cut -d'"' -f4)

if [[ -z "${AUTH_TOKEN}" ]]; then
  echo "❌ Failed to authenticate with Zabbix API."
  exit 1
fi
echo "✅ Authenticated with Zabbix API. Auth token obtained."

# 5. Check if host 'k8s-local-cluster' already exists
CHECK_HOST_JSON=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "host.get",
  "params": {
    "filter": {
      "host": ["k8s-local-cluster"]
    }
  },
  "id": 2
}
EOF
)

EXISTING_HOST_ID=$(kubectl exec -n "${NAMESPACE}" "${SERVER_POD}" -c zabbix-server -- \
  wget -qO- --post-data="${CHECK_HOST_JSON}" --header="Content-Type: application/json" --header="Authorization: Bearer ${AUTH_TOKEN}" "${ZABBIX_WEB_INTERNAL}" | grep -o '"hostid":"[^"]*' | head -n 1 | cut -d'"' -f4 || true)

if [[ -n "${EXISTING_HOST_ID}" ]]; then
  echo "ℹ️  Host 'k8s-local-cluster' already exists (hostid: ${EXISTING_HOST_ID}). Updating macros..."
  UPDATE_MACROS_JSON=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "host.update",
  "params": {
    "hostid": "${EXISTING_HOST_ID}",
    "macros": [
      {
        "macro": "{\$KUBE.API.URL}",
        "value": "https://kubernetes.default.svc:443"
      },
      {
        "macro": "{\$KUBE.API.TOKEN}",
        "value": "${K8S_TOKEN}"
      },
      {
        "macro": "{\$KUBE.STATE.ENDPOINT.NAME}",
        "value": "zabbix-kube-state-metrics"
      },
      {
        "macro": "{\$HTTP.TLS.VERIFY}",
        "value": "none"
      }
    ]
  },
  "id": 3
}
EOF
)
  kubectl exec -n "${NAMESPACE}" "${SERVER_POD}" -c zabbix-server -- \
    wget -qO- --post-data="${UPDATE_MACROS_JSON}" --header="Content-Type: application/json" --header="Authorization: Bearer ${AUTH_TOKEN}" "${ZABBIX_WEB_INTERNAL}" >/dev/null
  echo "✅ Host 'k8s-local-cluster' macros updated successfully."
else
  echo "➕ Creating host 'k8s-local-cluster' with template 'Kubernetes cluster state by HTTP'..."
  CREATE_HOST_JSON=$(cat <<EOF
{
  "jsonrpc": "2.0",
  "method": "host.create",
  "params": {
    "host": "k8s-local-cluster",
    "name": "Kubernetes Local Cluster (Self)",
    "groups": [
      {
        "groupid": "19"
      }
    ],
    "templates": [
      {
        "templateid": "10510"
      }
    ],
    "interfaces": [
      {
        "type": 1,
        "main": 1,
        "useip": 1,
        "ip": "127.0.0.1",
        "dns": "",
        "port": "10050"
      }
    ],
    "macros": [
      {
        "macro": "{\$KUBE.API.URL}",
        "value": "https://kubernetes.default.svc:443"
      },
      {
        "macro": "{\$KUBE.API.TOKEN}",
        "value": "${K8S_TOKEN}"
      },
      {
        "macro": "{\$KUBE.STATE.ENDPOINT.NAME}",
        "value": "zabbix-kube-state-metrics"
      },
      {
        "macro": "{\$HTTP.TLS.VERIFY}",
        "value": "none"
      }
    ]
  },
  "id": 4
}
EOF
)
  RESULT=$(kubectl exec -n "${NAMESPACE}" "${SERVER_POD}" -c zabbix-server -- \
    wget -qO- --post-data="${CREATE_HOST_JSON}" --header="Content-Type: application/json" --header="Authorization: Bearer ${AUTH_TOKEN}" "${ZABBIX_WEB_INTERNAL}")
  echo "✅ Host created: ${RESULT}"
fi

# 6. Reload Zabbix Server config cache
echo "🔄 Reloading Zabbix Server config cache..."
kubectl exec -n "${NAMESPACE}" "${SERVER_POD}" -c zabbix-server -- zabbix_server -R config_cache_reload >/dev/null
echo "✅ Local Kubernetes Cluster monitoring is active!"


# ==============================================================================
# PART 2: REMOTE KUBERNETES CLUSTER MONITORING (COMMENTED OUT / READY TO USE)
# ==============================================================================
#
# To monitor an external or remote Kubernetes cluster (e.g. AWS EKS, Google GKE,
# Azure AKS, or remote bare-metal / edge cluster), follow the enterprise best practice:
#
# 1. DEPLOY A ZABBIX PROXY INSIDE THE REMOTE CLUSTER:
#    - The remote proxy connects OUTBOUND to your HQ Server: zbx-srv.chetan.local:10051 via mTLS.
#    - Zero inbound firewall ports are opened in the remote cluster!
#
# 2. RUN KUBE-STATE-METRICS & RBAC INSIDE THE REMOTE CLUSTER.
#
# 3. UNCOMMENT AND CONFIGURE THE BLOCK BELOW WHEN READY TO ONBOARD A REMOTE CLUSTER:
#
# ------------------------------------------------------------------------------
# REMOTE_CLUSTER_NAME="k8s-aws-eks-prod"
# REMOTE_CLUSTER_DISPLAY_NAME="AWS EKS Production Cluster (US-East)"
# REMOTE_PROXY_NAME="US-EKS-ZBX-PROXY"
# REMOTE_K8S_TOKEN="<PASTE_REMOTE_SERVICE_ACCOUNT_TOKEN_HERE>"
#
# echo "🚀 [PART 2/2] Registering Remote Cluster '${REMOTE_CLUSTER_NAME}'..."
#
# # 1. Find the Proxy ID registered for the remote cluster
# REMOTE_PROXY_ID=$(kubectl exec -n "${NAMESPACE}" "${SERVER_POD}" -c zabbix-server -- psql -U zabbix -d zabbix -t -A -c \
#   "SELECT proxyid FROM proxy WHERE name = '${REMOTE_PROXY_NAME}';" || true)
#
# # 2. Register Remote Cluster Host pointing to the Remote Proxy
# CREATE_REMOTE_HOST_JSON=$(cat <<EOF
# {
#   "jsonrpc": "2.0",
#   "method": "host.create",
#   "params": {
#     "host": "${REMOTE_CLUSTER_NAME}",
#     "name": "${REMOTE_CLUSTER_DISPLAY_NAME}",
#     "monitored_by": 1,
#     "proxyid": "${REMOTE_PROXY_ID}",
#     "groups": [
#       {
#         "groupid": "19"
#       }
#     ],
#     "templates": [
#       {
#         "templateid": "10510"
#       }
#     ],
#     "interfaces": [
#       {
#         "type": 1,
#         "main": 1,
#         "useip": 1,
#         "ip": "127.0.0.1",
#         "dns": "",
#         "port": "10050"
#       }
#     ],
#     "macros": [
#       {
#         "macro": "{\$KUBE.API.URL}",
#         "value": "https://kubernetes.default.svc:443"
#       },
#       {
#         "macro": "{\$KUBE.API.TOKEN}",
#         "value": "${REMOTE_K8S_TOKEN}"
#       },
#       {
#         "macro": "{\$KUBE.STATE.ENDPOINT.NAME}",
#         "value": "zabbix-kube-state-metrics"
#       },
#       {
#         "macro": "{\$HTTP.TLS.VERIFY}",
#         "value": "none"
#       }
#     ]
#   },
#   "id": 5
# }
# EOF
# )
#
# kubectl exec -n "${NAMESPACE}" "${SERVER_POD}" -c zabbix-server -- \
#   wget -qO- --post-data="${CREATE_REMOTE_HOST_JSON}" --header="Content-Type: application/json" --header="Authorization: Bearer ${AUTH_TOKEN}" "${ZABBIX_WEB_INTERNAL}"
#
# echo "✅ Remote cluster '${REMOTE_CLUSTER_NAME}' successfully onboarded!"
# ------------------------------------------------------------------------------

echo ""
echo "================================================================="
echo "🎉 Kubernetes Monitoring Setup Complete!"
echo "   Host Name:    k8s-local-cluster"
echo "   Display Name: Kubernetes Local Cluster (Self)"
echo "   Template:     Kubernetes cluster state by HTTP"
echo "   KSM Service:  zabbix-kube-state-metrics:8080"
echo "   API Endpoint: https://kubernetes.default.svc:443"
echo "================================================================="
