# Architecture Overview

## Repository Purpose

This repository serves as a collection of Kubernetes modules that can be composed to build complete cluster configurations. The actual cluster deployments and environment-specific configurations are maintained in separate repositories that reference and use these modules.

## Module Types

### Infrastructure Modules

- Provide core cluster services and capabilities
- Focus on platform capabilities and operational needs
- Located in `/infrastructure` directory
- Examples:
  - security-core/extra: Certificate and secret management
  - storage-core: Block, object, and NFS storage
  - networking-core/extra: CNI and load balancing
  - kubernetes-core/extra: Core kubernetes enhancements
  - clusterops-core/extra: Operational capabilities
  - observability-core: Monitoring and metrics

### Application Modules

- Deliver end-user functionality
- Depend on infrastructure module capabilities
- Located in `/apps` directory
- Examples:
  - Media services
  - Home automation
  - Development tools

### Component Modules

- Provide cross-cutting configuration and capabilities
- Apply consistent configuration across multiple modules
- Located in `/components` directory
- Examples:
  - SSO configuration
  - Backup components
  - Cross-cutting patches

## Core/Extra Pattern

- Used to break circular dependencies across various module types
- Separates essential services (core) from additional features (extra)
- Currently implemented in:
  - Networking modules
  - Observability modules
  - Kubernetes modules
  - ClusterOps modules
  - Security modules
- Enables gradual deployment of complex systems

## Storage Capabilities

1. Block Storage
   - Provides persistent block storage volumes
   - Used for stateful applications

2. Object Storage
   - S3-compatible object storage
   - Used for unstructured data

3. External NFS
   - Support for external NFS volume mounts
   - Enables integration with existing storage systems

## Configuration Methods

1. Kustomize Patches
   - Primary method for module-specific parameterization
   - Applied through Flux Kustomization
   - Allows targeted modifications

2. FluxCD Post-build Variables
   - Used for cluster-wide settings
   - Applied through Flux Kustomization
   - Handles complex parameterization needs

3. Component Overlays
   - Applied through Kustomize components
   - Manages cross-cutting concerns
   - Enables flexible configuration composition

## Testing Framework

Current:

- GitHub Actions workflows
- Series of steps (preparation, action, validation)
- Each step implemented via shell scripts
- Limited to CI environment
- Manual kubernetes operation specification

Planned Migration:

- Moving to kyverno/chainsaw framework
- Will enable local testing during development
- Provides clear kubernetes context awareness
- More structured approach to kubernetes operations
- Can run both locally and in CI

## Monitoring & Metrics

1. Metrics Collection
   - Comprehensive metrics collection via Prometheus
   - Service monitors for various components
   - Custom metrics where needed

2. Alerting Status
   - Currently limited alert configuration
   - Need for improved default alerts per module
   - Planned enhancement for sensible default alerts

## Module Usage

1. Module Definition
   - Modules defined in this repository
   - Self-contained units of functionality
   - Independent versioning
   - Clear interface definitions

2. Module Consumption
   - Modules used by separate cluster configuration repositories
   - Environment-specific configuration applied at point of use
   - Cluster-specific details defined outside modules
   - Enables flexibility across different environments
