#!/usr/bin/env bash

# Kubespray Deployment Script
# This script automates the entire Kubespray deployment process:
# 1. Clone/update Kubespray
# 2. Generate inventory from EasyEnv hosts
# 3. Deploy Kubernetes cluster
# 4. Fetch kubeconfig
# 5. Validate cluster
# 6. Clean up unnecessary files

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/ee/.env"
KUBESPRAY_DIR="$SCRIPT_DIR/kubespray"
INVENTORY_DIR="$SCRIPT_DIR/inventory/kubespray"
KUBECONFIG_FILE="$SCRIPT_DIR/kubeconfig"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

load_env() {
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found. Run './ee/setup.sh init && ./ee/setup.sh vpn' first."
        exit 1
    fi
    set -a
    source "$ENV_FILE"
    set +a
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=0

    # Check required commands
    for cmd in ansible ansible-playbook git jq ssh; do
        if ! command -v $cmd &>/dev/null; then
            log_error "$cmd not found. Please install it."
            missing=1
        fi
    done

    # Check .env file
    if [ ! -f "$ENV_FILE" ]; then
        log_error ".env file not found."
        missing=1
    fi

    # Check connectivity
    load_env
    local master_host=$(grep "^HOSTNAME_K8S_MASTER_1=" "$ENV_FILE" | cut -d= -f2)
    if [ -z "$master_host" ]; then
        log_error "Master node hostname not found in .env"
        missing=1
    else
        if ! ping -c 1 -W 2 "$master_host" &>/dev/null; then
            log_warning "Cannot ping master node. Make sure VPN is connected."
        fi
    fi

    if [ $missing -eq 1 ]; then
        exit 1
    fi

    log_success "Prerequisites check passed"
}

setup_kubespray() {
    log_info "Setting up Kubespray..."

    if [ -d "$KUBESPRAY_DIR" ]; then
        log_info "Kubespray directory exists, updating..."
        cd "$KUBESPRAY_DIR"
        git fetch origin
        git checkout release-2.29
        git pull
        cd "$SCRIPT_DIR"
    else
        log_info "Cloning Kubespray repository..."
        git clone https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
        cd "$KUBESPRAY_DIR"
        git checkout release-2.29
        cd "$SCRIPT_DIR"
    fi

    log_info "Installing Kubespray requirements..."
    pip install -q -r "$KUBESPRAY_DIR/requirements.txt"

    log_success "Kubespray setup complete"
}

