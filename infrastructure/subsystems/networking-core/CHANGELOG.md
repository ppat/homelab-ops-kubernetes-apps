# Changelog

## [0.1.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.1.0...infra-networking-core-v0.1.1) (2024-10-13)


### ✨ Features

* **infra-networking-core:** update cert-manager (v1.15.3 -&gt; v1.16.0) ([#134](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/134)) ([0a17765](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0a17765b6057b5a6e68dd87a24ca585e653e0740))
* **infra-secrets-core:** add support for bitwarden-secrets-manager to external-secrets ([#128](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/128)) ([e5f2806](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e5f2806311f7c1650d7cb812088ad546bc41b789))
* sync bitwarden-secret webhook's CA cert to all namespaces that will need to fetch secrets ([#141](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/141)) ([2c161b6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2c161b6d3aad70a8e7924c3dc407e504d13cab23))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** patch cert-manager helm release to specify dns01RecursiveNameservers ([#131](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/131)) ([23e4dbd](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/23e4dbd331c3424d2cb46c07ce3951282566a4be))
* **infra-networking-core:** update cert-manager (v1.16.0 -&gt; v1.16.1) ([#150](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/150)) ([2344679](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/234467940d8cd02a29d7b784eb7c6b6f92cecc44))
* **infra-secrets-core:** sync bitwarden-ca-cert as configmap only to external-secrets namespace (not others) ([#145](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/145)) ([79f88a6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/79f88a6e166da979d0ca4ebcbff04f821ac10ae5))

## [0.1.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.0.1...infra-networking-core-v0.1.0) (2024-10-07)


### ⚠ BREAKING CHANGES

* **infra-networking-core:** update traefik (30.1.0 -> 31.1.1) ([#51](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/51))

### ✨ Features

* **infra-networking-core:** update traefik (30.1.0 -&gt; 31.1.1) ([#51](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/51)) ([8dd1847](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8dd1847e42372e7436bf978835cc3fd3cb61e91c))


### 🚀 Enhancements + Bug Fixes

* externalize PVCs so that they are created outside of subsystems modules and provided as input ([#62](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/62)) ([da4c30b](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/da4c30b5e87ecd5e8f92fb74c427616c794ee830))
* roll deployments when configmaps/secrets change ([#107](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/107)) ([f41b0d9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f41b0d9ee929a4b3f032799c977f1e28204c5197))

## 0.0.1 (2024-09-21)


### ✨ Features

* **infra-networking-core:** add subsystem - infra-networking-core ([#14](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/14)) ([d4bb8cb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d4bb8cb6f272f86920ab9e58115f51a5c41c5954))
