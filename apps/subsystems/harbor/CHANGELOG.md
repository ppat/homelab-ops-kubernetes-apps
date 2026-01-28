# Changelog

## [0.0.14](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.13...apps-harbor-v0.0.14) (2026-01-28)


### 🚀 Enhancements + Bug Fixes

* **apps-harbor:** update harbor (1.18.1 -&gt; 1.18.2) ([#2664](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2664)) ([1c78a76](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1c78a76ed99694fe497bf2fac9e5ec71148dd3e9))

## [0.0.13](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.12...apps-harbor-v0.0.13) (2025-12-15)


### ✨ Features

* update ghcr.io/dragonflydb/dragonfly (v1.34.2 -&gt; v1.35.0) ([#2430](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2430)) ([5026685](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5026685b43479ea258417cb781a3c09f99c69924))


### 🚀 Enhancements + Bug Fixes

* **apps-harbor:** re-enable trivy in chainsaw test ([#2545](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2545)) ([cf49eba](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/cf49eba89b34aee4c5f48e0e1333dcb2418d0a4d))
* **apps-harbor:** trivy db downloads should not be rate limited by github ([#2544](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2544)) ([3ef2844](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/3ef284443f5b65152181674cab0b86957a4d8270))
* **apps-harbor:** update harbor (1.18.0 -&gt; 1.18.1) ([#2503](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2503)) ([c73ae46](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c73ae4614a273f229fcb60844c675e0e639ea0f5))
* **infra-security-extra:** update ghcr.io/dragonflydb/dragonfly (v1.35.0 -&gt; v1.35.1) ([#2452](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2452)) ([8075545](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/80755450098758a944d09b462faa9b7a770688d0))

## [0.0.12](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.11...apps-harbor-v0.0.12) (2025-10-22)


### ✨ Features

* **apps-harbor:** switch to cloudnativepg postgres for harbor's database from internal ([#2306](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2306)) ([a7aaeeb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a7aaeeb9af1005cc0da4b06168b5f36ae73234d7))
* **apps-harbor:** switch to dragonfly for harbor's redis from internal ([#2309](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2309)) ([51e27bd](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/51e27bdbfac44efa4ed1e58f16b10c90c696bf25))

## [0.0.11](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.10...apps-harbor-v0.0.11) (2025-09-25)


### ✨ Features

* **apps-harbor:** update harbor (1.17.2 -&gt; 1.18.0) ([#2134](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/2134)) ([ff1b1f2](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ff1b1f23b708e7abea8a0d9bd56fbc23261269bb))

## [0.0.10](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.9...apps-harbor-v0.0.10) (2025-08-07)


### 🚀 Enhancements + Bug Fixes

* **apps-harbor:** update harbor (1.17.1 -&gt; 1.17.2) ([#1896](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1896)) ([937ece9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/937ece982e979a6beee24a9abd491eef34402ce4))

## [0.0.9](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.8...apps-harbor-v0.0.9) (2025-07-09)


### 🚀 Enhancements + Bug Fixes

* move helmrepository resources into respective modules that depend on them ([#1691](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1691)) ([5eb5ab6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5eb5ab6491cdd48eb5a7d5413a04041258c5b8c5))

## [0.0.8](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.7...apps-harbor-v0.0.8) (2025-06-30)


### 🚀 Enhancements + Bug Fixes

* default all external secrets to refresh every 24h (instead of 1h) ([#1578](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1578)) ([4ec69db](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/4ec69dbd9f0825da6b7b7d05e39d0f46ffb90bd0))

## [0.0.7](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.6...apps-harbor-v0.0.7) (2025-06-29)


### 🛠 Improvements

* address markdown linting errors ([#1567](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1567)) ([38ffe5c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/38ffe5c23a66c2181b75a57b8eac409adf80d521))

## [0.0.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.5...apps-harbor-v0.0.6) (2025-06-20)


### 🚀 Enhancements + Bug Fixes

* **apps-harbor:** migrate externally maintained external-secret(s) into apps-harbor module ([#1459](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1459)) ([babcc1f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/babcc1fd4de2b713888b42eeda32ca9438c3b904))

## [0.0.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.4...apps-harbor-v0.0.5) (2025-05-31)


### 🚀 Enhancements + Bug Fixes

* **apps-harbor:** update harbor (1.17.0 -&gt; 1.17.1) ([#1345](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1345)) ([6eb2cc5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6eb2cc54dcac2c107294c5f72fca8213a5cf2a85))

## [0.0.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.3...apps-harbor-v0.0.4) (2025-04-22)


### ✨ Features

* **apps-harbor:** update harbor (1.16.2 -&gt; 1.17.0) ([#1125](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1125)) ([40d65f2](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/40d65f252d046a10e30b1436ad5cb1fce87ed863))

## [0.0.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.2...apps-harbor-v0.0.3) (2025-04-11)


### 🛠 Improvements

* create initial documentation ([#833](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/833)) ([e5b84c0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e5b84c03920d34e3055bea987b465e04092af030))
* document module&lt;-&gt;app mapping and use app logos for each app ([#889](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/889)) ([6cb97bb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6cb97bb71826434291de7b067983830376f0d12b))


### 🚀 Enhancements + Bug Fixes

* **apps-harbor:** increase harbor helm release timeout ([#1082](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1082)) ([4762332](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/47623326640aeec306202749844bf3dd466a011d))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-harbor-v0.0.1...apps-harbor-v0.0.2) (2025-01-21)


### 🚀 Enhancements + Bug Fixes

* **apps-harbor:** update harbor (1.16.1 -&gt; 1.16.2) ([#635](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/635)) ([d9a85f8](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d9a85f805c6a143d0a18aa2f99bcff207f13e6b4))

## 0.0.1 (2025-01-10)


### ✨ Features

* **apps-harbor:** add harbor subsystem ([#546](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/546)) ([bffd4e6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/bffd4e64a5af935c0a8355b5b5a21b188378847b))
