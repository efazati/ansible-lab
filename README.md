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
