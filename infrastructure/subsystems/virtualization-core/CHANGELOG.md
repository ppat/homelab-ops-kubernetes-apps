# Changelog

## [0.1.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-virtualization-core-v0.1.0...infra-virtualization-core-v0.1.1) (2026-08-02)


### 🛠 Improvements

* **infra-virtualization-core:** document how VM resource config maps to k8s semantics ([#3508](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/3508)) ([c6555e2](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c6555e236a787178eaec3207518058d378a5705a))

## [0.1.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-virtualization-core-v0.0.1...infra-virtualization-core-v0.1.0) (2026-08-02)


### ⚠ BREAKING CHANGES

* **infra-virtualization-core:** removes the vm_node_label_key and vm_node_label_value Flux postBuild substitution variables. Consumers must drop both from postBuild.substitute; the node-placement label is now the fixed constant homelab-ops.internal/virtualization: "enabled" and no longer configurable. Nodes previously labelled with a cluster-chosen key/value must be relabelled to the new constant for KubeVirt to schedule onto them.

### 🚀 Enhancements + Bug Fixes

* **infra-virtualization-core:** hardcode the KubeVirt node-placement label as a module constant ([#3506](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/3506)) ([420284c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/420284ce08c9ac47526c2b8a1815dabc03c30caf))

## 0.0.1 (2026-08-02)


### ✨ Features

* **infra-virtualization-core:** add virtualization-core module for KubeVirt ([#3504](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/3504)) ([f223675](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f223675a555485f91d0b33e67bc0f4a339ce543c))
