# Bitwarden Subsystem

Self-hosted password management solution providing secure credential storage and sharing capabilities.

## Quick Links

- [Official Documentation](https://bitwarden.com/help/install-on-premise/)
- [GitHub Repository](https://github.com/bitwarden/server)

## Overview

The bitwarden subsystem consists of three main capability groups:

1. Core Services
   - Password vault management
   - Identity and access control
   - Administrative functions
   - Secure attachment handling

2. Data Management
   - Encrypted storage
   - Database persistence
   - Backup management
   - License management

3. Access Control
   - SSO integration
   - API access
   - Web interface
   - Event logging

### Component Architecture

The following diagram illustrates how Bitwarden's components work together, showing the relationships between services and their storage dependencies.

```mermaid
flowchart TB
    %% Color scheme with good contrast for light/dark themes
    classDef core fill:#a7f3d0,stroke:#059669,color:#064e3b
    classDef support fill:#bfdbfe,stroke:#3b82f6,color:#1e3a8a
    classDef db fill:#d8b4fe,stroke:#9333ea,color:#581c87
    classDef storage fill:#fecaca,stroke:#dc2626,color:#7f1d1d
    classDef client fill:#fde68a,stroke:#d97706,color:#92400e
    classDef legend fill:none,stroke:none,color:#6b7280

    %% Top-level layout
    subgraph main[" "]
        direction TB
        %% Client and primary services
        client[External Client<br/>Web/Mobile]:::client

        %% Services side by side
        subgraph services[" "]
            direction LR
            subgraph core[Core Services]
                direction TB
                space1[" "]:::hidden
                api[API Service]:::core
                space2[" "]:::hidden
                web[Web Vault]:::core
                space3[" "]:::hidden
                admin[Admin Portal]:::core
            end

            space4[" "]:::hidden

            subgraph support[Supporting Services]
                direction TB
                events[Events Service]:::support
                notifications[Notifications Service]:::support
                identity[Identity Service]:::support
                icons[Icons Service]:::support
                attachments[Attachments Service]:::support
                sso[SSO Service]:::support
            end
        end
    end

    %% Database, Storage, and Legend at bottom
    subgraph infrastructure[" "]
        direction TB
        %% Database
        subgraph database[Database]
            direction TB
            mssql[("MSSQL Server")]:::db
        end

        %% Storage
        subgraph storage[Storage]
            direction TB
            subgraph db_volumes[Database Volumes]
                db_data[(Database<br/>Data)]:::storage
                db_logs[(Database<br/>Logs)]:::storage
                db_backups[(Database<br/>Backups)]:::storage
            end
            subgraph app_volumes[Application Volumes]
                attachments_vol[(Attachments)]:::storage
                dataprotection[(Data<br/>Protection)]:::storage
                licenses[(Licenses)]:::storage
                logs[(Application<br/>Logs)]:::storage
            end
        end

        %% Spacer to push legend down
        spacer[" "]:::hidden

        %% Legend at bottom
        subgraph legend[" "]
            direction LR
            l1[Core]:::core
            l2[Support]:::support
            l3[DB]:::db
            l4[Storage]:::storage
            l5[Client]:::client
        end
    end

    %% Hide spacing nodes and containers
    classDef hidden fill:none,stroke:none
    class space1,space2,space3,space4,spacer hidden
    class main,infrastructure,services,legend legend
    client --> web
    client --> api

    %% Core Service Dependencies
    api --> mssql
    identity --> mssql
    admin --> mssql

    %% Service Communication
    web --> api
    admin --> api
    api --> events
    api --> notifications
    api --> icons
    api --> attachments
    sso --> identity

    %% Database Access
    api --> mssql
    events --> mssql
    notifications --> mssql
    attachments --> attachments_vol

    %% Storage Management
    mssql --> db_data
    mssql --> db_logs
    mssql --> db_backups
q
    %% PVC Usage
    api --> dataprotection
    api --> licenses
    api -.-> logs
    web -.-> logs
    admin -.-> logs
    events -.-> logs
    notifications -.-> logs
    icons -.-> logs
    attachments -.-> logs
    sso -.-> logs

    %% Make legend less prominent
    class legend legend
```

<sup>*Note: While component relationships are based on official documentation, some communication flows between services are inferred and may need verification*</sup>

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
|-----------|------|--------------|--------------|-------------------|
| API Service | Core | Request Handler | • Client request processing<br>• Data operation management<br>• Encryption handling<br>• Storage coordination | • Direct MSSQL database access<br>• Integration with all supporting services<br>• Data protection key management<br>• License validation |
| Web Vault | Core | User Interface | • Password management interface<br>• Secure vault access<br>• Organization management<br>• User settings | • Authentication via Identity service<br>• API service communication<br>• Application logging |
| Admin Portal | Core | Administration | • System configuration<br>• User management<br>• Organization control<br>• License management | • Identity service authentication<br>• MSSQL database access<br>• Application logging |
| Identity Service | Supporting | Authentication | • User authentication<br>• SSO management<br>• Token handling<br>• Session management | • MSSQL database integration<br>• SSO service coordination<br>• Authentication for all services |
| Events | Supporting | Audit System | • Activity logging<br>• Audit trail maintenance<br>• Event tracking<br>• History management | • MSSQL database integration<br>• API service coordination<br>• Application logging |
| Notifications | Supporting | Update System | • Real-time notifications<br>• Status updates<br>• Alert management<br>• User notifications | • MSSQL database integration<br>• API service coordination<br>• Application logging |
| Icons | Supporting | Resource Cache | • Favicon management<br>• Icon caching<br>• Resource optimization<br>• Cache maintenance | • API service coordination<br>• Application logging<br>• External icon fetching |
| Attachments | Supporting | File Management | • Secure file storage<br>• Attachment handling<br>• File encryption<br>• Storage management | • Dedicated volume access<br>• API service coordination<br>• Application logging |
| SSO | Supporting | Authentication | • External SSO integration<br>• Identity provider connection<br>• Protocol support<br>• Session handling | • Identity service integration<br>• Application logging<br>• External provider coordination |

## Prerequisites

1. Persistent Storage

   | PVC Name | Purpose | Access Mode |
   |----------|---------|-------------|
   | bitwarden-attachments | File attachments | RWX |
   | bitwarden-dataprotection | Encryption keys | RWX |
   | bitwarden-db-backups | Database backups | RWX |
   | bitwarden-db-data | MSSQL data files | RWX |
   | bitwarden-db-logs | Database logs | RWX |
   | bitwarden-licenses | License files | RWX |
   | bitwarden-logs | Application logs | RWX |

2. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | coder-db-app | Database connection | uri |
   | coder-oidc-auth-settings | OIDC configuration | clientId, clientSecret |

3. Required Variables

   | Variable | Purpose | Used By |
   |----------|---------|---------|
   | domain_name | External access URL (bitwarden.${domain_name}) | All services |
   | cloud_communication | External services (disabled by default) | Core services |
