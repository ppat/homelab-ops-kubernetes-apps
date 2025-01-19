# Changelog

## [0.4.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.4.0...infra-observability-core-v0.4.1) (2025-01-19)


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** update grafana (8.8.3 -&gt; 8.8.4) ([#611](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/611)) ([7181ad3](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7181ad315b26ad7324f825eb7c8861c9e411970b))
* **infra-observability-core:** update loki (6.24.0 -&gt; 6.24.1) ([#609](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/609)) ([2384eed](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2384eedee700e59bb37c0817c49fed66102336bc))

## [0.4.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.3.4...infra-observability-core-v0.4.0) (2025-01-16)


### ⚠ BREAKING CHANGES

* **infra-observability-core:** update kube-prometheus-stack (67.9.0 -> 68.1.1) ([#600](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/600))

### ✨ Features

* **infra-observability-core:** update kube-prometheus-stack (67.9.0 -&gt; 68.1.1) ([#600](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/600)) ([ad4e001](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ad4e001cd137c40901ffba822779da1c8010bf46))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** update grafana (8.8.2 -&gt; 8.8.3) ([#598](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/598)) ([932328a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/932328a525aec7e838d3a418762fabe610cfb7ea))

## [0.3.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.3.3...infra-observability-core-v0.3.4) (2025-01-14)


### ✨ Features

* **infra-observability-core:** specify extra ports for promtail in promtail-extra-config ([#576](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/576)) ([1099508](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/109950824e92bbab3ef14ec2d66fffca73acf1cd))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** automatically restart loki/promtail deployments/daemonsets if configmaps change ([#574](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/574)) ([c4b4785](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c4b4785ea4e71ebbf9c1b4a64f3e2db6685ceacd))
* **infra-observability-core:** clean up unnecessary/no-op configuration in flux helm releases ([#579](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/579)) ([c17e286](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c17e2867991e93ec68a90e3dfc92d7d9608caf23))
* **infra-observability-core:** updating loki/promtail updates when configmaps change requires a helm release ([#577](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/577)) ([865c8f6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/865c8f647620339c375e04b834aee11c8d9c823d))

## [0.3.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.3.2...infra-observability-core-v0.3.3) (2025-01-13)


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** streamline how system log scrape configuration is defined ([#573](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/573)) ([3c6ed99](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/3c6ed99ea7af25b480512baa11196c36fe074483))
* **infra-observability-core:** switch from loki-gateway to use of a simple k8s ingress ([#571](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/571)) ([a09a3e4](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a09a3e4c97c3fd0d69bd03f2f81c353b803a17f0))

## [0.3.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.3.1...infra-observability-core-v0.3.2) (2025-01-09)


### ✨ Features

* **infra-observability-core:** update kube-prometheus-stack (67.5.0 -&gt; 67.9.0) ([#533](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/533)) ([8546458](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/854645875d3691e5a57ee81319c9bd25cfe044cc))

## [0.3.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.3.0...infra-observability-core-v0.3.1) (2024-12-27)


### ✨ Features

* **infra-observability-core:** update kube-prometheus-stack (67.3.1 -&gt; 67.4.0) ([#486](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/486)) ([b8e37c0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b8e37c08bdfaff6833344a4ca0c750e706a05df2))
* **infra-observability-core:** update kube-prometheus-stack (67.4.0 -&gt; 67.5.0) ([#488](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/488)) ([48b00fe](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/48b00fea68b8976385c08376fe78d3dad311b6a0))
* **infra-observability-core:** update loki (6.23.0 -&gt; 6.24.0) ([#484](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/484)) ([b5efaed](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b5efaed2ed593fd43ec3da5d78824a76847b51e8))

## [0.3.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.2.2...infra-observability-core-v0.3.0) (2024-12-19)


### ⚠ BREAKING CHANGES

* **infra-observability-core:** update kube-prometheus-stack (66.4.0 -> 67.3.1) ([#453](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/453))

### ✨ Features

* **infra-observability-core:** update grafana (8.6.4 -&gt; 8.8.2) ([#452](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/452)) ([6e09db8](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6e09db8da36d1ddbb022879888aee6062c2b063b))
* **infra-observability-core:** update kube-prometheus-stack (66.4.0 -&gt; 67.3.1) ([#453](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/453)) ([a858a53](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a858a530425832699de79ebad110065d33024fba))

## [0.2.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.2.1...infra-observability-core-v0.2.2) (2024-12-13)


### ✨ Features

* **infra-observability-core:** update kube-prometheus-stack (66.2.2 -&gt; 66.3.0) ([#402](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/402)) ([5e135bd](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5e135bde572ced7cbabf783dc23e9cbe2c89dc38))
* **infra-observability-core:** update kube-prometheus-stack (66.3.1 -&gt; 66.4.0) ([#426](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/426)) ([24ede18](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/24ede18906296e44db0d2c83a1a2ed575270db52))
* **infra-observability-core:** update loki (6.21.0 -&gt; 6.23.0) ([#403](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/403)) ([03edb37](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/03edb37aea583be3553d7907ed831d49cd9b55fc))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** update grafana (8.6.1 -&gt; 8.6.3) ([#368](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/368)) ([fca6faf](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/fca6fafd3f559e2fd9c1d907e19b365d0b981e17))
* **infra-observability-core:** update grafana (8.6.3 -&gt; 8.6.4) ([#389](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/389)) ([fe4673f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/fe4673f67b4928568f447120751c84c8dd48d86b))
* **infra-observability-core:** update kube-prometheus-stack (66.2.1 -&gt; 66.2.2) ([#369](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/369)) ([446bbb5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/446bbb54a95801d26e81578b70b1549b90c8fc9c))
* **infra-observability-core:** update kube-prometheus-stack (66.3.0 -&gt; 66.3.1) ([#412](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/412)) ([ddf896d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ddf896d70171e2d85b5e2ca053a5823860487a06))

## [0.2.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.2.0...infra-observability-core-v0.2.1) (2024-11-24)


### ✨ Features

* **infra-observability-core:** update grafana (8.5.12 -&gt; 8.6.1) ([#326](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/326)) ([b166892](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b166892a71ac6a8ad66b3d93d47dce93ed93170b))
* **infra-observability-core:** update loki (6.18.0 -&gt; 6.21.0) ([#327](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/327)) ([a89cc29](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a89cc299986a80c983f744f3e5c03762f7eeb084))

## [0.2.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.1.2...infra-observability-core-v0.2.0) (2024-11-18)


### ⚠ BREAKING CHANGES

* **infra-observability-core:** update kube-prometheus-stack (65.8.1 -> 66.2.1) ([#291](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/291))

### ✨ Features

* **infra-observability-core:** update kube-prometheus-stack (65.8.1 -&gt; 66.2.1) ([#291](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/291)) ([6985b3f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6985b3f1644a720f7cbb0365c744c76ccd61cf1d))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** remove affinity settings from loki config ([#275](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/275)) ([a134f95](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a134f95d4a38dd9bfa873ef18aaf1ea1cf6634e2))

## [0.1.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.1.1...infra-observability-core-v0.1.2) (2024-11-10)


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** do not crowd control plane nodes with kube-prometheus-stack services ([#236](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/236)) ([e656d3d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e656d3d03cb32f190e5dc2ae66502f69214c3db0))

## [0.1.1](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.1.0...infra-observability-core-v0.1.1) (2024-11-10)


### ✨ Features

* **infra-observability-core:** update kube-prometheus-stack (65.1.1 -&gt; 65.2.0) ([#182](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/182)) ([907c81a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/907c81aa03602e22b012b6cb28c89f8f1dafc02d))
* **infra-observability-core:** update kube-prometheus-stack (65.2.0 -&gt; 65.3.2) ([#168](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/168)) ([852f3b9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/852f3b9922f853f71867cbfbe2f4cf1cec6e7f3b))
* **infra-observability-core:** update kube-prometheus-stack (65.3.2 -&gt; 65.4.0) ([#197](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/197)) ([904affe](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/904affef74077260465ff022b1a4fcf780b1d3b6))
* **infra-observability-core:** update kube-prometheus-stack (65.4.0 -&gt; 65.8.1) ([#235](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/235)) ([d5d4d59](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d5d4d59fa4f21fb7c7178cb08ffa504b605de11c))
* **infra-observability-core:** update loki (6.12.0 -&gt; 6.16.0) ([#135](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/135)) ([133589e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/133589eddcb9b992d3d96282e09842ba54dbd632))
* **infra-observability-core:** update loki (6.16.0 -&gt; 6.18.0) ([#169](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/169)) ([aeb6ba5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/aeb6ba5852252abbb6b1dc3ee810fa053b487892))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** update grafana (8.5.11 -&gt; 8.5.12) ([#234](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/234)) ([47d87cb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/47d87cb01bb54f8560c493c967b4ddf2c2479665))
* **infra-observability-core:** update grafana (8.5.2 -&gt; 8.5.3) ([#167](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/167)) ([03cf4a3](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/03cf4a3f99d4d476ff4df8377a67a4efe02fc47f))
* **infra-observability-core:** update grafana (8.5.3 -&gt; 8.5.6) ([#181](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/181)) ([a9b59b0](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a9b59b0236647140a8dc2f8e5da02a7f2168ec4c))
* **infra-observability-core:** update grafana (8.5.6 -&gt; 8.5.8) ([#195](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/195)) ([4b1c4c9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/4b1c4c9435c4db751f9ea682ddcccbf476b1c5fa))
* **infra-observability-core:** update grafana (8.5.8 -&gt; 8.5.11) ([#223](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/223)) ([743627d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/743627d191ee494e7974103ed546147ca9efb05c))

## [0.1.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.0.2...infra-observability-core-v0.1.0) (2024-10-13)


### ⚠ BREAKING CHANGES

* **infra-observability-core:** update kube-prometheus-stack (62.7.0 -> 65.1.1) ([#136](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/136))
* **infra-observability-extra:** move kubernetes-event-exporter + syslog-ng to new subsystem ([#117](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/117))

### ✨ Features

* **infra-observability-core:** update kube-prometheus-stack (62.7.0 -&gt; 65.1.1) ([#136](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/136)) ([49d05cb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/49d05cbf666382799ef8741b7a1d222bdb827101))
* sync bitwarden-secret webhook's CA cert to all namespaces that will need to fetch secrets ([#141](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/141)) ([2c161b6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2c161b6d3aad70a8e7924c3dc407e504d13cab23))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** drop high cardinality prometheus metrics for k3s ([#149](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/149)) ([372e8c7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/372e8c72f6ed9bc78b8b939aa48ca9062f066820))
* **infra-observability-core:** drop promtail's syslog-receiver + separate syslog-ng sources into rfc3164 and rfc5424 ([#113](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/113)) ([30414fe](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/30414fe039dd61ce1d7272b54f584d3f20c71490))
* **infra-observability-core:** tune prometheus settings ([#118](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/118)) ([d7d8221](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d7d8221d6dd96d4867a51058a83b8b79586e9456))
* **infra-observability-core:** update grafana (8.5.1 -&gt; 8.5.2) ([#120](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/120)) ([d8810f9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d8810f96496f2900f0f3de384883eddc48633b7b))
* **infra-observability-extra:** move kubernetes-event-exporter + syslog-ng to new subsystem ([#117](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/117)) ([ed250eb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ed250eb53d0dc51f0fa677a546b2fa71c5e0c8bd))
* **infra-secrets-core:** sync bitwarden-ca-cert as configmap only to external-secrets namespace (not others) ([#145](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/145)) ([79f88a6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/79f88a6e166da979d0ca4ebcbff04f821ac10ae5))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-core-v0.0.1...infra-observability-core-v0.0.2) (2024-10-07)


### ✨ Features

* **infra-observability-core:** add kubernetes-event-exporter and grafana dashboard ([#100](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/100)) ([9a54d0b](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9a54d0bece65f3f24a5c113c74ca7e07bda030f1))
* **infra-observability-core:** add prometheus rule to promtail ([#89](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/89)) ([a3b8514](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a3b85141a76f3356943723e8b6440db240518313))
* **infra-observability-core:** add syslogng as a forwarder to promtail ([#92](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/92)) ([bad7623](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/bad76233f2fec0e0ac55402743c611b205431e4d))
* **infra-observability-core:** configure promtail as a remote syslog receiver ([#90](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/90)) ([e489f45](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e489f452bff3696624823cc0bca83265e15b0fc0))
* **infra-observability-core:** configure retention for loki ([#55](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/55)) ([48fc26a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/48fc26a6fcda76c5d8cc545b46227cd67fb493e9))
* **infra-observability-core:** update loki (6.10.2 -&gt; 6.11.0) ([#87](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/87)) ([87d57f6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/87d57f622f0476bd59a2b3bfd146f4b2a9409529))
* **infra-observability-core:** update loki (6.11.0 -&gt; 6.12.0) ([#97](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/97)) ([bec8538](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/bec8538830b15eb7e2049220bd905df8a433be0f))


### 🚀 Enhancements + Bug Fixes

* **infra-kubernetes-core:** update coredns to log all requests, not just errors ([#56](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/56)) ([2098267](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2098267f98e8ad2e6863844d8a58ab2a57cad41f))
* **infra-observability-core:** adjust promotail syslog receiver config ([#108](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/108)) ([0e19c9d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0e19c9d510b2ae05a913a1fd6d8acbfddca6a38b))
* **infra-observability-core:** configure alertmanager in loki's ruler + enable canary/test for test purposes only ([#82](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/82)) ([e73e90f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e73e90f8a1468c06341c165be07eeb35822fa48a))
* **infra-observability-core:** externalize grafana dashboard + plugin configuration ([#84](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/84)) ([2a1a00d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/2a1a00d9a98326026246820eecdce4d257d74a1b))
* **infra-observability-core:** externalize loki's individual stream retention config ([#83](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/83)) ([d5ad6b5](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d5ad6b5ad80b218ec70aae6031b2b8f1c12faccc))
* **infra-observability-core:** externalize promtail extra configuration ([#88](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/88)) ([1a820c9](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1a820c99e7188480b3c2669f1f6e71053f95e8f5))
* **infra-observability-core:** fix incorrect reference to longhorn dashboard ([#66](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/66)) ([d7e9961](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/d7e99615fd8f39cb9b964e74dee69971642bdd4a))
* **infra-observability-core:** fix promtail's rsyslog receiver ([#91](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/91)) ([0f4db66](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0f4db66f0031a91160d8faa8d9b9dc6bdfb656c0))
* **infra-observability-core:** syslog should log its own errors to loki ([#98](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/98)) ([1842ab7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/1842ab7389f8f9bfbd8919a2f7ed662db6a2d5a7))
* **infra-observability-core:** update external-secrets/external-secrets (v0.10.3 -&gt; v0.10.4) ([#52](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/52)) ([a6f2d1d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a6f2d1d3dcab01195e9a2015b6fe4a013eb89d1e))
* **infra-observability-core:** update promtail (6.16.5 -&gt; 6.16.6) ([#46](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/46)) ([ca02c59](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ca02c598d3ad3ed8a9cd182dd01a746da5657512))
* misc refactor for consistency ([#93](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/93)) ([b3ed60e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b3ed60eefbec76e997b0fd5d3d527217a50742ac))

## 0.0.1 (2024-09-21)


### ✨ Features

* **infra-observability-core:** add subsystem - infra-observability-core ([#18](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/18)) ([20f2056](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/20f2056ae9f70bba7e908fbc89ad94d17b83e10b))
