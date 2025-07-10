# Changelog

## [0.0.20](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.19...infra-kubernetes-extra-v0.0.20) (2025-07-10)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-core:** move node-feature-discovery + vpa from kubernetes-extra -&gt; kubernetes-core module ([#1726](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1726)) ([a189341](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a189341b330e7b0dca2ae05e9c6253bf1f19769c))

## [0.0.19](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.18...infra-kubernetes-extra-v0.0.19) (2025-07-09)


### 🚀 Enhancements + Bug Fixes

* move helmrepository resources into respective modules that depend on them ([#1691](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1691)) ([5eb5ab6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5eb5ab6491cdd48eb5a7d5413a04041258c5b8c5))

## [0.0.18](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.17...infra-kubernetes-extra-v0.0.18) (2025-07-06)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** revert not yet ready for prime time descheduler policy changes ([#1664](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1664)) ([eb1fc68](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/eb1fc6865bee76694a6067108d47390b37f2f9e0))
* **infra-kubernetes-extra:** update descheduler policy to reflect deprecation of metricsUtilization.metricsServer ([#1663](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1663)) ([c7910ad](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c7910adc2d276fcf502395734d69e965fe092cfa))
* **infra-kubernetes-extra:** update descheduler policy w/ excludes for dns and coder namespaces ([#1661](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1661)) ([74802fa](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/74802fa4db985ff009d219b9fa3900494e2e12e0))

## [0.0.17](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.16...infra-kubernetes-extra-v0.0.17) (2025-07-04)


### 🚀 Enhancements + Bug Fixes

* add defensive measure to prevent unintentional pruning of critical infrastructure components ([#1624](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1624)) ([f0f4901](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f0f4901cbab8f0f98876f5c881a823b96736d4b4))

## [0.0.16](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.15...infra-kubernetes-extra-v0.0.16) (2025-05-18)


### ✨ Features

* **infra-kubernetes-extra:** update descheduler (0.32.2 -&gt; 0.33.0) ([#1252](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1252)) ([2d98232](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2d98232aa21d0daeb3bb6408cf0d49ec25925479))


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update intel-device-plugins-gpu (0.32.0 -&gt; 0.32.1) ([#1275](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1275)) ([8a90338](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8a90338c657b96e5f3c4a3346d8e6dcb8fc59e4a))
* **infra-kubernetes-extra:** update intel-device-plugins-operator (0.32.0 -&gt; 0.32.1) ([#1276](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1276)) ([d739f5e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d739f5ea10fee21b2f7c70602bc8c0fa31040b2e))

## [0.0.15](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.14...infra-kubernetes-extra-v0.0.15) (2025-04-30)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update node-feature-discovery (0.17.2 -&gt; 0.17.3) ([#1159](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1159)) ([18ccf64](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/18ccf6475374718fade96574dc05f335d50d6249))

## [0.0.14](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.13...infra-kubernetes-extra-v0.0.14) (2025-03-26)


### 🛠 Improvements

* document module&lt;-&gt;app mapping and use app logos for each app ([#889](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/889)) ([6cb97bb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6cb97bb71826434291de7b067983830376f0d12b))


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update digest squat/generic-device-plugin (12fec77 -&gt; d7d0951) ([#930](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/930)) ([e8586cd](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e8586cd7817843d8fd7bf3769b1e14685adec8d2))
* **infra-kubernetes-extra:** update digest squat/generic-device-plugin (ba6f0b4 -&gt; 12fec77) ([#913](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/913)) ([eb166d9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/eb166d9ae26cbca1b949493c59525a78adcffe4a))

## [0.0.13](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.12...infra-kubernetes-extra-v0.0.13) (2025-02-26)


### 🛠 Improvements

* create initial documentation ([#833](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/833)) ([e5b84c0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e5b84c03920d34e3055bea987b465e04092af030))


### ✨ Features

* **infra-kubernetes-extra:** update intel-device-plugins-gpu (0.31.1 -&gt; 0.32.0) ([#716](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/716)) ([5cf2116](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5cf2116da2be48373282428f9d5a20318bed0766))
* **infra-kubernetes-extra:** update intel-device-plugins-operator (0.31.1 -&gt; 0.32.0) ([#717](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/717)) ([7f252eb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7f252eb47ee000f3c60f9d10f068d1ac44797950))


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update descheduler (0.32.1 -&gt; 0.32.2) ([#748](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/748)) ([bc5260b](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/bc5260b962b67782818f297e2393fa0f877a19a7))
* **infra-kubernetes-extra:** update node-feature-discovery (0.17.1 -&gt; 0.17.2) ([#848](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/848)) ([b9709f7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b9709f7d4dceeddc4a65e120e7bda079c84b5a9a))
* **infra-kubernetes-extra:** update vpa (4.7.1 -&gt; 4.7.2) ([#824](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/824)) ([20dc40a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/20dc40a732ec698a4d2b831f54f1cca8cb5199a1))

## [0.0.12](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.11...infra-kubernetes-extra-v0.0.12) (2025-01-19)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** tune default configuration for descheduler ([#631](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/631)) ([5b417e3](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5b417e3acb39e903acb846d8d3249a39339dd399))

## [0.0.11](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.10...infra-kubernetes-extra-v0.0.11) (2025-01-19)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update node-feature-discovery (0.17.0 -&gt; 0.17.1) ([#594](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/594)) ([200b6e5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/200b6e55ed6d1f9ca2f91ae75b87bc58b6e438df))
* remove node affinity preference for control plane nodes ([#614](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/614)) ([1766b6c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1766b6c5019b6faa22e29c77e44b29153318d60b))

## [0.0.10](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.9...infra-kubernetes-extra-v0.0.10) (2025-01-14)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** add required permissions for descheduler ([#583](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/583)) ([f2d3bed](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f2d3beda5f97c4fd7dfbba23ddcc50feec5c56f8))

## [0.0.9](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.8...infra-kubernetes-extra-v0.0.9) (2025-01-14)


### ✨ Features

* **infra-kubernetes-extra:** enable descheduler's pod evictions for low node utilization as per metrics ([#582](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/582)) ([ba8551a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ba8551a472f37d3a6c56af6b9be76b304641621d))


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update descheduler (0.32.0 -&gt; 0.32.1) ([#528](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/528)) ([13dd943](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/13dd94365d7f0dde815595ff4534199bc8c17262))

## [0.0.8](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.7...infra-kubernetes-extra-v0.0.8) (2025-01-03)


### ✨ Features

* **infra-kubernetes-extra:** update descheduler (0.31.0 -&gt; 0.32.0) ([#514](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/514)) ([8caee3e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8caee3e7dad8f5937467cb5622c73aa07120cc9e))
* **infra-kubernetes-extra:** update node-feature-discovery (0.16.6 -&gt; 0.17.0) ([#500](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/500)) ([5190d24](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5190d249f802edb019a9fb5d8682fd93b9b87818))

## [0.0.7](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.6...infra-kubernetes-extra-v0.0.7) (2024-12-17)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** metrics based LowNodeUtilization balancing in descheduler is not yet released ([#447](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/447)) ([603b7b7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/603b7b734bf78f93b9cbed633954669af478bfc6))

## [0.0.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.5...infra-kubernetes-extra-v0.0.6) (2024-12-17)


### ✨ Features

* **infra-kubernetes-extra:** add descheduler ([#443](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/443)) ([5af89e2](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5af89e21cfd8865f598cceb3c0bf03bdf502729a))

## [0.0.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.4...infra-kubernetes-extra-v0.0.5) (2024-11-17)


### ✨ Features

* **infra-kubernetes-extra:** add generic-device-plugin ([#295](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/295)) ([c89d977](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c89d977f8140b1dbacc0a364cbb620cc85914fb9))
* **infra-kubernetes-extra:** update vpa (4.6.0 -&gt; 4.7.0) ([#265](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/265)) ([9641960](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9641960b26453448e13095aec32f560c137ff409))


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update vpa (4.7.0 -&gt; 4.7.1) ([#268](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/268)) ([8eaca84](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8eaca841b3f3644ad514f50f90d95321598a14a1))

## [0.0.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.3...infra-kubernetes-extra-v0.0.4) (2024-11-10)


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-extra:** update intel-device-plugins-gpu (0.31.0 -&gt; 0.31.1) ([#172](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/172)) ([b358248](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b358248e4929fd96bafda79dce30b3c75d53bd49))
* **infra-kubernetes-extra:** update intel-device-plugins-operator (0.31.0 -&gt; 0.31.1) ([#173](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/173)) ([29df590](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/29df590798f1925e292de75a61de174d85d1e960))
* **infra-kubernetes-extra:** update node-feature-discovery (0.16.4 -&gt; 0.16.5) ([#158](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/158)) ([6ae2d2d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6ae2d2d456d0d12c65099403855bd130179f7373))
* **infra-kubernetes-extra:** update node-feature-discovery (0.16.5 -&gt; 0.16.6) ([#214](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/214)) ([1365ed8](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1365ed80f74f4ede2178d7bcf709a5bf6baa3c37))

## [0.0.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.2...infra-kubernetes-extra-v0.0.3) (2024-10-13)


### ✨ Features

* **infra-kubernetes-extra:** update intel-device-plugins-gpu (0.30.0 -&gt; 0.31.0) ([#109](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/109)) ([511a776](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/511a776d41fb1143b4b953aba229226ed6978147))
* **infra-kubernetes-extra:** update intel-device-plugins-operator (0.30.0 -&gt; 0.31.0) ([#110](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/110)) ([a8559b6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a8559b66421b9c5767bbfad620a6816921c55323))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-kubernetes-extra-v0.0.1...infra-kubernetes-extra-v0.0.2) (2024-10-07)


### ✨ Features

* **infra-kubernetes-extra:** add cluster capabilty for intel gpu devices w/ intel-gpu-device-plugin ([#42](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/42)) ([9c53c2c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9c53c2c89f3f130118765dcc3620cbc10cfcf2a9))
* **infra-kubernetes-extra:** update vpa (4.5.0 -&gt; 4.6.0) ([#47](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/47)) ([83b7539](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/83b7539151571d2a3c42b809655757c76b7f7b81))

## 0.0.1 (2024-09-21)


### ✨ Features

* **infra-kubernetes-extra:** add subsystem - infra-kubernetes-extra ([#22](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/22)) ([8316287](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8316287cfab78c574d3c64c3be6ef7b64bf5f9df))
