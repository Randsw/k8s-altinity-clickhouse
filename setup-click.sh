#!/usr/bin/env bash

set -e

helm upgrade --install --wait --timeout 35m --atomic --namespace clickhouse --create-namespace  \
  --repo https://helm.altinity.com clickhouse-operator altinity-clickhouse-operator --values - <<EOF
serviceMonitor:
  enabled: true
dashboards:
  enabled: true
  additionalLabels:
    grafana_dashboard: "1"
configs:
  files:
    config.yaml:
      watch:
        namespaces:
          include: [".*"]
EOF

kubectl create namespace app || true

#Secret for GO application
kubectl create secret generic click-credentials \
  --from-literal=db-password="cart_secure_password_123" \
  --namespace=app

#Secret for Clickhouse installation
kubectl create secret generic clickhouse-users-passwords \
  --from-literal=cart_user=$(echo -n "cart_secure_password_123" | sha256sum | awk '{print $1}') \
  --namespace=app


cat << EOF | kubectl apply -f -
apiVersion: clickhouse-keeper.altinity.com/v1
kind: ClickHouseKeeperInstallation
metadata:
  name: keeper-cluster
  namespace: app
spec:
  configuration:
    settings:
      prometheus/endpoint: /metrics
      prometheus/port: 7000
      prometheus/metrics: true
      prometheus/events: true
      prometheus/asynchronous_metrics: true
    clusters:
      - name: "keeper"
        layout:
          replicasCount: 3
  defaults:
    templates:
      podTemplate: keeper-pod
      volumeClaimTemplate: keeper-storage
  templates:
    podTemplates:
      - name: keeper-pod
        metadata:
          labels:
            app: clickhouse-keeper
          annotations:
            prometheus.io/port: "7000"
            prometheus.io/scrape: "true"
        spec:
          containers:
            - name: clickhouse-keeper
              image: altinity/clickhouse-keeper:25.8.16.10002.altinitystable
              ports:
                - name: chk-metrics
                  containerPort: 7000 
    volumeClaimTemplates:
      - name: keeper-storage
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
EOF

cat << EOF | kubectl apply -f -
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMPodScrape
metadata:
  name: clickhouse-keeper-metrics
  namespace: app
  labels:
    app.kubernetes.io/part-of: vm-operator
    app.kubernetes.io/instance: vm-pod-scrape
spec:
  selector:
    matchLabels:
      app: clickhouse-keeper
  podMetricsEndpoints:
    - port: chk-metrics
      relabelConfigs:
        - sourceLabels: [__meta_kubernetes_namespace]
          targetLabel: namespace
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: pod_name
        - sourceLabels: [__meta_kubernetes_pod_container_name]
          targetLabel: container_name
EOF

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: "ConfigMap"
metadata:
  name: "bootstrap-mounted-configmap"
  namespace: app
data:
  01_create_databases.sh: |
    #!/bin/bash
    set -e
    clickhouse client -n <<-EOSQL
      CREATE DATABASE IF NOT EXISTS cart;
    EOSQL
EOF

cat << EOF | kubectl apply -f -
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: cart-clickhouse-cluster
  namespace: app
spec:
  defaults:
    templates:
      podTemplate: clickhouse-pod-template
      dataVolumeClaimTemplate: clickhouse-storage
  configuration:
    settings:
      prometheus/endpoint: /metrics
      prometheus/port: 9363
      prometheus/metrics: true
      prometheus/events: true
      prometheus/asynchronous_metrics: true
      prometheus/status_info: true
    zookeeper:
      keeper:
        name: keeper-cluster
    users:
      cart_user/password_sha256_hex:
        valueFrom:
          secretKeyRef:
            name: clickhouse-users-passwords
            key: cart_user
      cart_user/networks/ip:
        - "::/0"
        - "0.0.0.0/0"
      cart_user/profile: default
      cart_user/quota: default
      cart_user/grants/query:
          - "GRANT ALL ON cart.*"
    clusters:
      - name: "cart-shop"
        layout:
          shardsCount: 1
          replicasCount: 3
        templates:
          podTemplate: clickhouse-pod-template
  templates:
    podTemplates:
      - name: clickhouse-pod-template
        metadata:
          labels:
            app: clickhouse
          annotations:
            prometheus.io/port: "9363"
            prometheus.io/scrape: "true"
        spec:
          containers:
            - name: clickhouse-server
              image: altinity/clickhouse-server:25.8.16.10002.altinitystable
              ports:
                - name: "metrics"
                  containerPort: 9363
              volumeMounts:
                - name: bootstrap-configmap-volume
                  mountPath: /docker-entrypoint-initdb.d
          volumes:
            - name: bootstrap-configmap-volume
              configMap:
                name: bootstrap-mounted-configmap
    volumeClaimTemplates:
      - name: clickhouse-storage
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
EOF

cat << EOF | kubectl apply -f -
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMPodScrape
metadata:
  name: clickhouse-metrics
  namespace: app
  labels:
    app.kubernetes.io/part-of: vm-operator
    app.kubernetes.io/instance: vm-pod-scrape
spec:
  selector:
    matchLabels:
      app: clickhouse
  podMetricsEndpoints:
    - port: metrics
      relabelConfigs:
        - sourceLabels: [__meta_kubernetes_namespace]
          targetLabel: namespace
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: pod_name
        - sourceLabels: [__meta_kubernetes_pod_container_name]
          targetLabel: container_name
EOF