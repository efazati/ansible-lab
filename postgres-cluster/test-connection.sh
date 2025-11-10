#!/bin/bash

# Test connection script for PostgreSQL cluster nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "❌ .env file not found. Run './ee_setup.sh init' first."
    exit 1
fi

source "$ENV_FILE"

echo "🔍 Testing connectivity to PostgreSQL cluster nodes..."
echo ""

# Test each node
for hostname_var in $(grep "^HOSTNAME_PG_NODE" "$ENV_FILE"); do
    node_name=$(echo "$hostname_var" | cut -d= -f1 | sed 's/HOSTNAME_//')
    hostname=$(echo "$hostname_var" | cut -d= -f2)

    echo "Testing $node_name ($hostname)..."

    # Test ping
    if ping -c 1 -W 2 "$hostname" &>/dev/null; then
        echo "  ✅ Ping: OK"
    else
        echo "  ❌ Ping: FAILED"
        continue
    fi

    # Test SSH
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@"$hostname" "echo 'SSH OK'" &>/dev/null; then
        echo "  ✅ SSH: OK"
    else
        echo "  ❌ SSH: FAILED"
        continue
    fi

    # Test PostgreSQL port (if installed)
    if nc -z -w2 "$hostname" 5432 &>/dev/null 2>&1; then
        echo "  ✅ PostgreSQL Port (5432): Open"

        # Try to check PostgreSQL version
        pg_version=$(ssh -o StrictHostKeyChecking=no ubuntu@"$hostname" "psql --version 2>/dev/null" 2>/dev/null)
        if [ -n "$pg_version" ]; then
            echo "  ✅ PostgreSQL: $pg_version"
        fi
    else
        echo "  ⚠️  PostgreSQL Port (5432): Not accessible (may not be installed yet)"
    fi

    echo ""
done

echo "🎉 Connection test complete!"
echo ""
echo "Next steps:"
echo "  - If SSH failed: Run './ee_setup.sh ssh'"
echo "  - If PostgreSQL not installed: Run 'make deploy' or 'ansible-playbook -i inventory/hosts.ini playbooks/postgres-cluster.yml'"
echo "  - To test Ansible: Run './ee_setup.sh ansible'"

