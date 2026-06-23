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
    clusters:
      - name: "keeper"
        layout:
          replicasCount: 3
  templates:
    podTemplates:
      - name: keeper-pod
        spec:
          containers:
            - name: clickhouse-keeper
              image: altinity/clickhouse-keeper:25.8.16.10002.altinitystable
    volumeClaimTemplates:
      - name: keeper-data-template
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi # Хранилище для логов координатора
EOF

cat << EOF | kubectl apply -f -
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: cart-clickhouse-cluster
  namespace: app
spec:
  configuration:
    zookeeper:
      keeper:
        name: keeper-cluster
    users:
      cart_user:
        password_sha256_hex:
          valueFrom:
            secretKeyRef:
              name: clickhouse-users-passwords
              key: cart_user
        networks:
          ip: "::/0"
        profile: default
        quota: default
        grants:
          - "GRANT ALL ON cart.*"
    databases:
      - name: cart
    clusters:
      - name: "cart_shop_cluster"
        layout:
          shardsCount: 1
          replicasCount: 3
  templates:
    podTemplates:
      - name: clickhouse-pod
        spec:
          containers:
            - name: clickhouse-server
              image: altinity/clickhouse-server:25.8.16.10002.altinitystable
    volumeClaimTemplates:
      - name: clickhouse-data
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
EOF