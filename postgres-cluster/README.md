# PostgreSQL Cluster with Ansible

PostgreSQL 16 cluster: 1 primary + 2 standby nodes with streaming replication on Ubuntu 24.04.

## Setup

```bash
# 1. Setup EasyEnv workspace
ee/setup.sh init && ee/setup.sh vpn
ee/ansible.sh inventory && ee/ansible.sh test
source ee/setup.sh load_env

# 2. Install dependencies & deploy
pip install -r requirements.txt
make deploy

# 3. Verify
make verify
```

## Check Status

```bash
# Load environment
source ee/setup.sh load_env

# Check replication (primary)
ssh easyenv@$HOSTNAME_PG_NODE_1 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"

# Check standby status
ssh easyenv@$HOSTNAME_PG_NODE_2 "sudo -u postgres psql -c 'SELECT pg_is_in_recovery();'"

# Replication lag
ssh easyenv@$HOSTNAME_PG_NODE_2 "sudo -u postgres psql -c \"SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn() AS lag_bytes;\""
```

## Configuration

- **Replication**: Streaming (physical), replication slots
- **User**: `replicator` / `replicator_password`
- **WAL**: `wal_level=replica`, `max_wal_senders=10`, `wal_keep_size=1GB`
- **Auth**: MD5 from 0.0.0.0/0 (change for production)

## Manual Failover

```bash
# Promote standby to primary
ssh easyenv@$HOSTNAME_PG_NODE_2
sudo -u postgres pg_ctlcluster 16 main promote

# Verify
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"  # Should return 'f'
```

## Troubleshooting

```bash
# Logs
sudo tail -f /var/log/postgresql/postgresql-16-main.log

# Check connections
sudo netstat -tlnp | grep 5432

# Replication slots
sudo -u postgres psql -c "SELECT * FROM pg_replication_slots;"

# Test connectivity
ansible all -i inventory/hosts.ini -m ping
```

## Cleanup

```bash
ee/setup.sh cleanup  # Stops and optionally deletes workspace
```

## Playbooks

- `playbooks/postgres-cluster.yml` - Main deployment
- `playbooks/verify-cluster.yml` - Health checks
- `playbooks/maintenance.yml` - VACUUM, ANALYZE, backups
- `playbooks/manage-cluster.yml` - Start/stop/restart services
