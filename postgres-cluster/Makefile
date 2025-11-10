.PHONY: help init vpn ssh inventory ansible install deploy verify status clean

# Default target
help:
	@echo "PostgreSQL Cluster Lab - Available Commands:"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make init       - Create workspace with 3 VMs"
	@echo "  make vpn        - Connect to workspace VPN"
	@echo "  make ssh        - Setup SSH access to all nodes"
	@echo "  make inventory  - Generate Ansible inventory"
	@echo "  make ansible    - Test Ansible connectivity"
	@echo "  make install    - Install Ansible dependencies"
	@echo ""
	@echo "Deployment Commands:"
	@echo "  make deploy     - Deploy PostgreSQL cluster"
	@echo "  make verify     - Verify cluster health"
	@echo ""
	@echo "Management Commands:"
	@echo "  make status     - Show workspace status"
	@echo "  make clean      - Cleanup workspace"
	@echo ""
	@echo "Quick Start:"
	@echo "  make init && make vpn && make ssh && make inventory && make install && make deploy"

init:
	./ee_setup.sh init

vpn:
	./ee_setup.sh vpn

ssh:
	./ee_setup.sh ssh

inventory:
	./ee_setup.sh inventory

ansible:
	./ee_setup.sh ansible

install:
	pip install -r requirements.txt

deploy:
	ansible-playbook -i inventory/hosts.ini playbooks/postgres-cluster.yml

verify:
	ansible-playbook -i inventory/hosts.ini playbooks/verify-cluster.yml

status:
	./ee_setup.sh status

clean:
	./ee_setup.sh cleanup

# Quick setup - run all setup commands
setup: init vpn ssh inventory ansible

# Full deployment - setup + install + deploy + verify
all: setup install deploy verify

