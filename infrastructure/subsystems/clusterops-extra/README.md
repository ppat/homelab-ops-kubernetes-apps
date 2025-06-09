# Cluster Operations Extra

This module extends cluster operational capabilities with resource optimization visualization, configuration reloading, and infrastructure as code management.

## Quick Links

<a href="https://github.com/FairwindsOps/goldilocks" target="_blank"><img src="../../../.static/images/logos/goldilocks.svg" width="32" height="32" alt="Goldilocks"></a> <a href="https://github.com/stakater/Reloader" target="_blank"><img src="../../../.static/images/logos/reloader.png" width="32" height="32" alt="Reloader"></a>

## Overview

The clusterops-extra module provides three main capabilities:

1. Resource Optimization Visualization
   - VPA recommendations dashboard
   - Per-namespace resource analysis
   - Resource usage visualization
   - Secure dashboard access via ingress
   - Control plane node scheduling
   - Defined resource limits:
     - Controller: 25m-500m CPU, 50Mi-200Mi memory
     - Dashboard: 25m-500m CPU, 50Mi-200Mi memory

2. Configuration Reloading
   - Annotation-based reload strategy
   - ConfigMap and Secret change detection
   - Enhanced security features:
     - Read-only root filesystem
     - Non-root user execution (UID 65534)
     - Dropped capabilities
     - RuntimeDefault seccomp profile
   - Metrics collection via PodMonitor
   - Control plane node scheduling

3. Infrastructure as Code Management
   - GitOps-based Terraform management
   - Flux system integration
   - Metrics exposed via ServiceMonitor
   - Control plane node scheduling
   - Automated reconciliation (15m interval)

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Goldilocks | Resource optimization visualization | • Integrates with external VPA installation<br>• Exposes dashboard at goldilocks.${domain_name}<br>• Uses websecure entrypoint with TLS<br>• Provides resource usage insights<br>• Runs with specific resource limits |
| Stakater Reloader | Configuration reload management | • Watches ConfigMaps and Secrets<br>• Triggers pod restarts on config changes<br>• Exposes metrics via PodMonitor<br>• Runs with enhanced security<br>• Uses annotation-based triggers |

## Prerequisites

1. Required Components

   | Component | Purpose | Configuration |
   |-----------|---------|---------------|
   | VPA | Resource analysis | Installed separately |
   | Metrics Server | Metrics collection | K3s built-in |

2. Required Variables

   | Variable | Purpose | Required By |
   |----------|---------|-------------|
   | domain_name | Dashboard access | Goldilocks ingress |

## Dependencies

### Required By

- Application modules using:
  - Resource optimization insights
  - Dynamic configuration reloading
  - Terraform-managed resources

### Depends On

- [clusterops-core](../clusterops-core) - For Flux system integration

## Usage

### Resource Optimization

Enable Goldilocks for a namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: example-namespace
  labels:
    goldilocks.fairwinds.com/enabled: "true"
```

### Configuration Reloading

Enable reloading for a deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    reloader.stakater.com/auto: "true"
spec:
  template:
    spec:
      containers:
      - name: app
        envFrom:
        - configMapRef:
            name: app-config
```
