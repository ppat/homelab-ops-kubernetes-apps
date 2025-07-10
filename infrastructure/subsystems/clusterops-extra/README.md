# Cluster Operations Extra

This module extends cluster operational capabilities with resource optimization visualization, configuration reloading, and infrastructure as code management.

## Quick Links

<a href="https://github.com/FairwindsOps/goldilocks" target="_blank"><img src="../../../.static/images/logos/goldilocks.svg" width="32" height="32" alt="Goldilocks"></a>

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

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Goldilocks | Resource optimization visualization | • Integrates with external VPA installation<br>• Exposes dashboard at goldilocks.${domain_name}<br>• Uses websecure entrypoint with TLS<br>• Provides resource usage insights<br>• Runs with specific resource limits |

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
  - Terraform-managed resources

### Depends On

- [clusterops-core](../clusterops-core) - For Flux system integration
