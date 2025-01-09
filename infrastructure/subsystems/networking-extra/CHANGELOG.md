# Changelog

## [0.1.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.1.3...infra-networking-extra-v0.1.4) (2025-01-09)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-extra:** update docker.io/mongo (7.0.15 -&gt; 7.0.16) ([#494](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/494)) ([46ba2d3](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/46ba2d3265a86404684b19579b9d772e51f53bd9))

## [0.1.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.1.2...infra-networking-extra-v0.1.3) (2024-12-26)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-extra:** update digest linuxserver/unifi-network-application (380542d -&gt; f8403a6) ([#450](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/450)) ([f36f292](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f36f292702a61c429249ae94fef7e0f55d02b052))
* **infra-networking-extra:** update visibilityspots/cloudflared (v2024.12.1 -&gt; v2024.12.2) ([#467](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/467)) ([7d60a76](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7d60a76b688578f09f791c5f219eb299227296c9))

## [0.1.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.1.1...infra-networking-extra-v0.1.2) (2024-12-17)


### ✨ Features

* **infra-networking-extra:** update linuxserver/unifi-network-application (8.5.6 -&gt; 8.6.9) ([#401](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/401)) ([7eb180c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7eb180c95cba91bc98153ea8787285c3436e1780))
* **infra-networking-extra:** update tailscale-operator (1.76.6 -&gt; 1.78.1) ([#413](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/413)) ([546deff](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/546deff40d12d663a72ba89ef6a3371822543713))
* **infra-networking-extra:** update visibilityspots/cloudflared (v2024.11.1 -&gt; v2024.12.1) ([#425](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/425)) ([26f506e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/26f506ec8868300b227cad1adaa050cc977f07d2))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-extra:** update digest docker.io/mongo (8ff7333 -&gt; 8958f43) ([#420](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/420)) ([e7db40f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e7db40f644bba88696bb0789316cbe8e2d634b89))
* **infra-networking-extra:** update tailscale-operator (1.78.1 -&gt; 1.78.3) ([#427](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/427)) ([0aa3687](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0aa368776cc71b0e062eaefe96746be0d31fc03b))

## [0.1.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.1.0...infra-networking-extra-v0.1.1) (2024-12-04)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-extra:** pihole should differ resolution homelab + nas k8s cluster subdomains to router ([#382](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/382)) ([2d2b697](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2d2b697aff488391508d216c5c829e70f6acf7c9))

## [0.1.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.0.6...infra-networking-extra-v0.1.0) (2024-11-24)


### ⚠ BREAKING CHANGES

* **infra-networking-extra:** move pihole + unbound + cloudflared-doh from networking-core to networking-extra ([#335](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/335))

### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** drop affinity setting for networking-core + networking-extra subsystem apps ([#337](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/337)) ([825192c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/825192c655ecf6fad55b1728f37fe5a6c0292924))
* **infra-networking-extra:** move pihole + unbound + cloudflared-doh from networking-core to networking-extra ([#335](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/335)) ([b1fe04a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b1fe04ad3d28a6674a5c7676a591590ec458d8ee))

## [0.0.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.0.5...infra-networking-extra-v0.0.6) (2024-11-18)


### ✨ Features

* **infra-networking-extra:** add tailscale-operator w/ connector configuration for subnet-routes + exit-node ([#296](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/296)) ([71b0096](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/71b0096b8ecf04b151d14d532c8229efb08daa37))

## [0.0.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.0.4...infra-networking-extra-v0.0.5) (2024-11-15)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-extra:** re-locate unifi data and firmware backups to a separate PVC mount ([#288](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/288)) ([459bc67](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/459bc6728dcd10ebd165020677e8fbfe71f94164))
* **infra-networking-extra:** update digest docker.io/mongo (7ba1f8f -&gt; 8ff7333) ([#274](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/274)) ([b4c3d54](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b4c3d54bc1f7eb5fe691cad04b9bfc6802a5217e))

## [0.0.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-extra-v0.0.3...infra-networking-extra-v0.0.4) (2024-11-08)


### ✨ Features

* **infra-networking-extra:** update linuxserver/unifi-network-application (8.3.32 -&gt; 8.5.6) ([#176](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/176)) ([2b25c95](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2b25c95b905d0844f6a913ac213b89496eafd1e5))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-extra:** set unifi + unifi-db's affinity to any amd64 nodes instead of control-plane nodes ([#224](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/224)) ([a378845](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a378845862fe46a3717f3342a98793760459d1ad))
* **infra-networking-extra:** update docker.io/mongo (7.0.14 -&gt; 7.0.15) ([#198](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/198)) ([364836a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/364836a1d1269b473ad9db35da3c0d00c4f20567))

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
