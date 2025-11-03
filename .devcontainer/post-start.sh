#!/bin/bash
# Post-start script for GitHub Codespaces  
# Runs every time the devcontainer starts

set -e

echo "🔄 Starting k8s-base-cluster..."

# Check if cluster exists and is running
if k3d cluster list | grep -q "codespaces-cluster"; then
    echo "✅ Cluster 'codespaces-cluster' exists"
    
    # Start cluster if stopped
    if ! kubectl cluster-info &>/dev/null; then
        echo "🚀 Starting existing cluster..."
        k3d cluster start codespaces-cluster
        kubectl wait --for=condition=Ready nodes --all --timeout=60s
    fi
else
    echo "🆕 No cluster found - run 'task cluster:create' to get started"
fi

# Show status
echo ""
echo "📊 Current Status:"
echo "  Context: $(kubectl config current-context 2>/dev/null || echo 'none')"
echo "  Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo '0')"
echo ""
echo "🎯 Next Steps:"
echo "  - task cluster:create     # Create cluster"
echo "  - task deploy:core        # Deploy infrastructure" 
echo "  - task cluster:info       # Show service URLs"
echo ""