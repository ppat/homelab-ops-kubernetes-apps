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
