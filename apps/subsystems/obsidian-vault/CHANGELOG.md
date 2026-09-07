# Changelog

## [0.1.0](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/apps-obsidian-vault-v0.0.1...apps-obsidian-vault-v0.1.0) (2026-09-07)


### ⚠ BREAKING CHANGES

* **apps-obsidian-vault:** the watchdog's args become watch-agent-instance and both workloads require the new BATCH_AGENT_INSTANCE_* environment. This module and the obsidian-tools release that introduces that subcommand are not independently deployable in either direction, so the image pin must be bumped to that release before this lands.

### ✨ Features

* **apps-obsidian-vault:** give batch mode scaling authority over the agent MCP server alone ([#3972](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/3972)) ([9645c21](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/9645c21de16d145df4f75b70ae41274a29491489))


### 🚀 Enhancements + Bug Fixes

* **apps-obsidian-vault:** reference the Bitwarden name Terraform generates for batch-processor's gateway key ([#3971](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/3971)) ([04a6747](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/04a674745fe5dea4b67a9fe5516f35349f0e00e5))

## 0.0.1 (2026-09-06)


### ✨ Features

* extract the knowledge vault and its work queue into their own apps-obsidian-vault module ([#3967](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/3967)) ([f3cb3a7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f3cb3a790facf9eef5d7739cedd82947199602db))
