# Changelog

## [0.1.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.19...infra-clusterops-core-v0.1.0) (2025-10-21)


### ⚠ BREAKING CHANGES

* **infra-clusterops-core:** update fluxcd/flux2 (v2.6.4 -> v2.7.2) ([#2295](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2295))

### ✨ Features

* **infra-clusterops-core:** update fluxcd/flux2 (v2.6.4 -&gt; v2.7.2) ([#2295](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2295)) ([84b683b](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/84b683b1ca44a79c61bac5599610fd75d71da86a))

## [0.0.19](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.18...infra-clusterops-core-v0.0.19) (2025-09-22)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update reloader (2.2.2 -&gt; 2.2.3) ([#2086](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2086)) ([afbbc87](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/afbbc87223e2dfe915a7f338504ed82777ea0e41))

## [0.0.18](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.17...infra-clusterops-core-v0.0.18) (2025-09-07)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update rancher/system-upgrade-controller (v0.16.2 -&gt; v0.16.3) ([#2036](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2036)) ([df432ad](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/df432ad96c7e7286b865c592fe6e9d52de8dbc43))

## [0.0.17](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.16...infra-clusterops-core-v0.0.17) (2025-08-29)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update reloader (2.2.0 -&gt; 2.2.2) ([#2010](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2010)) ([bd87ef7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/bd87ef726a2d3b3e126f23a43e75fc26b887be11))

## [0.0.16](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.15...infra-clusterops-core-v0.0.16) (2025-08-17)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update rancher/system-upgrade-controller (v0.16.0 -&gt; v0.16.2) ([#1936](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1936)) ([6a522f7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6a522f710a7a7ce27bd6bca0467b168f0b072def))

## [0.0.15](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.14...infra-clusterops-core-v0.0.15) (2025-08-05)


### ✨ Features

* **infra-clusterops-core:** update reloader (2.1.5 -&gt; 2.2.0) ([#1878](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1878)) ([4784225](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/4784225a4bc9a7edb8ef2721009375cd283d33bb))

## [0.0.14](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.13...infra-clusterops-core-v0.0.14) (2025-07-18)


### ✨ Features

* **infra-clusterops-core:** update rancher/system-upgrade-controller (v0.15.3 -&gt; v0.16.0) ([#1784](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1784)) ([30f886d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/30f886d46035f8a27ad9d02069fe502fbf07f00b))

## [0.0.13](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.12...infra-clusterops-core-v0.0.13) (2025-07-10)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** move stakator reloader from clusterops-extra -&gt; clusterops-core module ([#1721](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1721)) ([ba2003e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ba2003eaa3e92969b768031dd9d3378a5e13a380))
* **infra-observability-core:** move goldilocks from clusterops-extra -&gt; observability-core module ([#1724](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1724)) ([1450644](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/14506448f82d46228009ca6b9b17085eeda325b0))

## [0.0.12](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.11...infra-clusterops-core-v0.0.12) (2025-07-08)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update fluxcd/flux2 (v2.6.3 -&gt; v2.6.4) ([#1681](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1681)) ([e8ce626](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e8ce626fe59ae51e72bff25527964456a825e538))

## [0.0.11](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.10...infra-clusterops-core-v0.0.11) (2025-07-04)


### 🚀 Enhancements + Bug Fixes

* add defensive measure to prevent unintentional pruning of critical infrastructure components ([#1624](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1624)) ([f0f4901](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f0f4901cbab8f0f98876f5c881a823b96736d4b4))

## [0.0.10](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.9...infra-clusterops-core-v0.0.10) (2025-07-04)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update rancher/system-upgrade-controller (v0.15.2 -&gt; v0.15.3) ([#1597](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1597)) ([9286d2a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9286d2a969e0ef7c80267b45e452bf3fe78e6e39))

## [0.0.9](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.8...infra-clusterops-core-v0.0.9) (2025-06-29)


### ✨ Features

* **infra-clusterops-core:** update fluxcd/flux2 (v2.5.1 -&gt; v2.6.2) ([#1504](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1504)) ([86c405d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/86c405d10e3d0756eeee6e134215c9dbf6b8b1eb))


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update fluxcd/flux2 (v2.6.2 -&gt; v2.6.3) ([#1562](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1562)) ([cf90a89](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/cf90a89bb1cd88c60ebfce2b247a18b0b48a9a99))

## [0.0.8](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.7...infra-clusterops-core-v0.0.8) (2025-04-06)


### ✨ Features

* **dev-tools:** update fluxcd/flux2 (v2.4.0 -&gt; v2.5.1) ([#1007](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1007)) ([7e108c6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7e108c6399805298b67dfec248ed5fce04bb5633))

## [0.0.7](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.6...infra-clusterops-core-v0.0.7) (2025-03-16)


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update rancher/system-upgrade-controller (v0.15.1 -&gt; v0.15.2) ([#917](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/917)) ([04f9461](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/04f9461f6c54063cdb865f4703c1d323cb2705e0))

## [0.0.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.5...infra-clusterops-core-v0.0.6) (2025-03-07)


### 🛠 Improvements

* create initial documentation ([#833](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/833)) ([e5b84c0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e5b84c03920d34e3055bea987b465e04092af030))
* document module&lt;-&gt;app mapping and use app logos for each app ([#889](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/889)) ([6cb97bb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6cb97bb71826434291de7b067983830376f0d12b))


### ✨ Features

* **infra-clusterops-core:** update rancher/system-upgrade-controller (v0.14.2 -&gt; v0.15.0) ([#854](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/854)) ([737b57a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/737b57a3dd35e9a37dbef108d4a3fa99b24f9f5b))


### 🚀 Enhancements + Bug Fixes

* **infra-clusterops-core:** update rancher/system-upgrade-controller (v0.15.0 -&gt; v0.15.1) ([#897](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/897)) ([86c20bc](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/86c20bc26c4a326a8d73fb0f4a82fe960eeac4e1))

## [0.0.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.4...infra-clusterops-core-v0.0.5) (2025-01-19)


### 🚀 Enhancements + Bug Fixes

* remove node affinity preference for control plane nodes ([#614](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/614)) ([1766b6c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1766b6c5019b6faa22e29c77e44b29153318d60b))

## [0.0.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.3...infra-clusterops-core-v0.0.4) (2025-01-17)


### ✨ Features

* **infra-clusterops-core:** add system-upgrade-controller ([#606](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/606)) ([9af188d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9af188d767c50bf44e2e19392ce3af092fc8b038))

## [0.0.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.2...infra-clusterops-core-v0.0.3) (2024-11-10)


### ✨ Features

* **infra-clusterops-core:** update fluxcd/flux2 (v2.3.0 -&gt; v2.4.0) ([#124](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/124)) ([d89153a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d89153ab4b78cbe57fedf8edcb95ba32bd2cb73b))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-clusterops-core-v0.0.1...infra-clusterops-core-v0.0.2) (2024-10-07)


### ✨ Features

* **infra-clusterops-core:** add podmonitor for flux ([#103](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/103)) ([aba91db](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/aba91db4af50f4aa1cc0bebf8751036197219305))

## 0.0.1 (2024-09-21)


### ✨ Features

* **infra-clusterops-core:** add subsystem - infra-clusterops-core ([#26](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/26)) ([385bbc5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/385bbc50845cf53103186e12562305224dfe4b18))
