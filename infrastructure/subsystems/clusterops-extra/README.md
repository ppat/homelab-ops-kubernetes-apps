# Cluster Operations Extra

This module extends cluster operational capabilities with resource optimization visualization, configuration reloading, and infrastructure as code management.

## Quick Links

<a href="https://github.com/FairwindsOps/goldilocks" target="_blank"><img src="../../../.static/images/logos/goldilocks.svg" width="32" height="32" alt="Goldilocks"></a> <a href="https://github.com/stakater/Reloader" target="_blank"><img src="../../../.static/images/logos/reloader.png" width="32" height="32" alt="Reloader"></a> <a href="https://github.com/weaveworks/tf-controller" target="_blank"><img src="../../../.static/images/logos/terraform.svg" width="32" height="32" alt="Terraform controller"></a>

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
| TF-controller | Terraform management | • Manages Terraform resources via GitOps<br>• Integrates with Flux system<br>• Exposes metrics via ServiceMonitor<br>• Supports multiple backends<br>• Handles Terraform state |

## Prerequisites

1. Required Components

   | Component | Purpose | Configuration |
   |-----------|---------|---------------|
   | VPA | Resource analysis | Installed separately |
   | Metrics Server | Metrics collection | K3s built-in |
   | Flux | GitOps engine | Required for TF-controller |

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

### Terraform Management

Create a Terraform resource:

```yaml
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: example
  namespace: flux-system
spec:
  path: ./terraform
  sourceRef:
    kind: GitRepository
    name: example-repo
  interval: 1h
  approvePlan: auto
  writeOutputsToSecret:
    name: tf-outputs
```

## Future Improvements

1. Resource Optimization
   - Enhanced VPA integration
     - Custom recommendation algorithms
     - Historical trend analysis
     - Workload pattern detection
   - Dashboard improvements
     - Cost analysis enablement
     - Custom metrics integration
     - Team-based views

2. Configuration Management
   - Advanced reload strategies
     - Gradual rollout support
     - Dependency-aware reloading
     - Validation hooks
   - Enhanced security
     - RBAC fine-tuning
     - Network policies
     - Resource quotas

3. Terraform Operations
   - Multi-cluster support
     - Cross-cluster state management
     - Resource dependency handling
     - State migration tools
   - Enhanced security
     - Secret rotation
     - Access auditing
     - Policy enforcement

4. Known Limitations
   - Resource Optimization
     - VPA must be installed separately
     - Cost analysis currently disabled
     - Limited to namespace-level opt-in
   - Configuration Reloading
     - Annotation-only trigger support
     - All-or-nothing reload strategy
     - No pre-reload validation
   - Terraform Management
     - Single runner per cluster
     - Basic metrics only
     - Limited state backup options
