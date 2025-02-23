# Infrastructure Subsystems

This directory contains core infrastructure subsystems that provide foundational capabilities for the Kubernetes cluster. Each subsystem is designed to be self-contained and focuses on a specific infrastructure domain.

## Subsystem Categories

### ClusterOps

#### Core (`clusterops-core/`)

- **Purpose**: Essential cluster operations and management
- **Components**:
  - Flux CD for GitOps workflows
  - System Upgrade Controller for automated cluster upgrades

#### Extra (`clusterops-extra/`)

- **Purpose**: Additional cluster operational tools
- **Components**:
  - Goldilocks for resource recommendation
  - Stakater Reloader for ConfigMap/Secret updates
  - Terraform Controller for infrastructure management

### Database

#### Core (`database-core/`)

- **Purpose**: Core database infrastructure
- **Components**:
  - CloudNative PG operator for PostgreSQL management

### Kubernetes

#### Core (`kubernetes-core/`)

- **Purpose**: Essential Kubernetes components
- **Components**:
  - CoreDNS for cluster DNS
  - Kubernetes API Server configurations

#### Extra (`kubernetes-extra/`)

- **Purpose**: Extended Kubernetes capabilities
- **Components**:
  - Descheduler for optimizing pod placement
  - Device plugins for hardware access
  - Vertical Pod Autoscaler
  - Node Feature Discovery

### Networking

#### Core (`networking-core/`)

- **Purpose**: Core networking infrastructure
- **Components**:
  - External DNS for DNS management
  - MetalLB for load balancing
  - Traefik for ingress control

#### Extra (`networking-extra/`)

- **Purpose**: Additional networking services
- **Components**:
  - PiHole for DNS ad-blocking
  - Tailscale Operator for VPN connectivity
  - UniFi Controller for network management

### Observability

#### Core (`observability-core/`)

- **Purpose**: Core monitoring and logging
- **Components**:
  - Grafana for visualization
  - Prometheus stack for monitoring
  - Loki for log aggregation
  - Promtail for log collection

#### Extra (`observability-extra/`)

- **Purpose**: Extended monitoring capabilities
- **Components**:
  - Kubernetes Event Exporter
  - Node Problem Detector
  - SNMP Exporter
  - Syslog-ng for system logging
  - UnPoller for UniFi metrics

### Security

#### Core (`security-core/`)

- **Purpose**: Core security infrastructure
- **Components**:
  - Cert-manager for certificate management
  - External Secrets for secrets management

#### Extra (`security-extra/`)

- **Purpose**: Additional security services
- **Components**:
  - Authentik for identity management

### Storage

#### Core (`storage-core/`)

- **Purpose**: Storage infrastructure
- **Components**:
  - CSI Driver NFS for network storage
  - Longhorn for distributed storage
  - MinIO for S3-compatible object storage

## Directory Structure

Each subsystem follows a consistent structure:

```plaintext
subsystem-name/
├── CHANGELOG.md          # Version history
├── kustomization.yaml    # Kustomize configuration
├── namespace.yaml        # Namespace definition (if needed)
└── component-name/       # Individual component configurations
    ├── helm-release.yaml # Helm release configuration
    ├── kustomization.yaml
    └── additional configs...
```

## Usage

Each subsystem can be deployed independently using Flux CD, which watches these directories for changes. The `-core` subsystems should be deployed first as they provide essential infrastructure that other components may depend on.

## Dependencies

- Subsystems marked as `-core` are essential and should be deployed first
- Subsystems marked as `-extra` may depend on their corresponding `-core` counterparts
- Cross-subsystem dependencies are documented in individual subsystem READMEs
