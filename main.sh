#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

./01-create-cluster/create-cluster.sh
./02-traefik-controller/install-traefik-gateway-controller.sh
./03-cert-manager/install-cert-manager.sh
./04-traefik-gateway/install-traefik-gatewayclass.sh
./05-infra-apps/02-metrics-server/install-metrics-server.sh
./06-argocd/01-install-argocd.sh
./06-argocd/02-adopt-infra-apps.sh
./07-apps/01-install-repo-creds-secret.sh
./07-apps/02-install-root-app.sh


