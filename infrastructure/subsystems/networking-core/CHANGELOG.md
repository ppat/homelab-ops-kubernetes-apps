# Changelog

## [0.7.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.7.1...infra-networking-core-v0.7.2) (2025-07-09)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** since traefik is a daemonset, we need a RWX volume and pod specific path within that ([#1713](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1713)) ([f1a78f7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f1a78f7c62a6c85160e82677b60f9da71dbb1320))
* **infra-networking-core:** traefik has container security context set on sidecar container but not on main container ([#1711](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1711)) ([72497c6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/72497c663d998050ce6fb6b19d25ca9dd41e4305))

## [0.7.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.7.0...infra-networking-core-v0.7.1) (2025-07-09)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** add liveness/readiness probes to whoami ([#1705](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1705)) ([65a4c84](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/65a4c84932db14456b6fc68c878fe53b1ffb8ee4))
* **infra-networking-core:** eliminate use of host paths in traefik and configure log rotation ([#1689](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1689)) ([1f43041](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1f430413ce3a405a0b267c9beec06e69c6243238))
* **infra-networking-core:** ensure that traefik can write to its logs pvc ([#1707](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1707)) ([f68ad07](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f68ad07852ecd845f7109869c2ccea834e5dc29b))
* move helmrepository resources into respective modules that depend on them ([#1691](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1691)) ([5eb5ab6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5eb5ab6491cdd48eb5a7d5413a04041258c5b8c5))

## [0.7.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.7...infra-networking-core-v0.7.0) (2025-07-08)


### ⚠ BREAKING CHANGES

* **infra-networking-core:** update traefik (35.4.0 -> 36.0.0) ([#1659](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1659))

### ✨ Features

* **infra-networking-core:** update traefik (35.4.0 -&gt; 36.0.0) ([#1659](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1659)) ([eca8645](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/eca86454ae0101d2679b5a49ef39bf0a3bf90a70))
* **infra-networking-core:** update traefik (36.0.0 -&gt; 36.1.0) ([#1667](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1667)) ([0470547](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0470547dfbe4a421cae155dda0da99f62ed0dfb0))
* **infra-networking-core:** update traefik (36.1.0 -&gt; 36.2.0) ([#1668](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1668)) ([f83439e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f83439ed64269a061ea081f0cd590482f7c6a9bb))
* **infra-networking-core:** update traefik (36.2.0 -&gt; 36.3.0) ([#1673](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1673)) ([0dc9bd1](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0dc9bd1a4ab8d0e86560e7d3683a4b783078ff5a))

## [0.6.7](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.6...infra-networking-core-v0.6.7) (2025-07-04)


### 🚀 Enhancements + Bug Fixes

* add defensive measure to prevent unintentional pruning of critical infrastructure components ([#1624](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1624)) ([f0f4901](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f0f4901cbab8f0f98876f5c881a823b96736d4b4))

## [0.6.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.5...infra-networking-core-v0.6.6) (2025-06-25)


### ✨ Features

* **infra-networking-core:** update external-dns (1.16.1 -&gt; 1.17.0) ([#1523](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1523)) ([6c5a223](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6c5a2239f77b6ab386e79ae8522e3fe829a29a16))

## [0.6.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.4...infra-networking-core-v0.6.5) (2025-06-20)


### 🚀 Enhancements + Bug Fixes

* create kustomize component for configuring different external-dns provider(s) ([#1450](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1450)) ([93bcd28](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/93bcd28846d5ccfc8dff32731c150489d42a2219))
* **infra-networking-core:** fix the default-tls-cert to be used by traefik ingress ([#1488](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1488)) ([6b13e32](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6b13e32cf45e0866bae2c537d536554e4f7a51d3))

## [0.6.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.3...infra-networking-core-v0.6.4) (2025-06-15)


### ✨ Features

* **infra-networking-core:** update metallb (0.14.9 -&gt; 0.15.0) ([#1418](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1418)) ([f316179](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f316179d2d58fbab800cc71237a201f20782abcf))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update metallb (0.15.0 -&gt; 0.15.2) ([#1421](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1421)) ([c93a655](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c93a655ca7e6c9d089d5f237596f8a1811100745))

## [0.6.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.2...infra-networking-core-v0.6.3) (2025-05-31)


### ✨ Features

* **infra-networking-core:** update traefik (35.3.0 -&gt; 35.4.0) ([#1354](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1354)) ([0b9ee66](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0b9ee6679c3a11494ce2d86ab53915c747a9972a))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update digest busybox (f64ff79 -&gt; f85340b) ([#1356](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1356)) ([664a3ce](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/664a3ce4a3e38fd85d807b26b53f258f842fcc17))

## [0.6.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.1...infra-networking-core-v0.6.2) (2025-05-26)


### ✨ Features

* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.5.2 -&gt; v0.6.0) ([#1324](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1324)) ([0eeec87](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0eeec8761e0562658c011769c976e312fd914ef1))
* **infra-networking-core:** update traefik (35.2.0 -&gt; 35.3.0) ([#1328](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1328)) ([83f5be2](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/83f5be2fb006a78105466f0b1d30cac2f0b22c3b))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update digest busybox (37f7b37 -&gt; f64ff79) ([#1318](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1318)) ([2c19a62](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2c19a62b48cdd182c11af50c6f9de4c4cf3c47e1))

## [0.6.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.6.0...infra-networking-core-v0.6.1) (2025-05-11)


### ✨ Features

* **infra-networking-core:** update traefik (35.0.0 -&gt; 35.1.0) ([#1234](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1234)) ([4b77c0e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/4b77c0e28bf2689bc722a29d2658d08afd329cb0))
* **infra-networking-core:** update traefik (35.1.0 -&gt; 35.2.0) ([#1235](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1235)) ([159a121](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/159a121e7ae557fb7f24f0915d96a128aab7aba5))

## [0.6.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.9...infra-networking-core-v0.6.0) (2025-05-09)


### ⚠ BREAKING CHANGES

* **infra-networking-core:** update traefik (34.5.0 -> 35.0.0) ([#1218](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1218))

### ✨ Features

* **infra-networking-core:** update traefik (34.5.0 -&gt; 35.0.0) ([#1218](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1218)) ([764193e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/764193e1e936e840e10af1d50025adc1fba5ae22))

## [0.5.9](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.8...infra-networking-core-v0.5.9) (2025-04-24)


### 🛠 Improvements

* misc corrections to docs ([#1136](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1136)) ([b8e5ad5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b8e5ad5356f5468db09444edaa86e27a44379688))


### ✨ Features

* **infra-networking-core:** update external-dns (1.15.2 -&gt; 1.16.1) ([#1003](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1003)) ([d6b2d48](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d6b2d489f482c38f1149dabf5da82af717eb01db))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-extra:** move cloudflared, pihole and unbound from pihole -&gt; dns namespace ([#1141](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1141)) ([e09e11b](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e09e11b6ce8702662a3ee154d0ebaebb7c392f71))

## [0.5.8](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.7...infra-networking-core-v0.5.8) (2025-04-13)


### ✨ Features

* **infra-networking-core:** update traefik (34.4.1 -&gt; 34.5.0) ([#1061](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1061)) ([ccb9588](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ccb9588acec0c75557cba300404c796dfd4de26b))

## [0.5.7](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.6...infra-networking-core-v0.5.7) (2025-04-10)


### ✨ Features

* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.4.3 -&gt; v0.5.0) ([#978](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/978)) ([26af932](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/26af93289b26b7901ff3046bb44b8514fc679b35))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update digest busybox (498a000 -&gt; 37f7b37) ([#970](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/970)) ([f1c46d0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f1c46d0fa9466c415fcf798006d4f55d91cf0de9))
* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.5.0 -&gt; v0.5.1) ([#980](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/980)) ([09e6c8a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/09e6c8a6eba22b2cb3e00fc25becf814b64bb433))
* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.5.1 -&gt; v0.5.2) ([#1038](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/1038)) ([fa2b61f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/fa2b61f1336f254f91aab7b70e6dd0ccdd5eb6a7))

## [0.5.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.5...infra-networking-core-v0.5.6) (2025-03-16)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.4.2 -&gt; v0.4.3) ([#919](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/919)) ([725f26d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/725f26dc94580ba4767f89f4bc3e4224a1921f79))

## [0.5.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.4...infra-networking-core-v0.5.5) (2025-03-07)


### 🛠 Improvements

* document module&lt;-&gt;app mapping and use app logos for each app ([#889](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/889)) ([6cb97bb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6cb97bb71826434291de7b067983830376f0d12b))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update traefik (34.4.0 -&gt; 34.4.1) ([#904](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/904)) ([8fcefbc](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/8fcefbc9d85dd52df2146abf680ab2241a206033))

## [0.5.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.3...infra-networking-core-v0.5.4) (2025-03-01)


### ✨ Features

* **infra-networking-core:** update traefik (34.3.0 -&gt; 34.4.0) ([#860](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/860)) ([49cdbea](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/49cdbea365b31f5e8e77af9ff7934c1ef0774970))

## [0.5.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.2...infra-networking-core-v0.5.3) (2025-02-23)


### 🛠 Improvements

* create initial documentation ([#833](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/833)) ([e5b84c0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e5b84c03920d34e3055bea987b465e04092af030))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update digest busybox (a5d0ce4 -&gt; 498a000) ([#826](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/826)) ([c717579](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c7175798f75b1ea34e015cffbbe9a9fc5717805a))
* **infra-networking-core:** update external-dns (1.15.1 -&gt; 1.15.2) ([#798](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/798)) ([a5d0fc5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a5d0fc5cab2b8fe9482f8e0c5028af51ab0f80cd))
* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.4.1 -&gt; v0.4.2) ([#828](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/828)) ([1384782](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1384782f41b462c8a6c30b7ee97ea07225ab43e0))

## [0.5.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.1...infra-networking-core-v0.5.2) (2025-02-15)


### ✨ Features

* **infra-networking-core:** update traefik (34.2.0 -&gt; 34.3.0) ([#791](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/791)) ([7d9f576](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7d9f576e9714868f21f8a66db7c00fef29b9be9f))

## [0.5.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.5.0...infra-networking-core-v0.5.1) (2025-02-13)


### ✨ Features

* **infra-networking-core:** update traefik (34.0.0 -&gt; 34.2.0) ([#778](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/778)) ([c035d9a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c035d9a51fcf35d5efe528956061775ebaa0d5bc))

## [0.5.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.4.6...infra-networking-core-v0.5.0) (2025-02-13)


### ⚠ BREAKING CHANGES

* **infra-networking-core:** update traefik (33.2.1 -> 34.0.0) ([#753](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/753))

### ✨ Features

* **infra-networking-core:** update traefik (33.2.1 -&gt; 34.0.0) ([#753](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/753)) ([dc8ccce](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/dc8ccce467fa0fc900c316d29df3f419b3f1e9d9))

## [0.4.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.4.5...infra-networking-core-v0.4.6) (2025-02-01)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update external-dns (1.15.0 -&gt; 1.15.1) ([#672](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/672)) ([284604f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/284604f3b52c7140817dd45b54e9f95f2a09e4a2))
* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.4.0 -&gt; v0.4.1) ([#685](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/685)) ([0d95831](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0d95831e06bae1c723b3fe6163939ec73acac6eb))

## [0.4.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.4.4...infra-networking-core-v0.4.5) (2025-01-23)


### ✨ Features

* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.3.4 -&gt; v0.4.0) ([#628](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/628)) ([a476c3a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a476c3ae484f1cbcd94b4b4d2af4594b41023386))


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update digest traefik/whoami (43a68d1 -&gt; 1699d99) ([#642](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/642)) ([5967385](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5967385e96ce7dbb3158075b258587708426d692))

## [0.4.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.4.3...infra-networking-core-v0.4.4) (2025-01-19)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** update kashalls/external-dns-unifi-webhook (v0.3.1 -&gt; v0.3.4) ([#627](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/627)) ([59f5de0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/59f5de06fb7d6b3eadfec90f784008b8051c1869))

## [0.4.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-networking-core-v0.4.2...infra-networking-core-v0.4.3) (2025-01-19)


### 🚀 Enhancements + Bug Fixes

* **infra-networking-core:** fix external-dns unifi webhook provider config ([#629](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/629)) ([9e32a97](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9e32a97f392275a28b37fbdfd1fd8d5fc653ab26))

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
