# Changelog

## [0.4.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.4.1...infra-networking-core-v0.4.2) (2025-01-19)


### ✨ Features

* **infra-networking-core:** supply unifi and pihole as two alternate external-dns provider configurations ([#621](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/621)) ([9e62760](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9e62760b20563e23162784a2541518bd1bf4c696))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** rename post build variable external_dns_provider -&gt; externaldns_provider ([#624](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/624)) ([67d5852](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/67d5852cff8d634a5c9370172dc5f9101f4a6a93))
* **infra-networking-core:** update digest busybox (2919d01 -&gt; a5d0ce4) ([#585](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/585)) ([7f058d4](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7f058d43f0b0161605b4b3f20bb83ce79acff384))
* remove node affinity preference for control plane nodes ([#614](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/614)) ([1766b6c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1766b6c5019b6faa22e29c77e44b29153318d60b))

## [0.4.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.4.0...infra-networking-core-v0.4.1) (2024-12-26)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update metallb (0.14.8 -&gt; 0.14.9) ([#457](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/457)) ([3ae4643](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/3ae46436c3e8556257d1d97238e825cc5b5c2ae8))
* **infra-networking-core:** update traefik (33.2.0 -&gt; 33.2.1) ([#429](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/429)) ([355836d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/355836d4abe179a0803cc0db8c2e3a7c2dfcb927))

## [0.4.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.3.0...infra-networking-core-v0.4.0) (2024-12-13)


### ⚠ BREAKING CHANGES

* **infra-networking-core:** update traefik (32.1.1 -> 33.1.0) ([#332](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/332))

### ✨ Features

* **infra-networking-core:** update traefik (32.1.1 -&gt; 33.1.0) ([#332](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/332)) ([c12546c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c12546cafad35062bc4c93a52c10e3d7f6dd374d))
* **infra-networking-core:** update traefik (33.1.0 -&gt; 33.2.0) ([#424](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/424)) ([24a8612](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/24a8612f103ee16bc39bdeb40cdf9d2193c70ff2))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update digest busybox (db142d4 -&gt; 2919d01) ([#417](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/417)) ([8ab2e29](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8ab2e293b3bd7c97cabbbd9be486ce4c36d43d3f))

## [0.3.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.2.0...infra-networking-core-v0.3.0) (2024-11-23)


### ⚠ BREAKING CHANGES

* **infra-networking-extra:** move pihole + unbound + cloudflared-doh from networking-core to networking-extra ([#335](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/335))

### ✨ Features

* **infra-networking-core:** update madnuttah/unbound (1.20.0-5 -&gt; 1.22.0-1) ([#283](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/283)) ([93b15e7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/93b15e72b31958961576d66663624d747814bcf6))
* **infra-networking-core:** update visibilityspots/cloudflared (v2024.10.1 -&gt; v2024.11.0) ([#284](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/284)) ([ca72ce2](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ca72ce2fe9cfc08fa48cfc408b35aeee39b223a8))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** drop affinity setting for networking-core + networking-extra subsystem apps ([#337](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/337)) ([825192c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/825192c655ecf6fad55b1728f37fe5a6c0292924))
* **infra-networking-core:** update digest busybox (5b0f33c -&gt; db142d4) ([#314](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/314)) ([1897233](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1897233dc4b5695fa3b7b34cdce985c0075f68bf))
* **infra-networking-core:** update digest busybox (c230832 -&gt; 5b0f33c) ([#312](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/312)) ([b2c9660](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b2c96609233be7be7480499305b11796c9eef4b7))
* **infra-networking-core:** update visibilityspots/cloudflared (v2024.11.0 -&gt; v2024.11.1) ([#316](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/316)) ([0eb2535](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0eb2535419b3cb981456682c9f655c242fdb221f))
* **infra-networking-extra:** move pihole + unbound + cloudflared-doh from networking-core to networking-extra ([#335](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/335)) ([b1fe04a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b1fe04ad3d28a6674a5c7676a591590ec458d8ee))

## [0.2.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.1.2...infra-networking-core-v0.2.0) (2024-11-09)


### ⚠ BREAKING CHANGES

* **infra-networking-core:** update traefik (31.1.1 -> 32.1.1) ([#171](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/171))

### ✨ Features

* **infra-networking-core:** pihole should delegate resolution of external-dns created DNS records to router ([#233](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/233)) ([8d7def0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8d7def0175ba875de7e1183741d6e16ef209d276))
* **infra-networking-core:** update traefik (31.1.1 -&gt; 32.1.1) ([#171](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/171)) ([aa9f843](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/aa9f84310346284cee61cb48bcfa78b92ea29e10))
* **infra-networking-core:** update visibilityspots/cloudflared (v2024.9.1 -&gt; v2024.10.0) ([#164](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/164)) ([80f82f6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/80f82f615d5ff9fa32d6067f69d37bcc2d913e20))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** do not set hostname in pods as its unnecessary ([#231](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/231)) ([8aecce7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8aecce730c8f8e405188beb06fd27ec7a66e186f))
* **infra-networking-core:** fix pihole liveness check ([#232](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/232)) ([b4ccc4c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b4ccc4c9c121ba3d3b2624fa2143cf84ed4e05b1))
* **infra-networking-core:** make pihole-secrets optional ([#225](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/225)) ([fb7998a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/fb7998a89fcdeb99eef0a6dadf2d59d36d01b5d8))
* **infra-networking-core:** update digest visibilityspots/cloudflared (29a4be0 -&gt; 198ff93) ([#192](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/192)) ([41bab44](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/41bab44f0347baff2ef664156b45150e478696bd))
* **infra-networking-core:** update visibilityspots/cloudflared (v2024.10.0 -&gt; v2024.10.1) ([#191](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/191)) ([bc0495a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/bc0495a3c9ae9c7b8a4a34a4f2ac35465dfd1594))

## [0.1.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.1.1...infra-networking-core-v0.1.2) (2024-10-14)


### ✨ Features

* **infra-secrets-core:** move cert-manager from infra-networking-core to infra-secrets-core ([#153](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/153)) ([6889411](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6889411b6403504d82354d92e26f3f0502644c26))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** externalize external-dns provider configuration ([#156](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/156)) ([357b4f3](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/357b4f39a2335e258bf7042447bdc73d25a830e4))

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
