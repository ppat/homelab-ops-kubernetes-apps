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
   | `kubevirt_monitor_namespace` | Namespace containing the Prometheus ServiceAccount that reads KubeVirt metrics | `KubeVirt` CR |
   | `kubevirt_monitor_account` | ServiceAccount name virt-operator grants read access to when generating its ServiceMonitor | `KubeVirt` CR |

## Dependencies

### Required By

- None currently. A future VM-hosting module (outside this repo) is expected to depend on this module once it exists.

### Depends On

- None. This module ships its own CRD, operator, and RBAC, and requires no secret store, storage class, or other module's resources.

## Notes

- **Node prerequisites are not automatable from inside the cluster.** The `KubeVirt` CR's node placement (`spec.infra.nodePlacement`/`spec.workloads.nodePlacement`) hardcodes `homelab-ops.internal/virtualization: "enabled"` as its `nodeSelector` — a module-owned constant, not a per-cluster configurable value, since which nodes are prepared to run VMs is an operator decision, not module config. Any node meant to carry that exact label must already have `/dev/kvm`, the `vhost_net` kernel module, and `/dev/net/tun` present, and the label itself must be applied out-of-band before this module is useful — nothing in this module can verify or provision either. See the node-prep runbook in the sibling clusters repo's `OPERATIONS.md` (`../homelab-ops-kubernetes-clusters/OPERATIONS.md`) for the actual steps.
- **`infrastructure/bootstrap/crds/kubevirt/` is bootstrap/DR-only.** It extracts the `KubeVirt` CRD from the same upstream release asset so dependent resources can reference the type during first-time cluster setup or disaster recovery, before this module has deployed. It has no effect on an already-running cluster — see [DESIGN.md#bootstrap-and-crds](../../../DESIGN.md#bootstrap-and-crds).
- **No `-extra` sibling exists or is planned.** Core/extra in this repo exists only to break dependency cycles; there is none here, so the `-core` suffix is kept purely for naming consistency with every other infrastructure subsystem.
- **A VM's `domain.cpu` is guest topology, not a Kubernetes CPU request.** `cores`/`sockets`/`threads` (their product is the vCPU count) describe what the guest OS sees, nothing more. virt-controller derives the virt-launcher pod's actual CPU *request* separately, as `vCPUs ÷ cpuAllocationRatio` — `cpuAllocationRatio` lives on the `KubeVirt` CR at `spec.configuration.developerConfiguration.cpuAllocationRatio` (this module leaves it unset, so it defaults to `10`; see `kubevirt-cr.yaml`, which already sets its sibling `useEmulation` under the same `developerConfiguration` block). No CPU *limit* is applied to the pod unless `domain.resources.limits.cpu` is set explicitly, or a namespace `ResourceQuota` carrying a `cpu` limit forces KubeVirt to add one automatically.
- **Setting a CPU limit on a VM is usually a mistake.** The guest kernel schedules against the full vCPU topology it was told about in `domain.cpu`; a Kubernetes CPU limit throttles the underlying cgroup via the host's CFS bandwidth controller, invisibly to the guest. The result is erratic stalls under contention, not the clean, visible degradation a request-only VM gets — the guest has no signal that it's being throttled and keeps scheduling as if it owned the full topology. If a VM needs a higher CPU guarantee, raise the *request* (fewer vCPUs, or a lower `cpuAllocationRatio`); don't add a limit.
- **`dedicatedCpuPlacement: true` is the clean alternative, but it needs the kubelet CPU Manager.** It moves the VM to Guaranteed QoS (CPU and memory requests pinned equal to limits) and has KubeVirt pin the guest's vCPUs 1:1 to exclusive host pCPUs via the Kubernetes CPU Manager's static policy — no `cpuAllocationRatio`, no CFS involvement. It only works on a node where kubelet is already running CPU Manager with that policy; KubeVirt detects this per node and reflects it in the `cpumanager`/`kubevirt.io/cpumanager` node labels. Enabling CPU Manager is a kubelet configuration change this module cannot make — it's node prep, the same category as the `/dev/kvm`/`vhost_net`/`/dev/net/tun` prerequisites above.
- **VM memory is a hard reservation — KubeVirt has no memory overcommit.** A running VMI can't give memory back once QEMU has allocated it, so whatever `domain.resources.requests.memory` asks for is reserved against node capacity for the VM's lifetime, not treated as a burstable hint the way pod memory requests often are. On top of that, virt-controller adds a calculated `virt-launcher` overhead: several small fixed per-process components (the virt-launcher, monitor, `virtlogd`, `virtqemud`, and QEMU processes, each tens of Mi), a per-vCPU allowance, a per-IOThread allowance, an allowance for the default video device, and a page-table allowance proportional to guest memory — together typically a few hundred Mi for a modest VM, not a number worth hardcoding. `domain.resources.overcommitGuestOverhead: true` skips requesting that overhead from Kubernetes, trading node density for OOM-kill risk if the estimate undershoots; unused by default on this platform.
- **A disk in `devices.disks` is only a name; the matching `volumes` entry decides whether it survives a restart.** This platform's VMs use three volume types: `containerDisk` (an OCI image layer — read-only base plus a writable layer, discarded whenever the VM stops; fine for an immutable boot disk, never for data that must persist), `persistentVolumeClaim` (the only one of the three that's durable), and `cloudInitNoCloud` (renders cloud-init user-data from a Secret fresh on every boot — regenerated, not persisted). A VM with three disks and only one PVC is the normal shape for that combination (ephemeral boot disk + persistent data disk + regenerated cloud-init disk), not a missing volume.
- **Set `bootOrder` explicitly on whichever disk should boot.** Without it, boot device order falls back to the order disks/interfaces are listed in the spec — an implicit ordering that a later edit to that list can silently invalidate. An explicit `bootOrder: 1` on the intended boot disk survives reordering or adding other disks later.
- **A disk's `serial` field gives the guest a stable device path.** virtio-blk device-letter assignment (`/dev/vda`, `/dev/vdb`, …) depends on enumeration order, which isn't guaranteed to stay put across reboots or spec changes. Setting `serial: <name>` on a disk makes it addressable in the guest at a fixed `/dev/disk/by-id/virtio-<name>` path instead — what any in-guest fstab entry or cloud-init mount referencing that disk should use rather than assuming a `/dev/vdX` letter.
