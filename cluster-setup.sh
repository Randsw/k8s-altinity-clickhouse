#!/usr/bin/env bash

set -euo pipefail

# CONSTANTS

readonly KIND_CLUSTER_NAME=kind
readonly KIND_NETWORK=kind
readonly KIND_NODE_IMAGE=kindest/node:v1.32.5
readonly HOSTS_MARKER='# k8s-altinity-click'
readonly HOSTS_NAMES='app.kind.cluster grafana.kind.cluster alertmanager.kind.cluster agent.kind.cluster single.kind.cluster'
readonly LB_IP_ATTEMPTS=60
readonly LB_IP_INTERVAL=2

# FUNCTIONS

log(){
  echo "---------------------------------------------------------------------------------------"
  echo "$*"
  echo "---------------------------------------------------------------------------------------"
}

require(){
  local CMD
  for CMD in "$@"; do
    if ! command -v "$CMD" >/dev/null 2>&1
    then
      echo "Required command not found: $CMD" >&2
      exit 1
    fi
  done
}

wait_ready(){
  local NAME=${1:-pods}
  local TIMEOUT=${2:-5m}
  local SELECTOR=${3:---all}

  log "WAIT $NAME ($TIMEOUT) ..."

  kubectl wait -A --timeout="$TIMEOUT" --for=condition=ready "$NAME" "$SELECTOR"
}

wait_pods_ready(){
  local TIMEOUT=${1:-5m}

  wait_ready pods "$TIMEOUT" --field-selector=status.phase!=Succeeded
}

wait_nodes_ready(){
  local TIMEOUT=${1:-5m}

  wait_ready nodes "$TIMEOUT" --all
}

network(){
  local NAME=${1:-$KIND_NETWORK}

  log "NETWORK ($NAME) ..."

  if [ -z "$(docker network ls --filter "name=^${NAME}$" --format '{{ .Name }}')" ]
  then
    docker network create --ipv6=false "$NAME"
    echo "Network $NAME created"
  else
    echo "Network $NAME already exists, skipping"
  fi
}

proxy(){
  local NAME=$1
  local TARGET=$2

  if [ -z "$(docker ps --filter "name=^${NAME}$" --format '{{ .Names }}')" ]
  then
    docker run -d --name "$NAME" --restart=always --net="$KIND_NETWORK" \
      -e REGISTRY_PROXY_REMOTEURL="$TARGET" registry:2
    echo "Proxy $NAME (-> $TARGET) created"
  else
    echo "Proxy $NAME already exists, skipping"
  fi
}

proxies(){
  log "REGISTRY PROXIES ..."

  proxy proxy-docker-hub https://registry-1.docker.io
  proxy proxy-quay       https://quay.io
  proxy proxy-gcr        https://gcr.io
  proxy proxy-k8s-gcr    https://k8s.gcr.io
  proxy proxy-ghcr       https://ghcr.io
  proxy proxy-kube       https://registry.k8s.io
}

get_service_lb_ip(){
  kubectl get svc -n "$1" "$2" -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
}

get_subnet(){
  docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' "$1"
}

subnet_to_ip(){
  local SUBNET=${1:?subnet required}
  local HOST=${2:?host octets required}
  local NETWORK=${SUBNET%/*}
  local PREFIX=${SUBNET#*/}

  if [ "$PREFIX" -ne 16 ]
  then
    echo "Unsupported subnet prefix /$PREFIX (expected /16): $SUBNET" >&2
    return 1
  fi

  echo "${NETWORK%.0.0}.${HOST}"
}

cluster(){
  local NAME=${1:-$KIND_CLUSTER_NAME}

  log "CLUSTER ..."

  docker pull "$KIND_NODE_IMAGE"

  kind create cluster --name "$NAME" --image "$KIND_NODE_IMAGE" --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
kubeadmConfigPatches:
  - |-
    kind: ClusterConfiguration
    controllerManager:
      extraArgs:
        bind-address: 0.0.0.0
    etcd:
      local:
        extraArgs:
          listen-metrics-urls: http://0.0.0.0:2381
    scheduler:
      extraArgs:
        bind-address: 0.0.0.0
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["http://proxy-docker-hub:5000"]
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
      endpoint = ["http://proxy-quay:5000"]
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."k8s.gcr.io"]
      endpoint = ["http://proxy-k8s-gcr:5000"]
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."gcr.io"]
      endpoint = ["http://proxy-gcr:5000"]
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
      endpoint = ["http://proxy-ghcr:5000"]
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
      endpoint = ["http://proxy-kube:5000"]
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
  - role: worker
