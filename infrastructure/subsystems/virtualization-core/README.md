# Virtualization Core

This module provides the KubeVirt virtualization capability, letting VirtualMachine/VirtualMachineInstance workloads run alongside standard pods on this cluster.

## Quick Links

<a href="https://kubevirt.io/" target="_blank"><img src="../../../.static/images/logos/kubevirt.png" width="32" height="32" alt="KubeVirt"></a>

## Overview

The virtualization-core module installs the KubeVirt operator and a hand-configured `KubeVirt` custom resource. It deliberately provides the virtualization *capability* only — no `VirtualMachine`/`VirtualMachineInstance` workload ever lives in this module. That boundary is intentional: keeping capability and workloads in separate modules is what keeps KubeVirt removable later without touching any VM definition, and lets VM workloads be owned by whichever module/repo actually runs them.

1. Operator Installation
   - Installs the upstream KubeVirt operator directly from its release manifest
   - Leaves the operator's image tag unset so it always installs the component versions matching its own container image, keeping operator/CR version skew impossible
   - Installs the `KubeVirt` CRD alongside the operator

2. Node Placement & Isolation
   - Restricts the privileged virt-handler DaemonSet to nodes carrying a specific label, as a security control rather than a scheduling hint
   - Restricts virt-api/virt-controller to the same labelled nodes
   - Tolerates the control-plane taint, since every node in this cluster is control-plane

3. Update & Availability Behavior
   - Opts out of automated workload disruption during KubeVirt version upgrades
   - Pins the VM rollout strategy to stage-until-reboot rather than KubeVirt's live-update default
   - Never live-migrates a VMI on eviction — an evicted VMI is stopped, not moved

4. Metrics Integration
   - Points KubeVirt's self-generated ServiceMonitor at the cluster's actual Prometheus namespace/ServiceAccount rather than the upstream OpenShift-oriented default

### Service Details

| Service | Primary Role | Key Features | Integration Points |
| ------- | ------------ | ------------- | ------------------- |
| KubeVirt | Runs and manages VM workloads on top of standard Kubernetes | • Reconciles the `KubeVirt` CR into virt-api/virt-controller/virt-handler<br>• Restricts privileged components to labelled nodes<br>• Falls back to software emulation when no `/dev/kvm` is present<br>• Publishes its own ServiceMonitor for Prometheus scraping | • Kubernetes API (CRDs, RBAC)<br>• Prometheus (via self-generated ServiceMonitor) |

## Prerequisites

1. Required Flux post-build variables

   | Variable | Purpose | Used By |
   | -------- | ------- | ------- |
   | `kubevirt_use_emulation` | Falls back to software emulation when no `/dev/kvm` is present on virtualization nodes | `KubeVirt` CR |
   | `vm_node_label_key` | Label key identifying nodes prepared to run VMs | `KubeVirt` CR node placement |
   | `vm_node_label_value` | Label value identifying nodes prepared to run VMs | `KubeVirt` CR node placement |
   | `kubevirt_monitor_namespace` | Namespace containing the Prometheus ServiceAccount that reads KubeVirt metrics | `KubeVirt` CR |
   | `kubevirt_monitor_account` | ServiceAccount name virt-operator grants read access to when generating its ServiceMonitor | `KubeVirt` CR |

## Dependencies

### Required By

- None currently. A future VM-hosting module (outside this repo) is expected to depend on this module once it exists.

### Depends On

- None. This module ships its own CRD, operator, and RBAC, and requires no secret store, storage class, or other module's resources.

## Notes

- **Node prerequisites are not automatable from inside the cluster.** Any node meant to carry the `${vm_node_label_key}: ${vm_node_label_value}` label must already have `/dev/kvm`, the `vhost_net` kernel module, and `/dev/net/tun` present, and the label itself must be applied out-of-band before this module is useful — nothing in this module can verify or provision either. See the node-prep runbook in the sibling clusters repo's `OPERATIONS.md` (`../homelab-ops-kubernetes-clusters/OPERATIONS.md`) for the actual steps.
- **`infrastructure/bootstrap/crds/kubevirt/` is bootstrap/DR-only.** It extracts the `KubeVirt` CRD from the same upstream release asset so dependent resources can reference the type during first-time cluster setup or disaster recovery, before this module has deployed. It has no effect on an already-running cluster — see [DESIGN.md#bootstrap-and-crds](../../../DESIGN.md#bootstrap-and-crds).
- **No `-extra` sibling exists or is planned.** Core/extra in this repo exists only to break dependency cycles; there is none here, so the `-core` suffix is kept purely for naming consistency with every other infrastructure subsystem.
