# Kubernetes Platform Modules

This repository contains modules for deploying and managing a complete Kubernetes platform. It provides both foundational infrastructure capabilities and end-user applications, using a modular approach that enables consistent deployment and management through GitOps practices.

## What This Project Provides

This platform enables you to:

- Deploy and manage infrastructure capabilities:
  - Secure service communication with automated TLS certificate management
  - Provide distributed storage with automated backup and replication
  - Configure networking with automated DNS and load balancing
  - Monitor system health with metrics, logs, and alerts
  - Manage databases with automated failover and backups

- Run end-user applications:
  - Secure password management with Bitwarden
  - Remote development environments with Coder
  - Container image registry with Harbor
  - Home automation through Home Assistant
  - Media management with Plex, Jellyfin, and automated content organization
  - Utility services including SMTP relay with Maddy

| Module Type | Module Name | Applications (↗) | Capabilities |
|-------------|-------------|--------------|--------------|
| **Infrastructure (Core)** | [security-core](./infrastructure/subsystems/security-core) | <img src="./.static/images/logos/cert-manager.svg" width="16" height="16" alt="cert-manager"> <a href="https://cert-manager.io/" target="_blank">cert-manager</a><br><img src="./.static/images/logos/external-secrets.svg" width="16" height="16" alt="external-secrets"> <a href="https://external-secrets.io/" target="_blank">external-secrets</a><br><img src="./.static/images/logos/cert-manager.svg" width="16" height="16" alt="trust-manager"> <a href="https://cert-manager.io/docs/trust/trust-manager/" target="_blank">trust-manager</a> | • Provides automated TLS certificate management<br>• Enables secure secret management with external providers<br>• Facilitates certificate distribution across namespaces |
| | [storage-core](./infrastructure/subsystems/storage-core) | <img src="./.static/images/logos/longhorn.svg" width="16" height="16" alt="Longhorn"> <a href="https://longhorn.io/" target="_blank">Longhorn</a><br><img src="./.static/images/logos/minio.svg" width="16" height="16" alt="MinIO"> <a href="https://min.io/" target="_blank">MinIO</a><br><img src="./.static/images/logos/nfs-csi-driver.png" width="16" height="16" alt="NFS CSI Driver"> NFS CSI Driver | • Delivers distributed block storage with replication<br>• Provides S3-compatible object storage<br>• Enables dynamic provisioning from NFS shares |
| | [networking-core](./infrastructure/subsystems/networking-core) | <img src="./.static/images/logos/metallb.png" width="16" height="16" alt="MetalLB"> <a href="https://metallb.io/" target="_blank">MetalLB</a><br><img src="./.static/images/logos/kubernetes.svg" width="16" height="16" alt="external-dns"> <a href="https://github.com/kubernetes-sigs/external-dns" target="_blank">external-dns</a><br><img src="./.static/images/logos/traefik.svg" width="16" height="16" alt="Traefik"> <a href="https://traefik.io/" target="_blank">Traefik</a> | • Supplies Layer 2 load balancing for services<br>• Manages DNS records automatically<br>• Controls ingress with TLS and middleware support |
| | [observability-core](./infrastructure/subsystems/observability-core) | <img src="./.static/images/logos/prometheus.svg" width="16" height="16" alt="Prometheus"> <a href="https://prometheus.io/" target="_blank">Prometheus</a><br><img src="./.static/images/logos/loki.svg" width="16" height="16" alt="Loki"> <a href="https://grafana.com/oss/loki/" target="_blank">Loki</a><br><img src="./.static/images/logos/grafana.svg" width="16" height="16" alt="Grafana"> <a href="https://grafana.com/" target="_blank">Grafana</a> | • Collects metrics with ServiceMonitor support<br>• Aggregates logs with retention policies<br>• Provides unified visualization dashboards |
| | [database-core](./infrastructure/subsystems/database-core) | <img src="./.static/images/logos/cloudnative-pg.svg" width="16" height="16" alt="CloudNativePG"> <a href="https://cloudnative-pg.io/" target="_blank">CloudNativePG</a> | • Manages PostgreSQL clusters with automation<br>• Enables high availability with failover<br>• Configures backup with retention policies |
| | [kubernetes-core](./infrastructure/subsystems/kubernetes-core) | <img src="./.static/images/logos/coredns.svg" width="16" height="16" alt="CoreDNS"> <a href="https://coredns.io/" target="_blank">CoreDNS</a> | • Configures cluster-wide service discovery<br>• Provides secure API access<br>• Supports custom DNS zones |
| | [clusterops-core](./infrastructure/subsystems/clusterops-core) | <img src="./.static/images/logos/fluxcd.png" width="16" height="16" alt="Flux CD"> <a href="https://fluxcd.io/" target="_blank">Flux CD</a><br><img src="./.static/images/logos/rancher.svg" width="16" height="16" alt="system-upgrade-controller"> <a href="https://github.com/rancher/system-upgrade-controller" target="_blank">system-upgrade-controller</a> | • Manages GitOps-based deployments<br>• Automates component upgrades<br>• Provides OOM protection |
| **Infrastructure (Extra)** | [security-extra](./infrastructure/subsystems/security-extra) | <img src="./.static/images/logos/authentik.svg" width="16" height="16" alt="Authentik"> <a href="https://goauthentik.io/" target="_blank">Authentik</a> | • Deploys identity provider for SSO<br>• Implements policy-based access control<br>• Secures service ingress with identity headers |
| | [networking-extra](./infrastructure/subsystems/networking-extra) | <img src="./.static/images/logos/pi-hole.svg" width="16" height="16" alt="Pi-hole"> <a href="https://pi-hole.net/" target="_blank">Pi-hole</a><br><img src="./.static/images/logos/freeradius.svg" width="16" height="16" alt="FreeRADIUS"> <a href="https://freeradius.org/" target="_blank">FreeRADIUS</a><br><img src="./.static/images/logos/tailscale.png" width="16" height="16" alt="Tailscale"> <a href="https://tailscale.com/" target="_blank">Tailscale</a><br><img src="./.static/images/logos/unifi.svg" width="16" height="16" alt="UniFi"> <a href="https://ui.com/" target="_blank">UniFi</a> | • Filters DNS and blocks ads<br>• Provides secure VPN access<br>• Manages network devices comprehensively<br>• Maps wireless clients to VLANs based on MAC addresses |
| | [observability-extra](./infrastructure/subsystems/observability-extra) | <img src="./.static/images/logos/resmoio.png" width="16" height="16" alt="Kubernetes Event Exporter"> <a href="https://github.com/resmoio/kubernetes-event-exporter" target="_blank">Kubernetes Event Exporter</a><br><img src="./.static/images/logos/kubernetes.svg" width="16" height="16" alt="Node Problem Detector"> <a href="https://github.com/kubernetes/node-problem-detector" target="_blank">Node Problem Detector</a><br><img src="./.static/images/logos/prometheus.svg" width="16" height="16" alt="SNMP Exporter"> <a href="https://github.com/prometheus/snmp_exporter" target="_blank">SNMP Exporter</a><br><img src="./.static/images/logos/syslog-ng.png" width="16" height="16" alt="Syslog-ng"> <a href="https://www.syslog-ng.com/technical-documents/doc/syslog-ng-open-source-edition/3.37/administration-guide/" target="_blank">Syslog-ng</a><br><img src="./.static/images/logos/unifi-poller.png" width="16" height="16" alt="UniFi Poller"> <a href="https://unpoller.com/" target="_blank">UniFi Poller</a> | • Exports Kubernetes events to Loki<br>• Collects metrics from network devices<br>• Detects node problems with custom definitions |
| | [kubernetes-extra](./infrastructure/subsystems/kubernetes-extra) | <img src="./.static/images/logos/kubernetes.svg" width="16" height="16" alt="node-feature-discovery"> <a href="https://kubernetes-sigs.github.io/node-feature-discovery/" target="_blank">node-feature-discovery</a><br><img src="./.static/images/logos/kubernetes.svg" width="16" height="16" alt="Vertical Pod Autoscaler"> <a href="https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler" target="_blank">Vertical Pod Autoscaler</a><br><img src="./.static/images/logos/kubernetes.svg" width="16" height="16" alt="descheduler"> <a href="https://github.com/kubernetes-sigs/descheduler" target="_blank">descheduler</a> | • Discovers and labels node hardware<br>• Optimizes resource allocation<br>• Balances workloads with policies |
| | [clusterops-extra](./infrastructure/subsystems/clusterops-extra) | <a href="https://github.com/FairwindsOps/goldilocks" target="_blank">Goldilocks</a><br><img src="./.static/images/logos/reloader.png" width="16" height="16" alt="reloader"> <a href="https://github.com/stakater/Reloader" target="_blank">reloader</a><br><img src="./.static/images/logos/terraform.svg" width="16" height="16" alt="Terraform controller"> <a href="https://github.com/weaveworks/tf-controller" target="_blank">Terraform controller</a> | • Visualizes resource optimization<br>• Automates pod restarts on config changes<br>• Manages infrastructure with Terraform integration |
| **Applications** | [ai](./apps/subsystems/ai) | <img src="./.static/images/logos/ollama.png" width="16" height="16" alt="Ollama"> <a href="https://github.com/ollama/ollama" target="_blank">Ollama</a><br><img src="./.static/images/logos/open-webui.png" width="16" height="16" alt="OpenWebUI"> <a href="https://github.com/open-webui/open-webui" target="_blank">OpenWebUI</a> | • Hosts large language models locally<br>• Provides web-based chat interface<br>• Enables model selection and configuration |
| | [bitwarden](./apps/subsystems/bitwarden) | <img src="./.static/images/logos/bitwarden.svg" width="16" height="16" alt="Bitwarden"> <a href="https://bitwarden.com/help/password-manager-overview/" target="_blank">Bitwarden</a> | • Provides end-to-end encrypted password vault<br>• Enables credential autofill in browsers<br>• Supports two-factor authentication |
| | [coder](./apps/subsystems/coder) | <img src="./.static/images/logos/coder.svg" width="16" height="16" alt="Coder"> <a href="https://coder.com/docs/about" target="_blank">Coder</a> | • Creates cloud-based development environments<br>• Provides server-grade compute resources<br>• Enables consistent environment configuration |
| | [downloaders](./apps/subsystems/downloaders) | <img src="./.static/images/logos/sonarr.svg" width="16" height="16" alt="Sonarr"> <a href="https://github.com/Sonarr/Sonarr/blob/v5-develop/README.md" target="_blank">Sonarr</a><br><img src="./.static/images/logos/radarr.svg" width="16" height="16" alt="Radarr"> <a href="https://github.com/Radarr/Radarr/blob/develop/README.md" target="_blank">Radarr</a><br><img src="./.static/images/logos/lidarr.svg" width="16" height="16" alt="Lidarr"> <a href="https://github.com/Lidarr/Lidarr/blob/develop/README.md" target="_blank">Lidarr</a><br><img src="./.static/images/logos/prowlarr.svg" width="16" height="16" alt="Prowlarr"> <a href="https://github.com/Prowlarr/Prowlarr/blob/develop/README.md" target="_blank">Prowlarr</a><br><img src="./.static/images/logos/sabnzbd.svg" width="16" height="16" alt="SABnzbd"> <a href="https://sabnzbd.org/wiki/" target="_blank">SABnzbd</a> | • Manages TV shows with quality profiles<br>• Handles movies with automated organization<br>• Provides unified indexer management |
| | [harbor](./apps/subsystems/harbor) | <img src="./.static/images/logos/harbor.svg" width="16" height="16" alt="Harbor"> <a href="https://github.com/goharbor/harbor/blob/main/README.md" target="_blank">Harbor</a> | • Stores and manages container images and charts<br>• Performs vulnerability scanning on images<br>• Enables image signing and content trust |
| | [home-automation](./apps/subsystems/home-automation) | <img src="./.static/images/logos/home-assistant.svg" width="16" height="16" alt="Home Assistant"> <a href="https://www.home-assistant.io/" target="_blank">Home Assistant</a> | • Integrates with smart home devices<br>• Provides automation engine for device control<br>• Enables custom monitoring dashboards |
| | [media](./apps/subsystems/media) | <img src="./.static/images/logos/plex.svg" width="16" height="16" alt="Plex"> <a href="https://www.plex.tv/" target="_blank">Plex</a><br><img src="./.static/images/logos/jellyfin.svg" width="16" height="16" alt="Jellyfin"> <a href="https://jellyfin.org/" target="_blank">Jellyfin</a><br><img src="./.static/images/logos/freetube.svg" width="16" height="16" alt="FreeTube"> <a href="https://freetubeapp.io/" target="_blank">FreeTube</a><br><img src="./.static/images/logos/tautulli.svg" width="16" height="16" alt="Tautulli"> <a href="https://tautulli.com/" target="_blank">Tautulli</a> | • Streams media with transcoding capabilities<br>• Enables privacy-focused YouTube viewing<br>• Monitors Plex statistics and usage |
| | [misc](./apps/subsystems/misc) | <a href="https://github.com/foxcpp/maddy" target="_blank">Maddy</a> | • Houses misc applications<br>• Provides SMTP relay services<br>• |
| **Components** | [sso](./components/sso) | SSO integration patches | • Adds single sign-on to multiple applications<br>• Secures ingress with authentication middleware<br>• Provides consistent login experience |
| | [db-backups](./components/db-backups) | Database backup configuration | • Configures scheduled database backups<br>• Manages backup credentials securely<br>• Applies consistent backup policies |
| | [oidc-credentials](./components/oidc-credentials) | OIDC credential configuration | • Configures OIDC credentials for applications<br>• Enables secure authentication flows<br>• Provides consistent identity integration |

