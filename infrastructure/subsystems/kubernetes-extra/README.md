# Kubernetes Extra

This module extends Kubernetes with advanced operational capabilities: hardware discovery, resource optimization, device management, and workload distribution.

## Quick Links

<a href="https://github.com/kubernetes-sigs/descheduler" target="_blank"><img src="../../../.static/images/logos/kubernetes.svg" width="32" height="32" alt="Descheduler"></a> <a href="https://github.com/intel/intel-device-plugins-for-kubernetes" target="_blank"><img src="../../../.static/images/logos/intel.png" width="32" height="32" alt="Intel Device Plugins"></a> <a href="https://kubernetes-sigs.github.io/node-feature-discovery/" target="_blank"><img src="../../../.static/images/logos/kubernetes.svg" width="32" height="32" alt="Node Feature Discovery"></a> <a href="https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler" target="_blank"><img src="../../../.static/images/logos/kubernetes.svg" width="32" height="32" alt="Vertical Pod Autoscaler"></a>

## Overview

The kubernetes-extra module provides four main capabilities:

1. Hardware Discovery and Management
   - Automated USB device detection with specific class support
     - Storage devices (08)
     - Display devices (03)
     - Communication devices (02)
     - Video devices (0e)
     - Vendor-specific devices (ff)
   - Device labeling with class, vendor, and device information
   - Intel GPU integration with shared device access
   - Node feature rule generation
   - TUN device management
     - Up to 1000 concurrent allocations
     - Direct /dev/net/tun access
     - Privileged device operations
     - Real-time metrics collection

2. Resource Optimization
   - Vertical Pod Autoscaler in recommendation mode
   - Resource usage analysis and suggestions
   - Memory and CPU optimization
   - No automatic updates (manual application required)

3. Workload Distribution
   - 15-minute descheduling interval
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

4. Monitoring Integration
   - Prometheus metrics for all components
   - Resource utilization tracking
   - Device status monitoring
   - Scheduling event tracking

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Node Feature Discovery | Hardware detection | • Detects specific USB device classes (02, 03, 08, 0e, ef, fe, ff)<br>• Labels nodes with hardware capabilities<br>• Provides device information (class, vendor, device)<br>• Enables Prometheus metrics<br>• Runs on all nodes including control plane |
| Vertical Pod Autoscaler | Resource optimization | • Analyzes workload resource usage<br>• Provides optimization recommendations<br>• Integrates with metrics server<br>• Exposes metrics via PodMonitor<br>• Operates in recommendation-only mode |
| Intel Device Plugins | GPU management | • Manages Intel GPU access<br>• Enables device sharing (${gpu_shared_across_max_pods} pods)<br>• Integrates with node feature discovery<br>• Provides device monitoring<br>• Requires plugin operator |
| Generic Device Plugin | TUN device management | • Manages /dev/net/tun access<br>• Supports 1000 concurrent allocations<br>• Runs with system-critical priority<br>• Exposes metrics every 15s<br>• Requires privileged access |
| Descheduler | Workload balancing | • Enforces pod distribution policies<br>• Balances node resource usage (30% -> 60%)<br>• Protects system namespaces<br>• Handles affinity/taint violations<br>• Provides scheduling metrics |

## Prerequisites

1. Required Components

   | Component | Purpose | Configuration |
   |-----------|---------|---------------|
   | Metrics Server | Resource metrics | Required for VPA |
   | Intel GPU | Device support | Optional for GPU features |
   | Prometheus | Metrics collection | For component monitoring |
   | TUN Device | Network tunneling | Required in /dev/net/tun |

2. Required Variables

   | Variable | Purpose | Default |
   |----------|---------|---------|
   | gpu_shared_across_max_pods | Maximum pods sharing a GPU | 1 |

## Dependencies

### Required By

- Application modules requiring:
  - Hardware access (GPU, USB devices, TUN)
  - Resource optimization
  - Workload distribution
  - Network tunneling capabilities

### Depends On

- [kubernetes-core](../kubernetes-core) - For API server access
