#!/bin/bash
# Post-create script for GitHub Codespaces
# Runs once when the devcontainer is created

set -e

echo "🚀 Setting up k8s-base-cluster development environment..."

# Install additional tools
echo "📦 Installing k3d..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

echo "📦 Installing mkcert..."
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-v*-linux-amd64
sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert

echo "📦 Installing task..."
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

# Setup mkcert CA
echo "🔐 Setting up certificates..."
mkcert -install

# Make scripts executable
chmod +x scripts/*.sh

# Add helpful aliases
cat >> ~/.bashrc << 'EOF'
# k8s-base-cluster aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgi='kubectl get ingress'
alias kgc='kubectl get certificates'
alias kctx='kubectl config current-context'

# Quick cluster access
alias cluster-info='kubectl cluster-info && kubectl get nodes'
alias cluster-status='task cluster:status'
EOF

echo "✅ Development environment ready!"
echo ""
echo "🎯 Quick Start:"
echo "  1. task cluster:create"
echo "  2. task deploy:core" 
echo "  3. Open forwarded ports to test"
echo ""