## Project Structure & Concepts

The platform organizes functionality into module types with clear responsibilities:

```mermaid
classDiagram
    class Module {
        +kustomization.yaml
        +CHANGELOG.md
        +namespace.yaml
        +deploy()
        +configure()
    }

    class InfrastructureModule {
        +core services
        +platform capabilities
        +core/extra pattern
        +provideCapability()
    }

    class ApplicationModule {
        +user services
        +specific use case
        +useInfrastructure()
    }

    class ComponentModule {
        +cross-cutting config
        +kustomize components
        +applyConfiguration()
    }

    Module <|-- InfrastructureModule
    Module <|-- ApplicationModule
    Module <|-- ComponentModule
```

| Module Type | Purpose | Characteristics | Examples |
|------------|---------|-----------------|----------|
| Infrastructure | Provides foundational platform capabilities | • Supplies core services<br/>• Uses core/extra pattern<br/>• Focuses on platform features<br/>• Other modules depend on it | [Infrastructure Modules](./infrastructure):<br/>• Security (certs, secrets)<br/>• Storage (block, object)<br/>• Networking (DNS, ingress) |
| Application | Delivers end-user functionality | • Provides user services<br/>• Focuses on use cases<br/>• Uses infrastructure capabilities<br/>• Independent deployment | [Application Modules](./apps):<br/>• Password management<br/>• Development environments<br/>• Media streaming |
| Component | Enables cross-cutting features | • Configures shared features<br/>• Uses Kustomize components<br/>• Applies to other modules<br/>• Flexible application | [Component Modules](./components):<br/>• Single sign-on<br/>• Backup policies<br/>• Monitoring templates |

