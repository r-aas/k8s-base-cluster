# k8s-base-cluster

**Self-contained Kubernetes cluster setup for local development**

## Quick Start

```bash
# Single script deployment - no external dependencies except Docker
./standalone.sh
```

This creates a complete Kubernetes cluster with:
- ✅ k3d cluster with working node registration  
- ✅ Automatic TLS certificates via mkcert
- ✅ cert-manager for certificate management
- ✅ Test application with HTTPS
- ✅ All tools downloaded locally (no package manager required)

## What It Provides

- **Self-contained**: Downloads k3d, kubectl, helm, mkcert automatically
- **Working TLS**: Uses mkcert for locally trusted HTTPS certificates
- **Production-ready**: cert-manager integration for automatic certificate management
- **Reliable**: Fixes inotify limits that cause k3s startup failures
- **Clean**: Single script handles setup, test deployment, and cleanup

## URLs After Setup

- HTTP: `http://standalone.127-0-0-1.sslip.io:8080`
- HTTPS: `https://standalone.127-0-0-1.sslip.io:8443`

## Cleanup

```bash
./standalone.sh cleanup
```

## Requirements

- Docker (must be running)
- curl (for downloading tools)

That's it! No package managers, no external tool installation required.