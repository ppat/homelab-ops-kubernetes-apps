# Coder Subsystem

Self-hosted development environment platform enabling secure, reproducible, and Kubernetes-native workspaces for development.

## Quick Links

<a href="https://coder.com/docs/about" target="_blank"><img src="../../../.static/images/logos/coder.svg" width="32" height="32" alt="Coder"></a>

## Overview

The coder subsystem consists of three main capability groups:

1. Workspace Management
   - Development environment provisioning
   - Resource allocation
   - Access control
   - Workspace templates

2. Platform Infrastructure
   - State persistence
   - Authentication
   - Metrics collection
   - Network access
   - Alert conditions on coderd health and Postgres liveness/connection saturation -- queryable state only, since this estate has no AlertManager routing configured

3. Security Controls
   - RBAC management
   - TLS encryption
   - Workspace isolation
   - Resource limits

### Component Details

| Component       | Type           | Primary Role        | Key Features                                                                                                                                                                                                                                                                                          | Integration Points                                                                              |
| --------------- | -------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Coder Server    | Core           | Platform Control    | • Workspace provisioning<br>• Template management<br>• Access control<br>• Resource orchestration<br>• `PrometheusRule` alerting on coderd pod restarts, scoped to the control-plane pod (not workspace pods) by an owning-Deployment join since this namespace has no pod-label metrics to select on | • PostgreSQL state storage<br>• OIDC authentication<br>• Prometheus metrics<br>• Kubernetes API |
| PostgreSQL      | Infrastructure | State Storage       | • Platform state persistence<br>• User data management<br>• Workspace metadata<br>• High availability support<br>• `PrometheusRule` alerting on per-instance and all-instance liveness and connection saturation, translated from postgres_exporter naming onto CloudNativePG's own exporter metrics  | • Coder server integration<br>• Automated failover<br>• Metrics collection                      |
| OIDC Provider   | Security       | Authentication      | • Identity management<br>• Session control<br>• Token handling<br>• User authorization                                                                                                                                                                                                                | • Coder server integration<br>• External provider support<br>• Session management               |
| Workspace Agent | Runtime        | Environment Control | • Development environment<br>• Resource management<br>• Connection handling<br>• Tool integration                                                                                                                                                                                                     | • Coder server communication<br>• Kubernetes resources<br>• Template execution                  |

## Prerequisites

1. Persistent Storage

   | PVC Name       | Purpose               | Access Mode |
   | -------------- | --------------------- | ----------- |
   | coder-db-data  | PostgreSQL data       | RWO         |
   | workspace-data | Per-workspace storage | RWX         |

2. Required Secrets

   | Secret Name           | Purpose             | Required Keys          |
   | --------------------- | ------------------- | ---------------------- |
   | coder-db-app          | Database connection | uri                    |
   | coder-sso-credentials | OIDC configuration  | clientId, clientSecret |

3. Required Variables

   | Variable         | Purpose             | Used By      |
   | ---------------- | ------------------- | ------------ |
   | domain_name      | External access URL | Coder server |
   | db_storage_size  | Database storage    | PostgreSQL   |
   | db_storage_class | Storage class       | PostgreSQL   |

4. RBAC Requirements

   | Resource    | Access                                   | Purpose                |
   | ----------- | ---------------------------------------- | ---------------------- |
   | configmaps  | create, delete, get, list, update, watch | Workspace management   |
   | deployments | create, delete, get, list, update        | Workspace provisioning |

## Notes

- **The coderd `PrometheusRule`'s highest-value condition, workspace build failures, is dormant until this module is released and deployed, not because anything is unwired in-repo.** `service-coder-metrics.yaml` and `servicemonitor-coder.yaml` (below) already expose and scrape coderd's `:2112` metrics endpoint, so `coderd_workspace_builds_total` will reach Prometheus once that config actually reaches the cluster -- this is a module-library repo, so merging to `main` deploys nothing by itself; it takes a release-please `apps-coder-vX.Y.Z` tag plus a bump of the clusters repo's `apps-coder` `GitRepository` pin to that tag. The `CoderdWorkspaceBuildFailures` rule is kept (dormant) rather than dropped, since a broken template silently failing every build is exactly the failure mode worth alerting on. CPU/memory-usage rules were dropped outright rather than kept dormant: coderd's `HelmRelease` sets only CPU/memory *requests*, no limits, so a usage-as-fraction-of-limit condition has no denominator to ever become meaningful.
- **The Postgres rules are translated, not copied, from the upstream chart they were ported from.** coder-db is scraped via CloudNativePG's own exporter (`postgres.yaml`'s `spec.monitoring.enablePodMonitor: true`), which uses `cnpg_*` metric names, not the `postgres_exporter`/`sql_exporter` vocabulary the source rules assumed — a notification-queue-depth condition from that source had no CNPG equivalent and was dropped rather than ported incorrectly.
- **First issuance of the apex-plus-wildcard `coder-tls-cert` Certificate is slow, and if a consuming Kustomization health-checks it, a red status for several minutes is expected during that first issuance — not a fault.** An apex plus a nested wildcard (`coder.${domain_name}` and `*.coder.${domain_name}`) produces two ACME DNS-01 challenges that share one `_acme-challenge.coder.${domain_name}` TXT name; cert-manager won't run them concurrently, since they'd collide on that record, so the second challenge doesn't even start until the first reaches `valid`. Each challenge's own DNS self-check backs off between retries, and the first attempt typically fires before the record has propagated, so cert-manager sits `pending` waiting out its own backoff rather than being stuck. If you're watching and want it to finish sooner, restarting the cert-manager controller short-circuits that backoff. Do **not** delete the Certificate or its Order to try to unstick it — that forces a fresh failed validation, and Let's Encrypt rate-limits failed validations at 5 per account per hostname per hour, turning a slow issuance into an hour-long block. Renewals are unaffected: the Certificate stays `Ready: True` throughout, and renewal starts 30 days before expiry.
- **The workspace-memory dashboard exists to contradict the stock memory reading, not to display it.** On these
  pods `container_memory_working_set_bytes` disagrees with genuinely unreclaimable memory by a factor of three or
  four — 97% of limit against 23% on one measured idle workspace — because it counts page cache the kernel hands
  straight back. `dashboards/coder-workspace-memory.json` shows both numbers side by side and adds per-container
  PSI, which measures harm rather than level and is the only thing that separates "at the limit and fine" from
  "at the limit and suffering". It also carries the only remaining record of a container OOM: `singleProcessOOMKill`
  means a cgroup OOM kills one process rather than the container, so the pod never reports `OOMKilled`,
  `container_oom_events_total` reads 0 through confirmed kills, and the kernel journal in Loki is all that is
  left. See [`dashboards/README.md`](./dashboards/README.md) to use it and
  [`dashboards/MAINTAINER.md`](./dashboards/MAINTAINER.md) before editing it.
- **coderd's Prometheus metrics are served on a port the chart's own `coder` Service
  does not expose.** The chart's Service only publishes ports 80/443, with no values
  hook to add another. `service-coder-metrics.yaml` is a second Service, selecting the
  same pods, that reaches the metrics port instead; `servicemonitor-coder.yaml` scrapes
  it. Both exist solely to make coderd observable from Prometheus and are unrelated to
  the chart's own Service/ingress wiring.
