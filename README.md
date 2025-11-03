# k8s-base-cluster

**Self-contained Kubernetes cluster with GitOps capabilities**

## Quick Start

```bash
# Single script deployment - no external dependencies except Docker
./standalone.sh
```

This creates a complete GitOps-ready Kubernetes cluster with:
- ✅ k3d cluster with working node registration  
- ✅ **Built-in k3s Traefik ingress controller**
- ✅ **Local container registry** (registry.localhost:5001)
- ✅ **Built-in persistent storage** (local-path storage class)
- ✅ **Volume mounts** (./data -> /data in containers)
- ✅ Automatic TLS certificates via mkcert
- ✅ cert-manager for certificate management
- ✅ **ArgoCD for GitOps workflow**
- ✅ Test application with HTTPS
- ✅ All tools downloaded locally (no package manager required)

## What You Get

- **Self-contained**: Downloads k3d, kubectl, helm, mkcert automatically
- **GitOps Ready**: ArgoCD installed and configured with HTTPS
- **Production Ingress**: Uses k3s built-in Traefik ingress controller
- **Working TLS**: Uses mkcert for locally trusted HTTPS certificates
- **Production-ready**: cert-manager integration for automatic certificate management
- **Reliable**: Fixes inotify limits that cause k3s startup failures
- **Clean**: Single script handles setup, test deployment, and cleanup

## GitOps Platform

Add monitoring, logging, and storage with GitOps:

```bash
# After cluster is running, add platform applications
kubectl apply -f https://raw.githubusercontent.com/r-aas/k8s-platform/main/bootstrap/platform-app.yaml
```

This deploys:
- **Prometheus + Grafana** - Monitoring and dashboards
- **Loki** - Log aggregation
- **MinIO** - S3-compatible object storage

## URLs After Setup

- **ArgoCD**: `https://argocd.127-0-0-1.sslip.io:8443`
- **Test App**: `https://standalone.127-0-0-1.sslip.io:8443`
- **Local Registry**: `registry.localhost:5001`
- **Grafana**: `https://grafana.127-0-0-1.sslip.io:8443` (after platform deployment)
- **Prometheus**: `https://prometheus.127-0-0-1.sslip.io:8443` (after platform deployment)

## Built-in Development Features

**Local Container Registry:**
```bash
# Build and push to local registry
docker build -t my-app .
docker tag my-app registry.localhost:5001/my-app
docker push registry.localhost:5001/my-app
```

**Persistent Storage:**
```yaml
# Use built-in storage class
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  storageClassName: local-path
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
```

**Volume Mounts:**
- Host directory `./data` mounted to `/data` in containers
- Perfect for development databases, logs, etc.

## ArgoCD Access

```bash
# Username: admin
# Password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Cleanup

```bash
./standalone.sh cleanup
```

## Requirements

- Docker (must be running)
- curl (for downloading tools)

That's it! No package managers, no external tool installation required.