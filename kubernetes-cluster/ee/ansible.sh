#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
cd "$SCRIPT_DIR"
ENV_FILE="$SCRIPT_DIR/.env"

set -eo pipefail

load_env() {
    [ -f "$ENV_FILE" ] || { echo "❌ .env not found. Run 'ee/setup.sh init' first"; exit 1; }
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
}

check_active() {
    load_env
    local status=$(ee describe ws "$WS" --json 2>&1 | jq -r '.status // .state // "unknown"')
    [[ "$status" =~ ^(running|active)$ ]] || { echo "❌ Workspace not active"; exit 1; }
}

# ─────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────

cmd_ssh() {
    check_active
    echo "🔑 Setting up SSH access to all nodes..."

    grep "^BOX_" "$ENV_FILE" | while IFS= read -r line; do
        name=$(echo "$line" | cut -d= -f1 | sed 's/BOX_//' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        id=$(echo "$line" | cut -d= -f2)
        [ -z "$id" ] && continue
        echo "  Setting up SSH for: $name"
        ee box ssh-copy-id "$WS" "$id"
    done

    echo "✅ SSH configured for all nodes"
    echo "Next: ee/ansible.sh inventory"
}

cmd_inventory() {
    check_active
    mkdir -p ../inventory

    echo "📝 Generating Ansible inventory..."

    # Generate basic inventory
    {
        echo "[all]"
        grep "^HOSTNAME_" "$ENV_FILE" 2>/dev/null | while IFS= read -r line; do
            name=$(echo "$line" | cut -d= -f1 | sed 's/HOSTNAME_//' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
            host=$(echo "$line" | cut -d= -f2)
            [ -n "${host:-}" ] && echo "$name ansible_host=$host"
        done || true

        echo
        echo "[all:vars]"
        echo "ansible_user=easyenv"
        echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
        echo "ansible_python_interpreter=/usr/bin/python3"
    } > ../inventory/hosts.ini

    # Auto-detect Kubernetes cluster setup
    local master_count=$(grep "^HOSTNAME_K8S_MASTER" "$ENV_FILE" 2>/dev/null | wc -l)
    local worker_count=$(grep "^HOSTNAME_K8S_WORKER" "$ENV_FILE" 2>/dev/null | wc -l)

    if [ "$master_count" -ge 1 ] || [ "$worker_count" -ge 1 ]; then
        echo
        echo "📦 Detected Kubernetes cluster setup, adding groups..."
        {
            echo
            echo "# Kubernetes Cluster Groups"
            echo "[kube_master]"
            grep "^HOSTNAME_K8S_MASTER" "$ENV_FILE" 2>/dev/null | while IFS= read -r line; do
                name=$(echo "$line" | cut -d= -f1 | sed 's/HOSTNAME_//' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
                echo "$name"
            done || true
            echo
            echo "[kube_workers]"
            grep "^HOSTNAME_K8S_WORKER" "$ENV_FILE" 2>/dev/null | while IFS= read -r line; do
                name=$(echo "$line" | cut -d= -f1 | sed 's/HOSTNAME_//' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
                echo "$name"
            done || true
            echo
            echo "[kubernetes:children]"
            echo "kube_master"
            echo "kube_workers"
        } >> ../inventory/hosts.ini
        echo "   ✓ Added Kubernetes cluster groups"
    fi

    echo "✅ Inventory: inventory/hosts.ini"
    echo "   Edit to customize groups if needed"
    echo
    echo "Next: ee/ansible.sh test"
}

cmd_test() {
    check_active
    [ -f "../inventory/hosts.ini" ] || { echo "❌ Run 'ee/ansible.sh inventory' first"; exit 1; }

    command -v ansible &>/dev/null || { echo "❌ Install Ansible first"; exit 1; }

    echo "📡 Testing connectivity..."
    cd ..
    if ansible all -i inventory/hosts.ini -m ping -o; then
        echo
        echo "✅ All nodes reachable"
        echo
        echo "Setup Kubespray:"
        echo "  make kubespray"
        echo
        echo "Deploy cluster:"
        echo "  make deploy"
    else
        echo "❌ Connection failed"
        exit 1
    fi
}

cmd_info() {
    check_active
    echo "📊 Ansible Environment"
    echo
    echo "Hosts:"
    grep "^HOSTNAME_" "$ENV_FILE" 2>/dev/null | while IFS= read -r line; do
        name=$(echo "$line" | cut -d= -f1 | sed 's/HOSTNAME_//' | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        host=$(echo "$line" | cut -d= -f2)
        echo "  $name: $host"
    done || true
    echo
    [ -f "../inventory/hosts.ini" ] && echo "✅ Inventory configured" || echo "❌ Inventory not generated"
}

cmd_help() {
    echo "Usage: ee/ansible.sh COMMAND"
    echo
    echo "Commands:"
    echo "  ssh         Setup SSH access to all nodes"
    echo "  inventory   Generate Ansible inventory file"
    echo "  test        Test connectivity to all nodes"
    echo "  info        Show ansible environment info"
    echo
    echo "Workflow:"
    echo "  ee/setup.sh init && ee/setup.sh vpn"
    echo "  ee/ansible.sh ssh && ee/ansible.sh inventory && ee/ansible.sh test"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

case "${1:-}" in
    ssh)       cmd_ssh ;;
    inventory) cmd_inventory ;;
    test)      cmd_test ;;
    info)      cmd_info ;;
    *)         cmd_help; exit 1 ;;
esac

