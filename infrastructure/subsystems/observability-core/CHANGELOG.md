# Changelog

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
