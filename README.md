# k8s-altinity-click

## Overview

This repository shows how to **deploy a ClickHouse cluster** on a local Kubernetes cluster using **Kind** and the **Altinity ClickHouse Operator**. It also includes a **VictoriaMetrics stack** for monitoring ClickHouse metrics. The focus is on the Kubernetes resources and operator configuration; the example Go application is provided only as a minimal client.

## Prerequisites

Ensure the following are installed and updated for 2026:

- **Docker** (Engine or Desktop)
- **kubectl**
- **Kind CLI**
- **Helm** (v3.x+)

---

## Deploy

### 1. Cluster Infrastructure Setup

Initialize the environment by running the setup script. This creates a multi-node cluster (1 Control Plane, 3 Workers) pre-configured with MetaLB (LoadBalancer support) and local image registries.

```bash
./cluster-setup.sh
```

### 2. Deploy VictoriaMetrics Kubernetes stack with Grafana

Run `./setup-vms.sh`

#### Get grafana password

Login - admin

Password:

`kubectl get secret --namespace victoria-metrics vm-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo`

### 3. Deploy Altinity ClickHouse Operator

Run `./setup-click.sh`

### 4. Run example application

The repository also contains a minimal Go client (`app/`) that can be used to verify connectivity, but the primary purpose of this project is the Kubernetes and monitoring setup.

Run `kubectl apply -f ./k8s/`

Open in browser `http://app.kind.cluster/generate`

## Detailed Steps

### 1. Create a Kind Cluster

The `cluster-setup.sh` script wraps Kind commands:

```bash
./cluster-setup.sh    # creates a cluster
```

It also configures the local Docker registry so that the built Go application image can be loaded into Kind without pushing to an external registry.

### 2. Install Victoria Metrics K8s stack

`setup-click.sh` performs the following actions:

1. Installs the Victoria Metrics K8s stack via Helm
2. Install default kubernetes dashboards
3. Enable multicluster dashboards in Grafana

### 3. Install Altinity ClickHouse Operator

`setup-click.sh` performs the following actions:

1. Installs the Altinity ClickHouse Operator via Helm.
2. Applies the `ClickKeeperHouseInstallation` CRD.
3. Creates a `ClickHouseInstallation` resource that defines a ClickHouse cluster with 1 shards and 3 replicas per shard.
4. Create `cart` database and user named `cart-user` with grants on `cart` database

### 4. Example applicattion

Example application consist of:

1. Deployment
2. Service
3. Ingress

Run `http://app.kind.cluster/generate`. This is create table in clickhouse and fill it with example data.
Generated data can be seen at `http://app.kind.cluster/show`.
Run `http://app.kind.cluster/calc` and see aggregated data

## Contributing

Feel free to open issues or submit pull requests. Contributions that add more realistic workloads, improve monitoring, or extend the operator configuration are welcome.

## License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.
