# Security Extra

This module provides advanced identity and access management through Authentik, enabling centralized authentication, authorization, and user management.

## Quick Links

- [Authentik Documentation](https://goauthentik.io/docs/)
- [Forward Auth Documentation](https://goauthentik.io/docs/providers/proxy/forward_auth)

## Overview

The security-extra module provides three main capabilities:

1. Identity Management
   - High-availability server deployment (3 replicas)
   - Background worker for async tasks
   - PostgreSQL cluster (2 instances)
   - Redis for caching and sessions
   - S3-based media storage
   - SMTP integration for notifications

2. Access Control
   - Forward authentication for Traefik
   - Rich identity headers
   - Wildcard domain support
   - TLS termination
   - Policy-based access control

3. Monitoring Integration
   - ServiceMonitor for servers
   - PodMonitor for database
   - Redis metrics collection
   - Prometheus rules
   - Health checks

### Component Architecture

```mermaid
flowchart TB
    %% Color scheme
    classDef ingress fill:#fef9c3,stroke:#ca8a04,color:#854d0e
    classDef core fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef db fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef storage fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef infra fill:#e5e7eb,stroke:#6b7280,color:#374151
    classDef legend fill:none,stroke:none,color:#6b7280

    %% Entry Points - All aligned at top
    ingress-api(["Ingress: auth.${domain_name}<br/>API/WebUI"]):::ingress
    ingress-internal(["Ingress: *.${domain_name}<br/>Internal Forward Auth"]):::ingress
    ingress-external(["Ingress: *.external.com<br/>External Forward Auth"]):::ingress

    %% Core Components
    subgraph core["Authentik Core"]
        direction TB
        server-1["**Server 1**<br/>API<br/>WebUI<br/>Outpost"]:::core
        server-2["**Server 2**<br/>API<br/>WebUI<br/>Outpost"]:::core
        server-3["**Server 3**<br/>API<br/>WebUI<br/>Outpost"]:::core
        worker["Background Worker<br/>(Tasks/Events)"]:::core
    end

    %% Database Layer
    subgraph databases["Database Layer"]
        direction TB
        pg-primary["PostgreSQL Primary<br/>(Config/Data)"]:::db
        pg-replica["PostgreSQL Replica<br/>(HA/Failover)"]:::db
        redis["Redis<br/>(Cache/Sessions)"]:::db
    end

    %% Storage Layer
    subgraph storage["Storage Layer"]
        direction TB
        pg-primary-pvc["PostgreSQL Primary PVC"]:::storage
        pg-replica-pvc["PostgreSQL Replica PVC"]:::storage
        redis-pvc["Redis PVC"]:::storage
        s3-media["S3 Bucket: Media<br/>homelab-authentik-media"]:::storage
        s3-backup["S3 Bucket: Backups<br/>homelab-authentik-backup"]:::storage
    end

    %% Infrastructure
    subgraph infra["Infrastructure"]
        direction TB
        smtp["SMTP Server<br/>smtp.${domain_name}"]:::infra
    end

    %% Traffic Flow - Top to Bottom
    ingress-api --> server-1
    ingress-api --> server-2
    ingress-api --> server-3
    ingress-internal --> server-1
    ingress-internal --> server-2
    ingress-internal --> server-3
    ingress-external -.-> server-1
    ingress-external -.-> server-2
    ingress-external -.-> server-3

    %% Core Dependencies
    server-1 --> pg-primary
    server-2 --> pg-primary
    server-3 --> pg-primary
    server-1 --> redis
    server-2 --> redis
    server-3 --> redis
    server-1 --> s3-media
    server-2 --> s3-media
    server-3 --> s3-media
    pg-primary --> pg-replica

    %% Worker Dependencies
    worker --> pg-primary
    worker --> redis
    worker --> s3-media
    worker --> smtp

    %% Database Storage
    pg-primary --> pg-primary-pvc
    pg-primary --> s3-backup
    pg-replica --> pg-replica-pvc
    redis --> redis-pvc

    %% Legend
    subgraph Legend[" "]
        direction LR
        ingress-l["Ingress"]:::ingress
        core-l["Core Services"]:::core
        db-l["Databases"]:::db
        storage-l["Storage"]:::storage
        infra-l["Infrastructure"]:::infra
        style Legend fill:none,stroke:none
    end

    class Legend legend
    style Legend opacity:0
```

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Server | Core identity management | • Runs 3 replicas for HA<br>• Handles API requests and flows<br>• Processes SSO operations<br>• Routes static assets<br>• Hosts embedded outpost |
| Background Worker | Async task processing | • Sends notifications<br>• Processes events<br>• Handles system tasks<br>• Manages email delivery |
| PostgreSQL | Data persistence | • Primary-replica setup<br>• Stores configuration<br>• Manages user data<br>• Custom storage class<br>• PodMonitor enabled |
| Redis | Session management | • Caches authentication data<br>• Manages user sessions<br>• Persistent storage<br>• Metrics collection |
| Embedded Outpost | Forward authentication | • Handles Traefik auth<br>• Provides identity headers<br>• Supports wildcard domains<br>• Real-time config updates |
| External Outpost | Remote authentication | • Optional deployment<br>• Supports airgapped setups<br>• Uses service account<br>• Websocket health checks |

## Prerequisites

1. Required Components

   | Component | Purpose | Configuration |
   |-----------|---------|---------------|
   | PostgreSQL | Data persistence | From database-core |
   | S3 Storage | Media storage | From storage-core |
   | Certificate Manager | JWT signing | From security-core |

2. Required Variables

   | Variable | Purpose | Example |
   |----------|---------|---------|
   | domain_name | Base domain | example.com |
   | dns_zone | Cookie domain | homelab.local |
   | cert_issuer | Certificate issuer | letsencrypt-prod |
   | POSTGRES_DB_SIZE | Database size | 10Gi |
   | REDIS_SIZE | Cache size | 1Gi |

3. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | authentik-credentials | Core credentials | authentik_secret_key, authentik_redis_password |
   | authentik-db-app | Database access | username, password |
   | authentik-signing-cert | JWT signing | tls.key, tls.crt |

## Dependencies

### Required By

- Application modules requiring:
  - Authentication services
  - Authorization controls
  - Single sign-on
  - Forward auth protection

### Depends On

- [security-core](../security-core) - For certificates
- [storage-core](../storage-core) - For S3 storage
- [database-core](../database-core) - For PostgreSQL

## Usage

### Forward Authentication

Enable authentication for an ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: authentik-forward-auth@kubernetescrd
spec:
  rules:
  - host: app.example.com
```

### Identity Headers

Available headers from forward auth:

```yaml
- X-authentik-username  # User's login name
- X-authentik-groups    # Group memberships
- X-authentik-email     # Email address
- X-authentik-name      # Display name
- X-authentik-uid       # Unique identifier
- X-authentik-jwt      # JSON Web Token
```