## Finding Your Way

| Category | When you need to... | Look in... | To find... | For example... |
|----------|-------------------|------------|------------|----------------|
| Project Understanding | Understand the project structure | [Project Brief - Organization](./projectBrief.md#module-types-and-organization) | Module types and relationships | • Infrastructure/Apps/Components<br/>• Core/Extra pattern<br/>• Module boundaries |
|  | Learn about design decisions | [Project Brief - Design](./projectBrief.md#design-principles) | Architecture principles and patterns | • Module independence<br/>• Configuration flexibility<br/>• Dependency management |
|  | See how changes are managed | [Project Brief - Development](./projectBrief.md#development-workflow) | Quality controls and workflows | • Version management<br/>• Automated updates<br/>• Release process |
| Module Usage | Find infrastructure capabilities | [Infrastructure Modules](./infrastructure) | Platform services by category | • Security (cert-manager, secrets)<br/>• Storage (Longhorn, MinIO)<br/>• Networking (MetalLB, Traefik) |
|  | Set up end-user applications | [Application Modules](./apps) | User-facing services | • Password management (Bitwarden)<br/>• Development environments (Coder)<br/>• Media streaming (Plex) |
|  | Configure cross-cutting features | [Component Modules](./components) | Reusable configurations | • Single sign-on setup<br/>• Backup configurations<br/>• Monitoring templates |
| Configuration | Configure modules | [Project Brief - Configuration](./projectBrief.md#configuration) | Configuration methods | • Kustomize patches<br/>• Post-build variables<br/>• Component overlays |
|  | Handle dependencies | [Project Brief - Dependencies](./projectBrief.md#dependencies) | Dependency management | • Hard vs soft dependencies<br/>• Core/Extra pattern<br/>• Dependency cycles |
|  | Set up integrations | [Project Brief - Integration](./projectBrief.md#integration-patterns) | Integration patterns | • Certificate management<br/>• Secret handling<br/>• Monitoring setup |
