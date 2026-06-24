#!/usr/bin/env bash

set -e

cat << EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: vms-datasource
  namespace: victoria-metrics
  labels:
    grafana_datasource: "1"
    namespace: victoria-metrics
data:
  vms-datasource.yaml: |-
    apiVersion: 1
    datasources:
      - name: prometheus
        type: prometheus
        access: proxy
        url: http://vmsingle-vm-victoria-metrics-k8s-stack.victoria-metrics:8428
        isDefault: false
        editable: true
        orgId: 1
        uid: prometheus
EOF

helm upgrade --install --wait --timeout 35m --atomic --namespace victoria-metrics --create-namespace  \
  --repo https://victoriametrics.github.io/helm-charts vm victoria-metrics-k8s-stack --values - <<EOF
victoria-metrics-operator:
  createCRD: true
vmsingle:
  enabled: true
  ingress:
    enabled: true
    hosts:
      - single.kind.cluster
    ingressClassName: nginx
vmagent:
  spec:
    externalLabels:
      cluster: "mycluster"
  ingress:
    enabled: true
    hosts:
      - agent.kind.cluster
    ingressClassName: nginx
alertmanager:
  enabled: true
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - alertmanager.kind.cluster
grafana:
  enabled: true
  sidecar:
    datasources:
      enabled: true
      searchNamespace: ALL
    dashboards:
      enabled: true
      searchNamespace: ALL
    provider:
      allowUiUpdates: true
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
        - grafana.kind.cluster
  plugins:
    - victoriametrics-metrics-datasource
  serviceMonitor:
    enabled: true
    relabelings:
      - targetLabel: cluster
        replacement: mycluster
kubeEtcd:
  enabled: true
  service:
    # -- Enable service for ETCD metrics scraping
    enabled: true
    # -- ETCD service port
    port: 2381
    # -- ETCD service target port
    targetPort: 2381
    # -- ETCD service pods selector
    selector:
      component: etcd
  vmScrape:
    enabled: true
    # spec for VMServiceScrape crd 
    # https://github.com/VictoriaMetrics/operator/blob/master/docs/api.MD#vmservicescrapespec
    spec:
      jobLabel: jobLabel
      endpoints:
        - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
          # bearerTokenSecret:
          #   key: ""
          port: http-metrics
          scheme: http
          tlsConfig:
            caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            insecureSkipVerify: true
kubeScheduler:
  enabled: true
  vmScrape:
    enabled: true
    # spec for VMServiceScrape crd 
    # https://github.com/VictoriaMetrics/operator/blob/master/docs/api.MD#vmservicescrapespec
    spec:
      jobLabel: app.kubernetes.io/component
      endpoints:
        - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
          # bearerTokenSecret:
          #   key: ""
          port: http-metrics
          scheme: https
          tlsConfig:
            caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            insecureSkipVerify: true
kubeControllerManager:
  enabled: true
  vmScrape:
    enabled: true
    # spec for VMServiceScrape crd 
    # https://github.com/VictoriaMetrics/operator/blob/master/docs/api.MD#vmservicescrapespec
    spec:
      jobLabel: app.kubernetes.io/component
      endpoints:
        - bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
          # bearerTokenSecret:
          #   key: ""
          port: http-metrics
          scheme: https
          tlsConfig:
            caFile: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            insecureSkipVerify: true
            serverName: kubernetes
EOF
