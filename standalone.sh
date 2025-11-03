#!/bin/bash
# Completely self-contained k8s-base-cluster setup
# No external dependencies except Docker and curl
# Can be distributed as a single file

set -euo pipefail

# Embedded configuration (can be customized)
CLUSTER_NAME="${CLUSTER_NAME:-standalone-cluster}"
DOMAIN="${DOMAIN:-127-0-0-1.sslip.io}"
TOOLS_DIR="${TOOLS_DIR:-./k8s-tools}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Detect OS and architecture
detect_platform() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac
    
    echo "${os}/${arch}"
}

# Download and install tool
install_tool() {
    local name="$1"
    local url="$2"
    local target="$3"
    
    if [[ -f "$target" ]]; then
        log "$name already installed"
        return 0
    fi
    
    log "Installing $name..."
    local temp_file=$(mktemp)
    
    if curl -fsSL -o "$temp_file" "$url"; then
        mv "$temp_file" "$target"
        chmod +x "$target"
        success "$name installed"
    else
        error "Failed to install $name"
        return 1
    fi
}

# Setup tools directory
setup_tools() {
    local platform=$(detect_platform)
    local platform_dash=$(echo "$platform" | tr '/' '-')
    log "Setting up tools for $platform..."
    
    mkdir -p "$TOOLS_DIR"
    export PATH="$TOOLS_DIR:$PATH"
    
    # Tool URLs
    local k3d_url="https://github.com/k3d-io/k3d/releases/latest/download/k3d-${platform_dash}"
    local kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    local kubectl_url="https://dl.k8s.io/release/${kubectl_version}/bin/${platform}/kubectl"
    local helm_url="https://get.helm.sh/helm-v3.13.3-${platform_dash}.tar.gz"
    local mkcert_url="https://dl.filippo.io/mkcert/latest?for=${platform}"
    
    # Install tools
    install_tool "k3d" "$k3d_url" "$TOOLS_DIR/k3d"
    install_tool "kubectl" "$kubectl_url" "$TOOLS_DIR/kubectl"
    install_tool "mkcert" "$mkcert_url" "$TOOLS_DIR/mkcert"
    
    # Helm requires special handling (tar.gz)
    if [[ ! -f "$TOOLS_DIR/helm" ]]; then
        log "Installing helm..."
        local temp_dir=$(mktemp -d)
        if curl -fsSL "$helm_url" | tar -xz -C "$temp_dir"; then
            find "$temp_dir" -name "helm" -type f -exec mv {} "$TOOLS_DIR/" \;
            chmod +x "$TOOLS_DIR/helm"
            rm -rf "$temp_dir"
            success "helm installed"
        else
            error "Failed to install helm"
        fi
    else
        log "helm already installed"
    fi
}

# Create cluster
create_cluster() {
    log "Creating k3d cluster: $CLUSTER_NAME"
    
    # Check if cluster exists
    if "$TOOLS_DIR/k3d" cluster list | grep -q "$CLUSTER_NAME"; then
        warn "Cluster $CLUSTER_NAME already exists"
        return 0
    fi
    
    # Find available ports
    local http_port=8080
    local https_port=8443
    while lsof -Pi :$http_port -sTCP:LISTEN -t >/dev/null 2>&1; do
        ((http_port++))
    done
    while lsof -Pi :$https_port -sTCP:LISTEN -t >/dev/null 2>&1; do
        ((https_port++))
    done
    
    log "Using ports: HTTP=$http_port, HTTPS=$https_port"
    
    # Create cluster (using built-in Traefik + local registry + volume mounts)
    mkdir -p ./data
    "$TOOLS_DIR/k3d" cluster create "$CLUSTER_NAME" \
        --servers 1 --agents 0 \
        --port "$http_port:80@loadbalancer" \
        --port "$https_port:443@loadbalancer" \
        --registry-create registry.localhost:5001 \
        --volume "$(pwd)/data:/data@server:0" \
        --wait --timeout 120s
    
    success "Cluster created on ports $http_port/$https_port"
    export HTTP_PORT=$http_port
    export HTTPS_PORT=$https_port
}

# Setup certificates
setup_certificates() {
    log "Setting up certificates..."
    
    # Install CA (suppress Java warnings)
    "$TOOLS_DIR/mkcert" -install 2>/dev/null || true
    
    # Create certificates directory
    mkdir -p certs
    
    # Generate certificates (suppress Java warnings)
    "$TOOLS_DIR/mkcert" -cert-file certs/wildcard.crt -key-file certs/wildcard.key \
        "*.$DOMAIN" "$DOMAIN" "localhost" "127.0.0.1" 2>/dev/null || {
        warn "Certificate generation had warnings but likely succeeded"
    }
    
    success "Certificates created"
}

