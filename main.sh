#!/bin/bash

set -euo pipefail

export MSYS_NO_PATHCONV=1

./01-create-cluster/create-cluster.sh
./02-Traefik-Gateway-Controller/install-traefik-gateway-controller.sh
./03-Traefik-Gateway-Class/install-traefik-gatewayclass.sh
./04-infra-apps/02-metrics-server/install-metrics-server.sh
./05-argocd/01-install-argocd.sh
./05-argocd/02-adopt-infra-apps.sh
./06-apps/01-install-repo-creds-secret.sh
./06-apps/02-install-root-app.sh
