.PHONY: help init vpn ssh inventory ansible install kubespray deploy verify status clean auto

# Default target
help:
	@echo "Kubernetes Cluster Lab - Available Commands:"
	@echo ""
	@echo "🚀 Automated Deployment (Recommended):"
	@echo "  make auto       - Automated end-to-end deployment"
	@echo "                    (init + vpn + install + kubespray.sh)"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make init       - Create workspace with 3 VMs"
	@echo "  make vpn        - Connect to workspace VPN"
	@echo "  make ssh        - Setup SSH access to all nodes"
	@echo "  make inventory  - Generate Ansible inventory"
	@echo "  make ansible    - Test Ansible connectivity"
	@echo "  make install    - Install Ansible dependencies"
	@echo "  make kubespray  - Clone and setup Kubespray"
	@echo ""
	@echo "Deployment Commands:"
	@echo "  make deploy     - Deploy Kubernetes cluster with Kubespray"
	@echo "  make verify     - Verify cluster health"
	@echo "  make reset      - Reset Kubernetes cluster"
	@echo ""
	@echo "Management Commands:"
	@echo "  make status     - Show workspace status"
	@echo "  make kubeconfig - Fetch kubeconfig from master"
	@echo "  make clean      - Cleanup workspace"
	@echo ""
	@echo "Quick Start (Automated):"
	@echo "  make auto"
	@echo ""
	@echo "Quick Start (Manual):"
	@echo "  make init && make vpn && make ssh && make inventory && make install && make kubespray && make deploy"

init:
	./ee/setup.sh init

vpn:
	./ee/setup.sh vpn

ssh:
	./ee/ansible.sh ssh

inventory:
	./ee/ansible.sh inventory

ansible:
	./ee/ansible.sh test

install:
	pip install -r requirements.txt

kubespray:
	@if [ ! -d "kubespray" ]; then \
		echo "📦 Cloning Kubespray..."; \
		git clone https://github.com/kubernetes-sigs/kubespray.git; \
		cd kubespray && git checkout release-2.29; \
		pip install -r requirements.txt; \
	else \
		echo "✅ Kubespray already cloned"; \
	fi
	@echo "🔧 Setting up Kubespray inventory..."
	@echo "💡 Run './kubespray.sh' for automated deployment, or continue with 'make deploy'"

deploy:
	@echo "⚠️  For best results, use: ./kubespray.sh"
	@echo ""
	@if [ ! -d "kubespray" ]; then \
		echo "❌ Kubespray not found. Run 'make kubespray' first."; \
		exit 1; \
	fi
	@if [ ! -f "inventory/kubespray/hosts.yaml" ]; then \
		echo "❌ Inventory not found. Run './kubespray.sh' for automated deployment."; \
		exit 1; \
	fi
	cd kubespray && ansible-playbook -i ../inventory/kubespray/hosts.yaml --become --become-user=root cluster.yml

verify:
	ansible-playbook -i inventory/hosts.ini playbooks/verify-cluster.yml

reset:
	@echo "⚠️  This will reset the entire Kubernetes cluster!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd kubespray && ansible-playbook -i ../inventory/kubespray/hosts.yaml --become --become-user=root reset.yml; \
	fi

status:
	./ee/setup.sh status

kubeconfig:
	@echo "📥 Fetching kubeconfig from master node..."
	@./ee/kube.sh fetch

clean:
	./ee/setup.sh cleanup

# Quick setup - run all setup commands
setup: init vpn ssh inventory ansible

# Full deployment - setup + install + kubespray + deploy
all: setup install kubespray deploy kubeconfig

# Automated deployment using kubespray.sh
auto: init vpn install
	@echo "🚀 Starting automated Kubespray deployment..."
	@./kubespray.sh


