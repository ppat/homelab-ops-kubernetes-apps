# Changelog

## [0.0.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-secrets-core-v0.0.2...infra-secrets-core-v0.0.3) (2024-10-13)


### ✨ Features

* **infra-secrets-core:** add support for bitwarden-secrets-manager to external-secrets ([#128](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/128)) ([e5f2806](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e5f2806311f7c1650d7cb812088ad546bc41b789))
* **infra-secrets-core:** distribute ca cert (needed for creating ExternalSecret) to other namespaces with trust-manager ([#139](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/139)) ([bc23e48](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/bc23e4831ba6afde86204d0111f695c00965a39d))
* sync bitwarden-secret webhook's CA cert to all namespaces that will need to fetch secrets ([#141](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/141)) ([2c161b6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2c161b6d3aad70a8e7924c3dc407e504d13cab23))


### 🚀 Enhancements + Bug Fixes

* **infra-secrets-core:** minor external-secrets refactor ([#140](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/140)) ([de6310c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/de6310c22c8551b289d4d458a92bb4b0798506fa))
* **infra-secrets-core:** sync bitwarden-ca-cert as configmap only to external-secrets namespace (not others) ([#145](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/145)) ([79f88a6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/79f88a6e166da979d0ca4ebcbff04f821ac10ae5))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-secrets-core-v0.0.1...infra-secrets-core-v0.0.2) (2024-10-07)


### 🚀 Enhancements + Bug Fixes

* **infra-secrets-core:** update external-secrets (0.10.3 -&gt; 0.10.4) ([#53](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/53)) ([5975500](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/597550084c92472fd59dafd2cb9928bd2cf79666))

## 0.0.1 (2024-09-21)


### ✨ Features

* **infra-secrets-core:** add subsystem - infra-secrets-core ([#12](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/12)) ([c046142](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c046142d3734ecdc67057795e170feadd6a4413e))