# Deploy infrastructure
deploy_infrastructure() {
    log "Deploying infrastructure..."
    
    # Add helm repos (only if they don't exist)
    "$TOOLS_DIR/helm" repo list | grep -q jetstack || "$TOOLS_DIR/helm" repo add jetstack https://charts.jetstack.io
    "$TOOLS_DIR/helm" repo list | grep -q argo || "$TOOLS_DIR/helm" repo add argo https://argoproj.github.io/argo-helm
    "$TOOLS_DIR/helm" repo update
    
    # Create namespaces
    "$TOOLS_DIR/kubectl" create namespace cert-manager --dry-run=client -o yaml | "$TOOLS_DIR/kubectl" apply -f -
    "$TOOLS_DIR/kubectl" create namespace argocd --dry-run=client -o yaml | "$TOOLS_DIR/kubectl" apply -f -
    
    # Install cert-manager
    "$TOOLS_DIR/helm" upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --set installCRDs=true \
        --wait --timeout=300s
    
    # Create mkcert CA secret
    "$TOOLS_DIR/kubectl" create secret tls mkcert-ca-secret \
        --cert="$("$TOOLS_DIR/mkcert" -CAROOT)/rootCA.pem" \
        --key="$("$TOOLS_DIR/mkcert" -CAROOT)/rootCA-key.pem" \
        --namespace=cert-manager \
        --dry-run=client -o yaml | "$TOOLS_DIR/kubectl" apply -f -
    
    # Create ClusterIssuer
    "$TOOLS_DIR/kubectl" apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: mkcert-issuer
spec:
  ca:
    secretName: mkcert-ca-secret
EOF
    
    success "cert-manager deployed"
}

# Deploy ArgoCD
deploy_argocd() {
    log "Deploying ArgoCD..."
    
    # Install ArgoCD
    "$TOOLS_DIR/helm" upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --set server.service.type=ClusterIP \
        --set server.ingress.enabled=false \
        --wait --timeout=300s
    
    # Create ArgoCD Ingress with TLS
    "$TOOLS_DIR/kubectl" apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: "mkcert-issuer"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - argocd.$DOMAIN
    secretName: argocd-tls
  rules:
  - host: argocd.$DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
    
    # Wait for ArgoCD to be ready
    "$TOOLS_DIR/kubectl" wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
    
    success "ArgoCD deployed"
}


# Deploy test application
deploy_test() {
    log "Deploying test application..."
    
    "$TOOLS_DIR/kubectl" apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: standalone-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: standalone-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: standalone-test
spec:
  selector:
    app: nginx
  ports:
  - port: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  namespace: standalone-test
  annotations:
    cert-manager.io/cluster-issuer: "mkcert-issuer"
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - standalone.$DOMAIN
    secretName: standalone-tls
  rules:
  - host: standalone.$DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
EOF
    
    # Wait for deployment
    "$TOOLS_DIR/kubectl" wait --for=condition=Available deployment/nginx -n standalone-test --timeout=120s
    "$TOOLS_DIR/kubectl" wait --for=condition=Ready certificate/standalone-tls -n standalone-test --timeout=120s
    
    success "Test application deployed"
}

# Show results
show_results() {
    echo ""
    echo "🎉 GitOps-Ready k8s-base-cluster Complete!"
    echo "=========================================="
    echo ""
    echo "🏷️  Cluster: $CLUSTER_NAME"
    echo "🌐 Domain: $DOMAIN"
    echo "🔧 Tools: $TOOLS_DIR"
    echo ""
    echo "🚀 GitOps Platform URLs:"
    echo "  ArgoCD:  https://argocd.$DOMAIN:${HTTPS_PORT:-8443}"
    echo "  Test App: https://standalone.$DOMAIN:${HTTPS_PORT:-8443}"
    echo ""
    echo "🐳 Local Registry:"
    echo "  Registry: registry.localhost:5001"
    echo "  Usage: docker tag image registry.localhost:5001/image"
    echo ""
    echo "💾 Built-in Storage:"
    echo "  Storage Class: local-path (default)"
    echo "  Host Mount: ./data -> /data (in containers)"
    echo ""
    echo "🔑 ArgoCD Credentials:"
    echo "  Username: admin"
    echo "  Password: \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
    echo ""
    echo "🔧 Tools available in: $TOOLS_DIR"
    echo "  export PATH=\"$TOOLS_DIR:\$PATH\""
    echo ""
    echo "🧹 Cleanup:"
    echo "  $TOOLS_DIR/k3d cluster delete $CLUSTER_NAME"
    echo ""
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    "$TOOLS_DIR/k3d" cluster delete "$CLUSTER_NAME" 2>/dev/null || true
    success "Cleanup complete"
}

# Fix inotify limits that cause containerd CRI failures
fix_inotify_limits() {
    log "Checking and fixing inotify limits..."
    
    # Increase inotify limits using privileged container (works on Docker Desktop)
    if docker run --rm --privileged alpine sh -c "sysctl -w fs.inotify.max_user_instances=1024" >/dev/null 2>&1; then
        success "Increased inotify instance limit to 1024"
    else
        warn "Could not increase inotify limits - k3s may fail to start"
    fi
}

# Main execution
main() {
    echo "🔒 Standalone k8s-base-cluster"
    echo "=============================="
    echo "Completely self-contained - no external dependencies!"
    echo ""
    
    case "${1:-setup}" in
        "setup"|"")
            fix_inotify_limits
            setup_tools
            setup_certificates
            create_cluster
            deploy_infrastructure
            deploy_argocd
            deploy_test
            show_results
            ;;
        "cleanup")
            cleanup
            ;;
        "tools")
            setup_tools
            echo "Tools installed to: $TOOLS_DIR"
            echo "Add to PATH: export PATH=\"$TOOLS_DIR:\$PATH\""
            ;;
        *)
            echo "Usage: $0 [setup|cleanup|tools]"
            exit 1
            ;;
    esac
}

# Check prerequisites
if ! command -v docker &> /dev/null; then
    error "Docker is required but not installed"
    exit 1
fi

if ! docker ps &> /dev/null; then
    error "Docker is not running"
    exit 1
fi

main "$@"