EOF
}

metallb(){
  log "METALLB ..."

  local KIND_SUBNET
  local METALLB_START
  local METALLB_END

  KIND_SUBNET=$(get_subnet "$KIND_NETWORK")
  METALLB_START=$(subnet_to_ip "$KIND_SUBNET" 255.200)
  METALLB_END=$(subnet_to_ip "$KIND_SUBNET" 255.250)

  helm upgrade --install --wait --timeout 35m --atomic --namespace metallb-system --create-namespace \
    --repo https://metallb.github.io/metallb metallb metallb --values - <<EOF
frrk8s:
  enabled: false
EOF

  kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - $METALLB_START-$METALLB_END
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: layer2
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF
}

prometheus_crd(){
  kubectl create namespace victoria-metrics || true

  helm upgrade --install --wait --timeout 35m --atomic --namespace victoria-metrics \
  --repo https://prometheus-community.github.io/helm-charts prometheus-crd prometheus-operator-crds
}

ingress(){
  log "INGRESS-NGINX ..."

  helm upgrade --install --wait --timeout 35m --atomic --namespace ingress-nginx --create-namespace \
    --repo https://kubernetes.github.io/ingress-nginx ingress-nginx ingress-nginx --values - <<EOF
controller:
  extraArgs:
    update-status: "true"
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
    prometheusRule:
      enabled: true
      rules:
        - alert: NGINXConfigFailed
          expr: count(nginx_ingress_controller_config_last_reload_successful == 0) > 0
          for: 1s
          labels:
            severity: critical
          annotations:
            description: bad ingress config - nginx config test failed
            summary: uninstall the latest ingress changes to allow config reloads to resume
        - alert: NGINXCertificateExpiry
          expr: (avg(nginx_ingress_controller_ssl_expire_time_seconds{host!="_"}) by (host) - time()) < 604800
          for: 1s
          labels:
            severity: critical
          annotations:
            description: ssl certificate(s) will expire in less then a week
            summary: renew expiring certificates to avoid downtime
        - alert: NGINXTooMany500s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"5.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 5XXs
            summary: More than 5% of all requests returned 5XX, this requires your attention
        - alert: NGINXTooMany400s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"4.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 4XXs
            summary: More than 5% of all requests returned 4XX, this requires your attention
EOF
}

dnsmasq(){
  log "Hosts ..."

  local INGRESS_LB_IP=""
  local ATTEMPT

  for ATTEMPT in $(seq 1 "$LB_IP_ATTEMPTS")
  do
    INGRESS_LB_IP=$(get_service_lb_ip ingress-nginx ingress-nginx-controller)
    if [ -n "$INGRESS_LB_IP" ]
    then
      break
    fi
    sleep "$LB_IP_INTERVAL"
  done

  if [ -z "$INGRESS_LB_IP" ]
  then
    echo "Could not determine ingress-nginx LoadBalancer IP" >&2
    return 1
  fi

  sudo sed -i "\|${HOSTS_MARKER}|d" /etc/hosts
  echo "$INGRESS_LB_IP $HOSTS_NAMES $HOSTS_MARKER" | sudo tee -a /etc/hosts
}

cleanup(){
  log "CLEANUP ..."
  sudo sed -i "\|${HOSTS_MARKER}|d" /etc/hosts
  kind delete cluster --name "$KIND_CLUSTER_NAME" || true
}

# RUN

require docker kubectl kind helm

cleanup
network
proxies
cluster
wait_nodes_ready
metallb
prometheus_crd
ingress
wait_pods_ready
dnsmasq

# DONE
log "CLUSTER READY !"
