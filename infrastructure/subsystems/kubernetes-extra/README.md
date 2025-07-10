# Kubernetes Extra

This module extends Kubernetes with advanced operational capabilities: hardware discovery, resource optimization, device management, and workload distribution.

## Quick Links

<a href="https://github.com/kubernetes-sigs/descheduler" target="_blank"><img src="../../../.static/images/logos/kubernetes.svg" width="32" height="32" alt="Descheduler"></a> <a href="https://github.com/intel/intel-device-plugins-for-kubernetes" target="_blank"><img src="../../../.static/images/logos/intel.png" width="32" height="32" alt="Intel Device Plugins"></a>

## Overview

The kubernetes-extra module provides four main capabilities:

1. Intel GPU Support
   - Intel GPU integration with shared device access

2. Network Tunnel Device Support
   - TUN device management
     - Direct /dev/net/tun access
     - Exposed as a allocatable resource
     - Does not require downstream pods to have privileged access
     - Real-time metrics collection

3. Workload Redistribution
   - 60-minute descheduling interval
   - Pod eviction policies:
     - Pods with >100 restarts
     - Anti-affinity violations
     - Node affinity violations
     - Taint violations
   - Resource balancing:
     - CPU threshold: 30% -> 60%
     - Memory threshold: 30% -> 60%
   - Protected namespaces:
     - kube-system
     - longhorn-system
     - logging

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Intel Device Plugins | GPU management | • Manages Intel GPU access<br>• Enables device sharing (${gpu_shared_across_max_pods} pods)<br>• Integrates with node feature discovery<br>• Provides device monitoring<br>• Requires plugin operator |
| Generic Device Plugin | TUN device management | • Manages /dev/net/tun access<br>• Supports 1000 concurrent allocations<br>• Runs with system-critical priority<br>• Exposes metrics every 15s<br>• Requires privileged access so downstream pods don't need to be privileged |
| Descheduler | Workload balancing | • Enforces pod distribution policies<br>• Balances node resource usage (30% -> 60%)<br>• Protects system namespaces<br>• Handles affinity/taint violations<br>• Provides scheduling metrics |

## Prerequisites

1. Required Components

   | Component | Purpose | Configuration |
   |-----------|---------|---------------|
   | Intel GPU | Device support | Optional for GPU features |
   | Prometheus | Metrics collection | For component monitoring |
   | TUN Device | Network tunneling | Required in /dev/net/tun |

2. Required Variables

   | Variable | Purpose | Default |
   |----------|---------|---------|
   | gpu_shared_across_max_pods | Maximum pods sharing a GPU | None, Required |

## Dependencies

### Required By

- Application modules requiring:
  - Hardware access (GPU, TUN)
  - Workload distribution
  - Network tunneling capabilities

### Depends On

- [kubernetes-core](../kubernetes-core) - For API server access and node feature labelling
