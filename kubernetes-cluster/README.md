# Kubernetes Cluster with Kubespray

Production-ready K8s cluster on 3 Ubuntu 24.04 nodes via Kubespray.

## Architecture

- **k8s-master-1**: Control plane + schedulable
- **k8s-worker-1**: Worker node
- **k8s-worker-2**: Worker node

## Quick Start

### Automated (Recommended)

```bash
make auto && export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

### Manual

```bash
# Setup
make init vpn ssh inventory ansible

# Install & Deploy
make install kubespray deploy kubeconfig

# Use
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

## Configuration

Edit before deployment:

```bash
# Kubernetes settings
inventory/kubespray/group_vars/k8s_cluster.yml

# General settings
inventory/kubespray/group_vars/all.yml
```

Key toggles in `k8s_cluster.yml`:
```yaml
kube_version: v1.30.8
kube_network_plugin: calico
dashboard_enabled: false        # Set true to enable
ingress_nginx_enabled: false    # Set true to enable
metallb_enabled: false          # Set true for LoadBalancer
helm_enabled: true
kube_control_plane_schedulable: true
```

## Commands

### Setup
```bash
make init          # Create 3 VMs
make vpn           # Connect VPN
make ssh           # Setup SSH
make inventory     # Generate inventory
make ansible       # Test connectivity
```

### Deployment
```bash
make install       # Install dependencies
make kubespray     # Clone Kubespray
make deploy        # Deploy cluster (10-15 min)
make kubeconfig    # Fetch kubeconfig
make verify        # Verify health
```

### Management
```bash
make status        # Workspace status
make reset         # Reset cluster
make clean         # Cleanup workspace
```

### Helper Scripts
```bash
./kubespray.sh            # One-script deployment
./ee/kube.sh info         # Cluster info
./ee/kube.sh pods         # List pods
./ee/kube.sh ns <name>    # Switch namespace
./ee/ansible.sh test      # Test connectivity
```

## Deploy Sample App

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx
```

Or use example:
```bash
kubectl apply -f examples/nginx-deployment.yaml
kubectl get all -n demo
```

## Troubleshooting

### Can't connect to cluster
```bash
make kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig
```

### Nodes not ready
```bash
ssh easyenv@$(grep HOSTNAME_K8S_MASTER_1 .env | cut -d= -f2)
sudo journalctl -u kubelet -f
```

### Reset and redeploy
```bash
make reset
make deploy
```

### Check logs
```bash
kubectl logs -n kube-system -l k8s-app=calico-node
kubectl logs -n kube-system -l k8s-app=kube-dns
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

## Scale Cluster

Add node to `ee/conf.yml`:
```yaml
boxes:
  - title: "k8s-worker-3"
    recipe_title: "Ubuntu 24.04 LTS"
```

Then:
```bash
make init vpn
./ee/ansible.sh inventory
# Update inventory/kubespray/hosts.yaml with new node
cd kubespray && ansible-playbook -i ../inventory/kubespray/hosts.yaml scale.yml
```
