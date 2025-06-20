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

3. Security Controls
   - RBAC management
   - TLS encryption
   - Workspace isolation
   - Resource limits

### Component Details

| Component | Type | Primary Role | Key Features | Integration Points |
|-----------|------|--------------|--------------|-------------------|
| Coder Server | Core | Platform Control | • Workspace provisioning<br>• Template management<br>• Access control<br>• Resource orchestration | • PostgreSQL state storage<br>• OIDC authentication<br>• Prometheus metrics<br>• Kubernetes API |
| PostgreSQL | Infrastructure | State Storage | • Platform state persistence<br>• User data management<br>• Workspace metadata<br>• High availability support | • Coder server integration<br>• Automated failover<br>• Metrics collection |
| OIDC Provider | Security | Authentication | • Identity management<br>• Session control<br>• Token handling<br>• User authorization | • Coder server integration<br>• External provider support<br>• Session management |
| Workspace Agent | Runtime | Environment Control | • Development environment<br>• Resource management<br>• Connection handling<br>• Tool integration | • Coder server communication<br>• Kubernetes resources<br>• Template execution |

## Prerequisites

1. Persistent Storage

   | PVC Name | Purpose | Access Mode |
   |----------|---------|-------------|
   | coder-db-data | PostgreSQL data | RWO |
   | workspace-data | Per-workspace storage | RWX |

2. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | coder-db-app | Database connection | uri |
   | coder-sso-credentials | OIDC configuration | clientId, clientSecret |

3. Required Variables

   | Variable | Purpose | Used By |
   |----------|---------|---------|
   | domain_name | External access URL | Coder server |
   | db_storage_size | Database storage | PostgreSQL |
   | db_storage_class | Storage class | PostgreSQL |

4. RBAC Requirements

   | Resource | Access | Purpose |
   |----------|---------|---------|
   | configmaps | create, delete, get, list, update, watch | Workspace management |
   | deployments | create, delete, get, list, update | Workspace provisioning |
