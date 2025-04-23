# Infrastructure Modules

This directory contains infrastructure modules that provide foundational capabilities for the Kubernetes platform. These modules establish the core services, security, networking, and operational features that both the cluster itself and applications require.

## Functional Areas & Capabilities

| Category | Functional Areas | Module Capabilities |
|----------|-----------------|-------------------|
| Security | Certificates<br/>Secrets<br/>SSO & Auth | [security-core](./subsystems/security-core):<br/>• Provides cert-manager operator that automatically obtains and renews TLS certificates from configured issuers (e.g., Let's Encrypt)<br/>• Enables applications to fetch secrets from Bitwarden Secrets Manager through external-secrets operator with automated synchronization<br/>• Uses trust-manager to copy certificates between namespaces based on bundle definitions, eliminating manual certificate distribution<br/><br/>[security-extra](./subsystems/security-extra):<br/>• Deploys Authentik identity provider for SSO across all cluster services with policy-based access control<br/>• Implements forward authentication for securing service ingress endpoints with rich identity headers |
| Storage | Block Storage<br/>Object Storage<br/>Network Storage | [storage-core](./subsystems/storage-core):<br/>• Deploys Longhorn to provide distributed block storage across cluster nodes with built-in replication and backup<br/>• Runs MinIO operator to provide S3-compatible object storage with bucket lifecycle management<br/>• Installs CSI driver for dynamic provisioning of volumes from existing NFS shares with custom mount options |
| Networking | Load Balancing<br/>DNS Management<br/>Ingress Control<br/>VPN & Network Management | [networking-core](./subsystems/networking-core):<br/>• Deploys MetalLB to provide Layer 2 load balancing for Kubernetes services with automatic IP allocation<br/>• Runs external-dns to automatically manage DNS records in configured providers (PiHole/UniFi)<br/>• Configures Traefik for ingress control with automatic TLS and custom middleware chains<br/><br/>[networking-extra](./subsystems/networking-extra):<br/>• Installs Pi-hole for DNS filtering and ad blocking with custom blocklists<br/>• Deploys Tailscale operator for secure VPN access with MagicDNS support<br/>• Runs UniFi controller for comprehensive network device management<br/>• Provides RADIUS authentication for mapping wireless clients to VLANs based on MAC addresses |
| Observability | Metrics Collection<br/>Log Aggregation<br/>Visualization<br/>Event Management | [observability-core](./subsystems/observability-core):<br/>• Deploys Prometheus stack for metrics collection with ServiceMonitor/PodMonitor support<br/>• Runs Loki for log aggregation with automated retention and S3 storage<br/>• Provides Grafana for unified visualization with auto-discovered dashboards<br/><br/>[observability-extra](./subsystems/observability-extra):<br/>• Exports Kubernetes events to Loki with custom stream labels<br/>• Collects SNMP metrics from network devices with custom MIBs<br/>• Detects node problems with custom problem definitions |
| Database | PostgreSQL Operations<br/>HA Management<br/>Backup & Recovery | [database-core](./subsystems/database-core):<br/>• Installs CloudNativePG operator for automated PostgreSQL cluster management<br/>• Enables other modules to create HA PostgreSQL clusters with automated failover<br/>• Configures S3 backup storage with customizable retention policies<br/>• Provides monitoring integration with pre-configured Grafana dashboards |
| Kubernetes | DNS Resolution<br/>API Access<br/>Hardware Management<br/>Resource Optimization | [kubernetes-core](./subsystems/kubernetes-core):<br/>• Configures CoreDNS for cluster-wide service discovery with custom zone support<br/>• Provides secure external access to Kubernetes API with load balancing<br/><br/>[kubernetes-extra](./subsystems/kubernetes-extra):<br/>• Discovers and labels node hardware capabilities through node-feature-discovery<br/>• Runs Vertical Pod Autoscaler in recommendation mode for resource optimization<br/>• Manages device plugins for hardware access with shared device support<br/>• Balances workloads through descheduler with configurable policies |
| ClusterOps | GitOps Deployment<br/>System Upgrades<br/>Configuration Management<br/>Resource Tuning | [clusterops-core](./subsystems/clusterops-core):<br/>• Manages Flux CD for GitOps-based deployment with OOM protection<br/>• Runs system-upgrade-controller for automated component upgrades<br/><br/>[clusterops-extra](./subsystems/clusterops-extra):<br/>• Provides Goldilocks for resource optimization visualization<br/>• Deploys reloader for automatic pod restarts on config changes<br/>• Runs Terraform controller for infrastructure management with Flux integration |

## Module Relationships

The following diagram shows the dependencies between infrastructure modules, illustrating how core services provide foundations for extended capabilities:

```mermaid
flowchart BT
    %% Color scheme for better contrast in light/dark themes
    classDef core fill:#86efac,stroke:#059669,color:#064e3b
    classDef extra fill:#fca5a5,stroke:#dc2626,color:#7f1d1d

    %% Layer 1 - Root
    security-core[security-core]:::core

    %% Layer 2 - Direct Dependencies
    storage-core[storage-core]:::core
    networking-core[networking-core]:::core
    observability-core[observability-core]:::core
    database-core[database-core]:::core

    %% Layer 3 - Extended Components
    kubernetes-core[kubernetes-core]:::core
    clusterops-core[clusterops-core]:::core
    security-extra[security-extra]:::extra
    networking-extra[networking-extra]:::extra
    kubernetes-extra[kubernetes-extra]:::extra
    clusterops-extra[clusterops-extra]:::extra
    observability-extra[observability-extra]:::extra

    %% Dependencies - Organized by layers
    storage-core & networking-core & observability-core --> security-core
    observability-core --> storage-core

    %% Extra module dependencies - Minimizing crossings
    security-extra --> security-core
    security-extra --> storage-core
    security-extra --> database-core

    networking-extra --> security-core
    networking-extra --> storage-core
    networking-extra --> networking-core

    observability-extra --> observability-core

    kubernetes-extra --> kubernetes-core
    clusterops-extra --> clusterops-core
```

## Configuration

For detailed information about configuration methods used across all modules, including Kustomize patches, FluxCD post-build variables, and component overlays, refer to the [Configuration Methods](../projectBrief.md#configuration-methods) section in the project brief.
