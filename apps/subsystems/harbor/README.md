# Harbor Subsystem

Private container registry platform with built-in security scanning, RBAC, and artifact management capabilities.

## Quick Links

<a href="https://github.com/goharbor/harbor" target="_blank"><img src="../../../.static/images/logos/harbor.svg" width="32" height="32" alt="Harbor"></a>

## Overview

The harbor subsystem consists of three main capability groups:

1. Registry Services
   - Container image storage
   - Artifact management
   - Chart repository
   - Image scanning

2. Supporting Infrastructure
   - Job processing
   - Data persistence
   - Caching layer
   - Security database

3. Operational Features
   - Metrics collection
   - Access control
   - TLS termination
   - Resource management

### Component Architecture

The following diagram illustrates how Harbor's components work together to provide container registry services, showing the relationships between core services, storage, and monitoring.

```mermaid
flowchart TB
    %% Color scheme with good contrast for light/dark themes
    classDef core fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef storage fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef db fill:#d8b4fe,stroke:#9333ea,color:#581c87
    classDef security fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef infra fill:#e5e7eb,stroke:#4b5563,color:#1f2937
    classDef monitor fill:#fde68a,stroke:#d97706,color:#92400e
    classDef legend fill:none,stroke:none,color:#6b7280

    %% External Access
    client[External Client<br/>Push/Pull]:::infra

    %% Core Services
    registry[Registry<br/>Image Storage]:::core
    core[Core<br/>API Service]:::core
    jobservice[Job Service<br/>Background Tasks]:::core

    %% Security
    trivy[Trivy<br/>Security Scanner]:::security

    %% Storage Components
    subgraph storage[Storage Infrastructure]
        direction TB
        subgraph databases[Stateful Services]
            database[("PostgreSQL<br/>Database")]:::db
            redis[("Redis<br/>Cache")]:::db
        end
        subgraph volumes[Persistent Volumes]
            registry_storage[(Registry<br/>Storage)]:::storage
            chart_storage[(Chart<br/>Storage)]:::storage
            trivy_storage[(Trivy<br/>Storage)]:::storage
            db_storage[(Database<br/>Storage)]:::storage
            redis_storage[(Redis<br/>Storage)]:::storage
        end
        %% Database storage connections
        database --> db_storage
        redis --> redis_storage
    end

    %% Monitoring
    subgraph monitoring[Monitoring]
        direction TB
        metrics[Prometheus<br/>Metrics]:::monitor
        servicemonitor[Service<br/>Monitor]:::monitor
    end

    %% Relationships
    client --> core
    client --> registry

    %% Core Service dependencies
    core --> registry
    core --> database
    core --> redis

    %% Registry dependencies
    registry --> registry_storage
    registry --> chart_storage

    %% Job Service dependencies
    jobservice --> core
    jobservice --> registry
    jobservice --> redis

    %% Trivy dependencies
    trivy --> core
    trivy --> registry
    trivy --> trivy_storage

    core -.-> metrics
    registry -.-> metrics
    jobservice -.-> metrics

    metrics --> servicemonitor

    %% Simple legend at bottom
    subgraph Legend[" "]
        direction LR
        core_leg[Core Services]:::core
        db_leg[Databases]:::db
        storage_leg[Storage Volumes]:::storage
        security_leg[Security]:::security
        monitor_leg[Monitoring]:::monitor
        infra_leg[External Access]:::infra
    end

    %% Styling
    class Legend legend
    class storage legend
    class monitoring legend
```

<!-- markdownlint-disable-next-line MD036 -->
<sup>*Line styles: Solid (→) = Direct interaction/data flow, Dotted with arrow (-.→) = Metrics collection*</sup>

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
|-----------|------|--------------|--------------|-------------------|
| Registry | Core | Image Storage | • Container image management<br>• Helm chart repository<br>• Artifact versioning<br>• Storage optimization | • Direct storage volume access<br>• Core API integration<br>• Metrics collection<br>• Chart storage management |
| Core API | Core | Service Control | • Authentication management<br>• Authorization control<br>• API request handling<br>• Resource coordination | • PostgreSQL data persistence<br>• Redis cache integration<br>• Registry coordination<br>• Security service integration |
| Job Service | Core | Task Management | • Background task execution<br>• Replication management<br>• Scan job coordination<br>• Queue processing | • Redis queue integration<br>• Registry interaction<br>• Core API communication<br>• Job logging |
| Trivy | Core | Security Scanner | • Vulnerability scanning<br>• Security database<br>• Image analysis<br>• Report generation | • Registry image access<br>• Core API integration<br>• Vulnerability database<br>• Scan result storage |
| PostgreSQL | Storage | Data Persistence | • Metadata storage<br>• User data management<br>• Configuration storage<br>• Relationship tracking | • Core service integration<br>• Persistent volume storage<br>• Data backup support |
| Redis | Storage | Cache Management | • Request caching<br>• Job queue handling<br>• Session management<br>• Task coordination | • Job service integration<br>• Core API caching<br>• Queue persistence |

## Prerequisites

1. Persistent Storage

   | PVC Name | Purpose | Access Mode |
   |----------|---------|-------------|
   | harbor-registry | Container images and charts | RWX |
   | harbor-jobservice | Job logs and data | RWX |
   | harbor-database | PostgreSQL data | RWX |
   | harbor-redis | Redis data | RWX |
   | harbor-trivy | Vulnerability database | RWX |

2. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | harbor | Admin credentials | adminPassword, secretKey |

3. Required Variables

   | Variable | Purpose | Used By |
   |----------|---------|---------|
   | domain_name | External access URL (harbor.${domain_name}) | All services |