generate_inventory() {
    log_info "Generating Kubespray inventory..."

    load_env

    mkdir -p "$INVENTORY_DIR/group_vars"

    # Extract hostnames from .env
    MASTER_HOST=$(grep "^HOSTNAME_K8S_MASTER_1=" "$ENV_FILE" | cut -d= -f2)
    WORKER1_HOST=$(grep "^HOSTNAME_K8S_WORKER_1=" "$ENV_FILE" | cut -d= -f2)
    WORKER2_HOST=$(grep "^HOSTNAME_K8S_WORKER_2=" "$ENV_FILE" | cut -d= -f2)

    if [ -z "$MASTER_HOST" ] || [ -z "$WORKER1_HOST" ] || [ -z "$WORKER2_HOST" ]; then
        log_error "Could not find all hostnames in .env file"
        exit 1
    fi

    # Create Kubespray inventory file
    cat > "$INVENTORY_DIR/hosts.yaml" <<EOF
all:
  hosts:
    k8s-master-1:
      ansible_host: ${MASTER_HOST}
    k8s-worker-1:
      ansible_host: ${WORKER1_HOST}
    k8s-worker-2:
      ansible_host: ${WORKER2_HOST}
  children:
    kube_control_plane:
      hosts:
        k8s-master-1:
    kube_node:
      hosts:
        k8s-master-1:
        k8s-worker-1:
        k8s-worker-2:
    etcd:
      hosts:
        k8s-master-1:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
  vars:
    ansible_user: easyenv
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    ansible_python_interpreter: /usr/bin/python3
EOF

    # Create k8s-cluster.yml with custom configurations
    cat > "$INVENTORY_DIR/group_vars/k8s_cluster.yml" <<EOF
# Kubernetes cluster configuration
# kube_version: use Kubespray default

# Network plugin
kube_network_plugin: calico
kube_network_plugin_multus: false

# Service and pod network CIDR
kube_service_addresses: 10.233.0.0/18
kube_pods_subnet: 10.233.64.0/18

# DNS
dns_mode: coredns
enable_nodelocaldns: true

# Container runtime
container_manager: containerd

# Enable kubeconfig on master
kubeconfig_localhost: true
kubectl_localhost: true

# Kubernetes dashboard
dashboard_enabled: false

# Ingress controller
ingress_nginx_enabled: false

# MetalLB
metallb_enabled: false

# Helm
helm_enabled: true

# Allow scheduling on master (for small clusters)
kube_control_plane_schedulable: true
EOF

    # Create all.yml with general configurations
    cat > "$INVENTORY_DIR/group_vars/all.yml" <<EOF
# General configuration
upstream_dns_servers:
  - 8.8.8.8
  - 8.8.4.4

# Download settings
download_run_once: true
download_localhost: false

# Certificate settings
certificates_duration: 36500

# Enable kubectl download
kubectl_enabled: true
EOF

    log_success "Inventory generated at: $INVENTORY_DIR/hosts.yaml"
}

deploy_cluster() {
    log_info "Deploying Kubernetes cluster with Kubespray..."
    log_warning "This will take 10-15 minutes. Please be patient..."

    cd "$KUBESPRAY_DIR"

    if ansible-playbook -i "$INVENTORY_DIR/hosts.yaml" \
        --become --become-user=root \
        cluster.yml; then
        log_success "Cluster deployment completed successfully"
    else
        log_error "Cluster deployment failed"
        exit 1
    fi

    cd "$SCRIPT_DIR"
}

fetch_kubeconfig() {
    log_info "Fetching kubeconfig from master node..."

    load_env

    MASTER_HOST=$(grep "^HOSTNAME_K8S_MASTER_1=" "$ENV_FILE" | cut -d= -f2)

    if [ -z "$MASTER_HOST" ]; then
        log_error "Could not find master hostname in .env file"
        exit 1
    fi

    # Try to fetch from /root/.kube/config first
    if ssh -o StrictHostKeyChecking=no easyenv@"$MASTER_HOST" "sudo test -f /root/.kube/config" 2>/dev/null; then
        ssh -o StrictHostKeyChecking=no easyenv@"$MASTER_HOST" "sudo cat /root/.kube/config" > "$KUBECONFIG_FILE"
    elif ssh -o StrictHostKeyChecking=no easyenv@"$MASTER_HOST" "sudo test -f /etc/kubernetes/admin.conf" 2>/dev/null; then
        ssh -o StrictHostKeyChecking=no easyenv@"$MASTER_HOST" "sudo cat /etc/kubernetes/admin.conf" > "$KUBECONFIG_FILE"
    else
        log_error "Could not find kubeconfig on master node"
        exit 1
    fi

    # Replace server address with master hostname
    sed -i "s|server:.*|server: https://${MASTER_HOST}:6443|g" "$KUBECONFIG_FILE"
    chmod 600 "$KUBECONFIG_FILE"

    # Update .env with KUBECONFIG
    grep -q "^KUBECONFIG=" "$ENV_FILE" 2>/dev/null || echo "KUBECONFIG=$KUBECONFIG_FILE" >> "$ENV_FILE"

    log_success "Kubeconfig saved to: $KUBECONFIG_FILE"
}

