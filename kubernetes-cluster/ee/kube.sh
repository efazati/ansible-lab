#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
cd "$SCRIPT_DIR"
ENV_FILE="$SCRIPT_DIR/.env"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig"

set -eo pipefail

load_env() {
    [ -f "$ENV_FILE" ] || { echo "❌ .env not found. Run 'ee/setup.sh init' first"; exit 1; }
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
}

check_kubectl() {
    [ -f "$KUBECONFIG_FILE" ] || { echo "❌ Kubeconfig not found. Run: ee/kube.sh fetch"; exit 1; }
    export KUBECONFIG="$KUBECONFIG_FILE"
    kubectl cluster-info &>/dev/null || { echo "❌ Cannot connect to cluster"; exit 1; }
}

# ─────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────

cmd_fetch() {
    load_env

    local master_host=$(grep "^HOSTNAME_K8S_MASTER_1=" "$ENV_FILE" | cut -d= -f2)
    [ -z "$master_host" ] && { echo "❌ Master node hostname not found"; exit 1; }

    echo "📥 Fetching kubeconfig from $master_host..."

    # Try to fetch from /root/.kube/config first
    if ssh -o StrictHostKeyChecking=no easyenv@"$master_host" "sudo test -f /root/.kube/config" 2>/dev/null; then
        ssh -o StrictHostKeyChecking=no easyenv@"$master_host" "sudo cat /root/.kube/config" > "$KUBECONFIG_FILE"
        echo "✅ Kubeconfig saved to: $KUBECONFIG_FILE"
    elif ssh -o StrictHostKeyChecking=no easyenv@"$master_host" "sudo test -f /etc/kubernetes/admin.conf" 2>/dev/null; then
        ssh -o StrictHostKeyChecking=no easyenv@"$master_host" "sudo cat /etc/kubernetes/admin.conf" > "$KUBECONFIG_FILE"
        echo "✅ Kubeconfig saved to: $KUBECONFIG_FILE"
    else
        echo "❌ Could not find kubeconfig on master node"
        echo "   Make sure Kubernetes is deployed: make deploy"
        exit 1
    fi

    # Replace server address with master hostname
    sed -i "s|server:.*|server: https://${master_host}:6443|g" "$KUBECONFIG_FILE"
    chmod 600 "$KUBECONFIG_FILE"

    # Update .env with KUBECONFIG
    grep -q "^KUBECONFIG=" "$ENV_FILE" 2>/dev/null || echo "KUBECONFIG=$KUBECONFIG_FILE" >> "$ENV_FILE"

    export KUBECONFIG="$KUBECONFIG_FILE"
    echo
    echo "To use kubectl, run:"
    echo "  export KUBECONFIG=$KUBECONFIG_FILE"
    echo
    kubectl get nodes 2>/dev/null || echo "⚠️  Cluster not ready yet"
}

cmd_info() {
    load_env
    check_kubectl

    echo "📊 Kubernetes Cluster Info"
    echo
    echo "Cluster:"
    kubectl cluster-info | head -2
    echo
    echo "Nodes:"
    kubectl get nodes -o wide
    echo
    echo "System Pods:"
    kubectl get pods -n kube-system
    echo
    echo "Kubeconfig: $KUBECONFIG"
}

cmd_ns() {
    load_env
    check_kubectl

    if [ -n "${1:-}" ]; then
        echo "🔄 Switching to namespace: $1"
        kubectl config set-context --current --namespace="$1"
    else
        echo "📋 Namespaces:"
        kubectl get namespaces
        echo
        local current_ns=$(kubectl config view --minify --output 'jsonpath={..namespace}')
        echo "Current: ${current_ns:-default}"
        echo
        echo "Switch: ee/kube.sh ns <namespace>"
    fi
}

cmd_pods() {
    load_env
    check_kubectl

    local ns="${1:-}"
    if [ -n "$ns" ]; then
        kubectl get pods -n "$ns" -o wide
    else
        kubectl get pods --all-namespaces -o wide
    fi
}

cmd_deploy() {
    load_env
    check_kubectl

    local file="${1:-}"
    if [ -z "$file" ]; then
        echo "Usage: ee/kube.sh deploy <file.yaml>"
        exit 1
    fi

    echo "🚀 Deploying: $file"
    kubectl apply -f "$file"
}

cmd_logs() {
    load_env
    check_kubectl

    local pod="${1:-}"
    local ns="${2:-default}"

    if [ -z "$pod" ]; then
        echo "Usage: ee/kube.sh logs <pod-name> [namespace]"
        exit 1
    fi

    echo "📜 Logs for pod: $pod (namespace: $ns)"
    kubectl logs -n "$ns" "$pod" --tail=100 -f
}

cmd_help() {
    echo "Usage: ee/kube.sh COMMAND [args]"
    echo
    echo "Setup:"
    echo "  fetch           Fetch kubeconfig from master node"
    echo
    echo "Info Commands:"
    echo "  info            Show cluster and node info"
    echo "  ns [name]       List namespaces or switch to one"
    echo "  pods [ns]       List pods (all namespaces or specific)"
    echo
    echo "Management:"
    echo "  deploy <file>   Deploy a YAML file"
    echo "  logs <pod> [ns] View pod logs"
    echo
    echo "Examples:"
    echo "  ee/kube.sh fetch"
    echo "  ee/kube.sh info"
    echo "  ee/kube.sh ns kube-system"
    echo "  ee/kube.sh pods kube-system"
    echo "  ee/kube.sh deploy app.yaml"
    echo "  ee/kube.sh logs my-pod default"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

case "${1:-}" in
    fetch)   cmd_fetch ;;
    info)    cmd_info ;;
    ns)      cmd_ns "${2:-}" ;;
    pods)    cmd_pods "${2:-}" ;;
    deploy)  cmd_deploy "${2:-}" ;;
    logs)    cmd_logs "${2:-}" "${3:-default}" ;;
    *)       cmd_help; exit 1 ;;
esac

