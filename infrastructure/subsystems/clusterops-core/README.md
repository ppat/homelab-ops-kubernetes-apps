# Cluster Operations Core

This module provides essential cluster operational capabilities, including GitOps management, configuration reloading and system upgrades. It takes ownership of the manually installed Flux operator to manage its ongoing updates and configuration.

## Quick Links

<a href="https://fluxcd.io/" target="_blank"><img src="../../../.static/images/logos/fluxcd.png" width="32" height="32" alt="Flux CD"></a> <a href="https://github.com/rancher/system-upgrade-controller" target="_blank"><img src="../../../.static/images/logos/rancher.svg" width="32" height="32" alt="system-upgrade-controller"></a> <a href="https://github.com/stakater/Reloader" target="_blank"><img src="../../../.static/images/logos/reloader.png" width="32" height="32" alt="Reloader"></a>

## Overview

The clusterops-core module provides three main capabilities:

1. GitOps Management through Flux
   - Takes over management of the manually installed Flux operator
   - Enables Flux to manage its own updates and configuration
   - Handles Git repository synchronization and Helm chart deployments
   - Protects against out-of-memory conditions in Helm operations
   - Enforces strict variable substitution in Kustomize

2. System Component Upgrades
   - Manages automated upgrades through System Upgrade Controller
   - Controls upgrade rollout across node groups
   - Targets specific nodes based on labels and taints
   - Verifies node readiness before and after upgrades

3. Configuration Reloading
   - Annotation-based reload strategy
   - ConfigMap and Secret change detection
   - Enhanced security features:
     - Read-only root filesystem
     - Non-root user execution (UID 65534)
     - Dropped capabilities
     - RuntimeDefault seccomp profile
   - Metrics collection via PodMonitor
   - Control plane node scheduling

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Source Controller | Git and Helm source management | • Clones repositories and validates checksums<br>• Downloads Helm charts from configured repositories<br>• Maintains local cache of sources in /data<br>• Triggers reconciliation on source changes<br>• Provides metrics on source operations and status |
| Kustomize Controller | Kubernetes resource management | • Processes kustomizations with strict variable checking<br>• Applies resources using server-side apply merge strategy<br>• Prunes resources removed from source<br>• Integrates with notification controller for alerts<br>• Reports detailed reconciliation metrics |
| Helm Controller | Helm release management | • Manages Helm releases with OOM protection (95% threshold)<br>• Handles release upgrades and rollbacks<br>• Monitors memory usage every 500ms<br>• Coordinates with notification system<br>• Exposes detailed release status metrics |
| System Upgrade Controller | System component upgrades | • Executes upgrade plans with node selection<br>• Manages upgrade job scheduling and ordering<br>• Validates node status pre/post upgrade<br>• Coordinates with notification controller<br>• Integrates with Goldilocks for resource tuning |
| Stakater Reloader | Configuration reload management | • Watches ConfigMaps and Secrets<br>• Triggers pod restarts on config changes<br>• Exposes metrics via PodMonitor<br>• Runs with enhanced security<br>• Uses annotation-based triggers |

## Prerequisites

1. Required Components

   | Component | Purpose | Installation |
   |-----------|---------|--------------|
   | Flux | GitOps engine | Manual bootstrap installation |
   | Git Repository | Source of truth | Available and accessible |
   | Helm Repositories | Chart sources | Available and accessible |

2. Required Configuration

   | Configuration | Purpose | Applied By |
   |--------------|---------|------------|
   | Control plane tolerations | Schedule on control plane | deployment-tolerations.yaml |
   | SSA merge strategy | Resource merging | namespace-metadata.yaml |
   | Resource optimization | Goldilocks integration | namespace-metadata.yaml |
   | OOM protection | Helm controller safety | kustomization.yaml |

## Dependencies

### Required By

- [clusterops-extra](../clusterops-extra)
- System components requiring automated upgrades
- Dynamic configuration reloading

### Depends On

- [observability-core](../observability-core) (for monitoring)

Note: While this module manages Flux's lifecycle, Flux itself must be manually installed during cluster bootstrap. This prevents circular dependencies while enabling GitOps-based management.
