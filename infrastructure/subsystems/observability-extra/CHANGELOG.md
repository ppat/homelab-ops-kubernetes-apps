# Changelog

## [0.0.9](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.8...infra-observability-extra-v0.0.9) (2025-01-16)


### 🚀 Enhancements + Bug Fixes

* **infra-observability-extra:** update ghcr.io/unpoller/unpoller (v2.14.0 -&gt; v2.14.1) ([#596](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/596)) ([c3a2836](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c3a283633496f212fc4823d3069e72abaf65822a))
* **infra-observability-extra:** update kubernetes-event-exporter (3.3.0 -&gt; 3.3.1) ([#587](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/587)) ([91b7e1d](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/91b7e1dc40494c8f692c2ed1d81e41cd99547dac))

## [0.0.8](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.7...infra-observability-extra-v0.0.8) (2025-01-14)


### 🚀 Enhancements + Bug Fixes

* **infra-observability-extra:** syslogng should not reverse lookup dns as its more accurate to have source specify host ([#580](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/580)) ([5bfda0a](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/5bfda0a29e54f19bf4e0d97212e9ac97130f208f))

## [0.0.7](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.6...infra-observability-extra-v0.0.7) (2025-01-13)


### 🚀 Enhancements + Bug Fixes

* **infra-observability-core:** switch from loki-gateway to use of a simple k8s ingress ([#571](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/571)) ([a09a3e4](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/a09a3e4c97c3fd0d69bd03f2f81c353b803a17f0))
* **infra-observability-core:** syslogng should reverse lookup ip addresses of remote hosts ([#569](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/569)) ([86b1e09](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/86b1e09e7e6f710a41ee01f30546281e92588b08))

## [0.0.6](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.5...infra-observability-extra-v0.0.6) (2025-01-11)


### ✨ Features

* **infra-observability-extra:** update ghcr.io/unpoller/unpoller (v2.13.1 -&gt; v2.14.0) ([#554](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/554)) ([b63fc13](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b63fc132c1a570f1b66beaf61e6365d1289151c0))

## [0.0.5](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.4...infra-observability-extra-v0.0.5) (2025-01-03)


### ✨ Features

* **infra-observability-extra:** update ghcr.io/unpoller/unpoller (v2.11.2 -&gt; v2.13.1) ([#509](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/509)) ([e94f6b4](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/e94f6b459e3923c32c83aee44cd2b9373d0cc7ae))

## [0.0.4](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.3...infra-observability-extra-v0.0.4) (2024-12-27)


### ✨ Features

* **infra-observability-extra:** update kubernetes-event-exporter (3.2.16 -&gt; 3.3.0) ([#454](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/454)) ([637e7ae](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/637e7ae2e269f9e4c100c31bf8e1616af036ae2e))

## [0.0.3](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.2...infra-observability-extra-v0.0.3) (2024-12-17)


### ✨ Features

* **infra-observability-extra:** add node-problem-detector ([#446](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/446)) ([ae7a2c6](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ae7a2c622229e39ee9cade5dba6940cb48725282))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-extra:** update kubernetes-event-exporter (3.2.15 -&gt; 3.2.16) ([#385](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/385)) ([7cf716e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7cf716e1f68e8a2db4eb857e844ae95f22f08d4a))

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-observability-extra-v0.0.1...infra-observability-extra-v0.0.2) (2024-11-10)


### ✨ Features

* **infra-observability-extra:** update prometheus-snmp-exporter (5.5.1 -&gt; 5.6.0) ([#183](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/183)) ([0ac109c](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0ac109c6cc1ad8044f5801a3f607e8aeece28628))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-extra:** add nodeselector for syslogng requiring an amd64 node ([#221](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/221)) ([4d3c376](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/4d3c376cc20b8b316f79205d2018cd034cdb657c))
* **infra-observability-extra:** do not crowd control plane nodes with kubernetes-event-exporter services ([#240](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/240)) ([895a805](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/895a805c8e68ca7705a00bdd4950f32efd3b3eb1))
* **infra-observability-extra:** update kubernetes-event-exporter (3.2.14 -&gt; 3.2.15) ([#228](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/228)) ([0af0de7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0af0de7e5d10345ae6c1ac93de9645558e6f2fc2))

## 0.0.1 (2024-10-13)


### ⚠ BREAKING CHANGES

* **infra-observability-extra:** move kubernetes-event-exporter + syslog-ng to new subsystem ([#117](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/117))

### ✨ Features

* **infra-observability-extra:** add snmp-exporter within a new subsystem ([#115](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/115)) ([9f5440f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9f5440f195baeef66b5b647e3b18fc61c1c32290))
* **infra-observability-extra:** export unifi network application metrics with unpoller ([#148](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/148)) ([3f251a2](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/3f251a28947d6d1667496f28fe184ff5004e8759))


### 🚀 Enhancements + Bug Fixes

* **infra-observability-extra:** move kubernetes-event-exporter + syslog-ng to new subsystem ([#117](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/117)) ([ed250eb](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ed250eb53d0dc51f0fa677a546b2fa71c5e0c8bd))
* **infra-observability-extra:** update kubernetes-event-exporter (3.2.13 -&gt; 3.2.14) ([#121](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/121)) ([26c4326](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/26c43266201d211e8f9f6aa84ae71ba5f8994c2b))
