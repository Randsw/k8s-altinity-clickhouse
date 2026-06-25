# k8s-altinity-click

## Overview

This repository provides a complete, production-ready blueprint for deploying a **ClickHouse cluster** on a Kubernetes environment using the **Altinity ClickHouse Operator**.

To ensure complete observability, the project includes a fully configured **VictoriaMetrics stack** (Grafana + VictoriaMetrics Operator) tailored to monitor ClickHouse performance metrics out of the box.

### Architecture Quick Look

* **Infrastructure**: 1 Control Plane + 3 Worker nodes (Kind) with MetalLB for LoadBalancer support.
* **Storage & Coordination**: ClickHouse Keeper for replication management.
* **Database**: 1 Shard × 3 Replicas setup with a pre-configured `cart` database and dedicated user permissions.
* **App Layer**: A minimal Go client to generate, display, and aggregate mock data.

---

## Prerequisites

Ensure the following tools are installed and updated:

* **Docker** (Engine or Desktop)
* **kubectl**
* **Kind CLI**
* **Helm** (v3.x+)

---

## Getting Started & Deployment

### 1. Provision the Kubernetes Infrastructure

Initialize your local multi-node cluster. This script creates the nodes, sets up a local Docker registry integration, and configures MetalLB for external IP routing.

```bash
./cluster-setup.sh
```

### 2. Deploy the VictoriaMetrics Stack & Grafana

Install the monitoring infrastructure, including cluster-wide Kubernetes dashboards and multi-cluster viewing support.

```bash
./setup-vms.sh
```

#### Accessing Grafana

The default login username is `admin`. Retrieve your auto-generated password by running:

```bash
kubectl get secret --namespace victoria-metrics vm-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

### 3. Deploy Altinity ClickHouse Operator & Cluster

Deploy the operator, spin up the `ClickHouseKeeperInstallation` for coordination, and initialize the ClickHouse cluster (1 shard, 3 replicas). This step also auto-provisions the `cart` database and `cart-user`.

```bash
./setup-click.sh
```

### 4. Launch the Example Go Application

Deploy the application workloads (Deployment, Service, and Ingress resources) to test end-to-end database connectivity.

```bash
kubectl apply -f ./k8s/
```

---

## Verifying the Setup

Once all pods are running, you can interact with the Go application via your browser using the following endpoints:

* **Seed Data**: `http://app.kind.cluster/generate`  
  *Initializes the target ClickHouse tables and populates them with sample data.*
* **View Data**: `http://app.kind.cluster/show`  
  *Fetches and prints raw rows directly from the ClickHouse cluster.*
* **Aggregate Data**: `http://app.kind.cluster/calc`  
  *Executes an analytical aggregation query over the generated dataset.*

---

## Project Structure

* `/app` - Minimal Go client source code and Dockerfile.
* `app/k8s` - Kubernetes manifests for the application layer (Deployment, Service, Ingress).
* `cluster-setup.sh` - Kind cluster bootstrap and network setup automation.
* `setup-vms.sh` - Helm charts and configuration for VictoriaMetrics/Grafana.
* `setup-click.sh` - Altinity Operator, Keeper, and ClickHouse Custom Resources.

---

## Contributing

Contributions are highly welcome! Feel free to open issues or submit pull requests. Areas for expansion include:

* Introducing realistic, high-throughput data workloads.
* Adding custom Grafana dashboards for deep ClickHouse engine metrics.
* Expanding operator configurations (e.g., advanced storage classes, volume templates).

## License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.
