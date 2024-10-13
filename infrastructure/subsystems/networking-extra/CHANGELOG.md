# Changelog

## [0.0.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.0.2...infra-networking-extra-v0.0.3) (2024-10-13)


### ✨ Features

* sync bitwarden-secret webhook's CA cert to all namespaces that will need to fetch secrets ([#141](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/141)) ([2c161b6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2c161b6d3aad70a8e7924c3dc407e504d13cab23))


### 🚀 Enhancements + Bug Fixes

* **infra-secrets-core:** sync bitwarden-ca-cert as configmap only to external-secrets namespace (not others) ([#145](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/145)) ([79f88a6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/79f88a6e166da979d0ca4ebcbff04f821ac10ae5))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.0.1...infra-networking-extra-v0.0.2) (2024-10-07)


### ✨ Features

* **infra-networking-extra:** update ghcr.io/fluxcd/flux-cli (v2.3.0 -&gt; v2.4.0) ([#76](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/76)) ([af48790](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/af48790dce1a5d1f1966ed740818a7fa1ca4d77a))


### 🚀 Enhancements + Bug Fixes

* externalize PVCs so that they are created outside of subsystems modules and provided as input ([#62](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/62)) ([da4c30b](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/da4c30b5e87ecd5e8f92fb74c427616c794ee830))

## 0.0.1 (2024-09-21)


### ✨ Features

* **infra-networking-extra:** add subsystem - infra-networking-extra ([#16](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/16)) ([d8e3cac](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d8e3cac9071840835609dbe94d233a3c47d3f7ec))
