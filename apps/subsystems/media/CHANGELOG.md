# Changelog

## [0.0.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-media-v0.0.2...apps-media-v0.0.3) (2024-11-10)


### ✨ Features

* **apps-media:** add jellyfin to media subsystem ([#245](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/245)) ([02a1658](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/02a1658bc6040eebe15d6226f44d8cc082337b63))
* **apps-media:** add tautulli to media subsystem ([#244](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/244)) ([945f950](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/945f9507ca12c9e6431dea417555c4a29557ee02))


### 🚀 Enhancements + Bug Fixes

* **apps-downloaders:** switch from dockerhub to ghcr.io ([#212](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/212)) ([9bc6975](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9bc6975225b8135db5a966a074e1a718722e31c3))
* **apps-media:** clean up plex PID file from a previous run if it exists ([#161](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/161)) ([b1d548a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b1d548a71e157a033abf9b981ba8e06ef2db65c8))
* **apps-media:** misc minor changes to plex ([#220](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/220)) ([cc42cd5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/cc42cd56f49310796c34621f700fef3ba2b5af18))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-media-v0.0.1...apps-media-v0.0.2) (2024-10-13)


### ✨ Features

* sync bitwarden-secret webhook's CA cert to all namespaces that will need to fetch secrets ([#141](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/141)) ([2c161b6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2c161b6d3aad70a8e7924c3dc407e504d13cab23))


### 🚀 Enhancements + Bug Fixes

* **infra-secrets-core:** sync bitwarden-ca-cert as configmap only to external-secrets namespace (not others) ([#145](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/145)) ([79f88a6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/79f88a6e166da979d0ca4ebcbff04f821ac10ae5))

## 0.0.1 (2024-10-07)


### ✨ Features

* **apps-media:** add new subsystem - apps-media (plex, freetube, etc) ([#68](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/68)) ([67b5f0e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/67b5f0e8fd760714ed8ab6c8b07ef66224d45975))


### 🚀 Enhancements + Bug Fixes

* roll deployments when configmaps/secrets change ([#107](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/107)) ([f41b0d9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f41b0d9ee929a4b3f032799c977f1e28204c5197))
