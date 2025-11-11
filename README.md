# Ansible Labs

This directory contains hands-on labs for learning Ansible by building real-world infrastructure automation.

## Labs Overview

### Lab 1: PostgreSQL Cluster (`postgres-cluster/`)

Production-ready PostgreSQL 16 cluster with streaming replication (1 primary + 2 standby nodes).

**Quick Start:**
```bash
cd postgres-cluster
ee/setup.sh init && ee/setup.sh vpn
ee/ansible.sh inventory && ee/ansible.sh test
make deploy
```

See [postgres-cluster/README.md](postgres-cluster/README.md) for details.

### Lab 2: Kubernetes Cluster (`kubernetes-cluster/`)

Production-ready Kubernetes cluster using Kubespray (1 master + 2 worker nodes).

**Quick Start (Automated):**
```bash
cd kubernetes-cluster
make auto
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

**Quick Start (Manual):**
```bash
cd kubernetes-cluster
make init && make vpn && make ssh && make inventory
make install && make kubespray && make deploy
make kubeconfig
```

See [kubernetes-cluster/README.md](kubernetes-cluster/README.md) for details.