validate_cluster() {
    log_info "Validating cluster..."

    export KUBECONFIG="$KUBECONFIG_FILE"

    # Check if kubectl can connect
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to cluster"
        exit 1
    fi

    log_success "Cluster is accessible"

    # Wait for nodes to be ready
    log_info "Waiting for nodes to be ready..."
    local max_wait=300
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l)
        if [ "$not_ready" -eq 0 ]; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Still waiting... ($elapsed/${max_wait}s)"
    done

    # Display cluster info
    echo
    log_info "Cluster Info:"
    kubectl cluster-info

    echo
    log_info "Nodes:"
    kubectl get nodes -o wide

    echo
    log_info "System Pods:"
    kubectl get pods -n kube-system

    # Check if all nodes are ready
    local not_ready=$(kubectl get nodes --no-headers | grep -v " Ready" | wc -l)
    if [ "$not_ready" -ne 0 ]; then
        log_warning "Some nodes are not ready yet"
    else
        log_success "All nodes are ready"
    fi

    # Check if all system pods are running
    local not_running=$(kubectl get pods -n kube-system --no-headers | grep -v "Running\|Completed" | wc -l)
    if [ "$not_running" -ne 0 ]; then
        log_warning "Some system pods are not running yet"
    else
        log_success "All system pods are running"
    fi
}

cleanup_files() {
    log_info "Cleaning up Kubespray artifacts..."

    # Clean up Kubespray .git and .vagrant directories
    if [ -d "$KUBESPRAY_DIR" ]; then
        cd "$KUBESPRAY_DIR"
        rm -rf .vagrant .git
        cd "$SCRIPT_DIR"
        log_success "Removed Kubespray .git and .vagrant directories"
    fi

    log_success "Cleanup complete"
}

display_usage_info() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Kubernetes Cluster Deployment Complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "To use the cluster, run:"
    echo "  export KUBECONFIG=$KUBECONFIG_FILE"
    echo
    echo "Then you can use kubectl:"
    echo "  kubectl get nodes"
    echo "  kubectl get pods --all-namespaces"
    echo
    echo "Deploy a sample application:"
    echo "  kubectl create deployment nginx --image=nginx"
    echo "  kubectl expose deployment nginx --port=80 --type=NodePort"
    echo "  kubectl get svc nginx"
    echo
    echo "Helper scripts available:"
    echo "  ./ee/kube.sh info    - Show cluster info"
    echo "  ./ee/kube.sh pods    - List all pods"
    echo "  ./ee/kube.sh ns      - List namespaces"
    echo
    echo "See README.md for more information"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

# ─────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────

main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Kubespray Kubernetes Cluster Deployment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Step 1: Check prerequisites
    check_prerequisites
    echo

    # Step 2: Setup Kubespray
    setup_kubespray
    echo

    # Step 3: Generate inventory
    generate_inventory
    echo

    # Step 4: Deploy cluster
    deploy_cluster
    echo

    # Step 5: Fetch kubeconfig
    fetch_kubeconfig
    echo

    # Step 6: Validate cluster
    validate_cluster
    echo

    # Step 7: Cleanup Kubespray artifacts
    read -p "Clean up Kubespray .git/.vagrant directories to save space? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup_files
        echo
    fi

    # Display usage information
    display_usage_info
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Automated Kubespray deployment script"
        echo
        echo "Steps performed:"
        echo "  1. Check prerequisites"
        echo "  2. Clone/update Kubespray"
        echo "  3. Generate inventory from .env"
        echo "  4. Deploy Kubernetes cluster"
        echo "  5. Fetch kubeconfig from master"
        echo "  6. Validate cluster"
        echo "  7. Clean up Kubespray artifacts (optional)"
        echo
        echo "Prerequisites:"
        echo "  - Run './ee/setup.sh init && ./ee/setup.sh vpn' first"
        echo "  - Ensure SSH access is configured"
        echo "  - Install Python requirements: pip install -r requirements.txt"
        echo
        exit 0
        ;;
    *)
        main
        ;;
esac

