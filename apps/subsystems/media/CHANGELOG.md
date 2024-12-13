# Changelog

## [0.0.8](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-media-v0.0.7...apps-media-v0.0.8) (2024-12-13)


### 🚀 Enhancements + Bug Fixes

* **apps-media:** update plexinc/pms-docker (1.41.2.9200-c6bbc1b53 -&gt; 1.41.3.9292-bc7397402) ([#422](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/422)) ([652de45](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/652de45a546b3b74a158f63b14de35983e5acd28))
* **infra-networking-core:** update digest busybox (db142d4 -&gt; 2919d01) ([#417](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/417)) ([8ab2e29](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8ab2e293b3bd7c97cabbbd9be486ce4c36d43d3f))

## [0.0.7](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-media-v0.0.6...apps-media-v0.0.7) (2024-12-04)


### ✨ Features

* **apps-media:** update ghcr.io/tautulli/tautulli (v2.14.6 -&gt; v2.15.0) ([#356](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/356)) ([2ef1dcb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2ef1dcb63225dfeee5073df592a3120bfada54aa))


### 🚀 Enhancements + Bug Fixes

* **apps-media:** fix issue where plex deployment's init script creates an unnecessary symlink ([#381](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/381)) ([f5bb471](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f5bb471ee39b760a4722685c837478060002f18e))

## [0.0.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-media-v0.0.5...apps-media-v0.0.6) (2024-11-24)


### 🚀 Enhancements + Bug Fixes

* **apps-media:** update ghcr.io/jellyfin/jellyfin (10.10.2 -&gt; 10.10.3) ([#308](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/308)) ([3283809](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/3283809b761009c7d27f0afa294563dfda1e69b8))
* **infra-networking-core:** update digest busybox (5b0f33c -&gt; db142d4) ([#314](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/314)) ([1897233](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1897233dc4b5695fa3b7b34cdce985c0075f68bf))
* **infra-networking-core:** update digest busybox (c230832 -&gt; 5b0f33c) ([#312](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/312)) ([b2c9660](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b2c96609233be7be7480499305b11796c9eef4b7))

## [0.0.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-media-v0.0.4...apps-media-v0.0.5) (2024-11-18)


### 🚀 Enhancements + Bug Fixes

* **apps-media:** update ghcr.io/jellyfin/jellyfin (10.10.1 -&gt; 10.10.2) ([#294](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/294)) ([d3c7ed3](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d3c7ed3b6e83e8461cf78810f2e2f00086b5773a))
* **apps-media:** update plexinc/pms-docker (1.41.1.9057-af5eaea7a -&gt; 1.41.2.9200-c6bbc1b53) ([#290](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/290)) ([4029c8c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/4029c8c0e5dde22ba469c82c3b07cc64d93d59bc))

## [0.0.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-media-v0.0.3...apps-media-v0.0.4) (2024-11-15)


### 🚀 Enhancements + Bug Fixes

* **apps-media:** switch jellyfin's media volume mount path to be /data ([#287](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/287)) ([f775d33](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f775d33afffa03ca4409ab071c6c75b7be5928ff))
* **apps-media:** update plexinc/pms-docker (1.41.0.8992-8463ad060 -&gt; 1.41.1.9057-af5eaea7a) ([#280](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/280)) ([cbb1f1e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/cbb1f1e0b813e630cb4d6272869c7482bfaf38a8))

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
