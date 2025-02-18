# Database Core

This module provides PostgreSQL database management capabilities for the cluster by installing and configuring the CloudNativePG operator. The operator enables other modules to create and manage their own PostgreSQL clusters with high availability, backup/recovery, and monitoring integration.

Note: This module only installs the operator - actual PostgreSQL clusters are created by other modules that need databases.

## Quick Links

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

## Overview

The database-core module provides:

1. Database Management Capabilities
   - CloudNativePG operator deployment
   - Custom Resource Definitions for PostgreSQL
   - Operator monitoring integration
   - Operator high availability configuration

2. Data Protection Framework
   - S3 backup configuration
   - WAL archiving setup
   - Backup retention configuration
   - Recovery mechanisms

3. Monitoring Integration
   - Operator metrics collection
   - Default Grafana dashboards
   - Performance monitoring
   - Health checks

### Component Architecture

```mermaid
flowchart TB
    %% Color scheme
    classDef operator fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef database fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef storage fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef monitor fill:#fde68a,stroke:#d97706,color:#92400e
    classDef legend fill:none,stroke:none,color:#6b7280

    %% Main Component - The Operator
    cnpg[CloudNativePG Operator]:::operator

    %% Example PostgreSQL Cluster
    subgraph cluster[Example PostgreSQL Cluster]
        direction TB
        note[Created by other modules<br/>using Cluster CRD]
        primary[Primary Instance]:::database
        replica1[Replica 1]:::database
        replica2[Replica 2]:::database
    end

    %% Storage Components
    subgraph storage[Storage]
        pvc1[(Primary PVC)]:::storage
        pvc2[(Replica 1 PVC)]:::storage
        pvc3[(Replica 2 PVC)]:::storage
        s3[(S3 Backup Storage)]:::storage
    end

    %% Minimal but Meaningful Monitoring
    podmonitor[PodMonitor]:::monitor

    %% Relationships
    cnpg --> primary
    cnpg --> replica1
    cnpg --> replica2

    primary --> pvc1
    replica1 --> pvc2
    replica2 --> pvc3

    primary -- "WAL Shipping" --> replica1
    primary -- "WAL Shipping" --> replica2
    primary -- "WAL Archive" --> s3

    podmonitor -- "Collects Metrics" --> primary
    podmonitor -- "Collects Metrics" --> replica1
    podmonitor -- "Collects Metrics" --> replica2

    %% Legend
    subgraph Legend[" "]
        direction LR
        op[Operator]:::operator
        db[Database]:::database
        st[Storage]:::storage
        mon[Monitoring]:::monitor
    end

    class Legend legend
```

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| CloudNativePG Operator | Database management | • Provides CRDs for PostgreSQL management<br>• Enables high availability and failover<br>• Configures backup and recovery<br>• Integrates with monitoring stack<br>• Collects operator/cluster metrics via PodMonitor<br>• Provides default Grafana dashboards |

## Prerequisites

None for this subsystem (which provides the cloudnativepg operator). But creating Postgres instances using the `Cluster` CRD provided by this subsystem will have its own pre-requisites (according to how the `Cluster` is defined).

## Dependencies

### Required By

- Application modules requiring PostgreSQL databases
- [security-extra](../security-extra) (for authentication and authorization)

### Depends On

None
