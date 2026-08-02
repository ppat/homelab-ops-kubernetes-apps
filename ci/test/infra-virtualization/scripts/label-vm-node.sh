#!/bin/bash
set -euo pipefail

# The kubevirt-cr.yaml nodeSelector (homelab-ops.internal/virtualization: "enabled")
# is now a module-owned constant, not a Flux postBuild variable -- so unlike the old
# vm_node_label_key/vm_node_label_value substitution (which CI pointed at
# kubernetes.io/os=linux to match every kind node for free), this suite has to put the
# real label on a real node itself or virt-handler/virt-api/virt-controller have
# nowhere to schedule and the KubeVirt CR never reaches Deployed. Labelling for real
# here -- rather than patching the nodeSelector away in the test's Kustomization -- is
# what keeps this suite an actual proof that the shipped nodeSelector causes scheduling,
# the same security control production relies on.
#
# Single-node kind cluster, so --all is exactly the one node meant to run KubeVirt.
kubectl label node --all homelab-ops.internal/virtualization=enabled --overwrite
