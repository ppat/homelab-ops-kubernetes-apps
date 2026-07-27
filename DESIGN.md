# Kubernetes Platform Modules

This repository contains modules for deploying applications and infrastructure on Kubernetes clusters using FluxCD. Each module is a self-contained unit that can be composed to build complete cluster configurations.

This document describes the architecture and design of those modules. Related docs: [README.md](./README.md) (module catalog and navigation), [TESTING.md](./TESTING.md) (how modules are tested and validated), [OPERATIONS.md](./OPERATIONS.md) (development workflow, versioning, and releases), and [CLAUDE.md](./CLAUDE.md) (working conventions and commands).

```mermaid
flowchart TB
    %% Color scheme with better contrast
    classDef infra fill:#dcfce7,stroke:#059669,color:#064e3b
    classDef apps fill:#dbeafe,stroke:#3b82f6,color:#1e3a8a
    classDef components fill:#fee2e2,stroke:#dc2626,color:#7f1d1d
    classDef clusterStyle fill:none,stroke:none,color:#334155
    classDef legend fill:none,stroke:none

    subgraph Cluster["Kubernetes Cluster"]
        subgraph Infrastructure["Infrastructure Modules"]
            ICap[Cluster Capabilities]:::infra
            IServ[Core Services]:::infra
            ISec[Security & Access]:::infra
            IStore[Storage & State]:::infra
            IMon[Monitoring & Observability]:::infra
        end

        subgraph Applications["Application Modules"]
            AFunc[End-user Functionality]:::apps
            AServ[Application Services]:::apps
        end

        subgraph Components["Component Modules"]
            CSSO[SSO Configuration]:::components
            CBack[DB Backups]:::components
            CCred[PVC Backups]:::components
        end

        %% Dependencies
        Infrastructure --> Applications
        Components -.-> Infrastructure
        Components -.-> Applications
    end

    %% Simple legend at bottom
    subgraph Legend[" "]
        direction LR
        leg_infra[Infrastructure Modules]:::infra
        leg_apps[Application Modules]:::apps
        leg_comp[Component Modules]:::components
    end

    class Cluster clusterStyle
    class Legend legend
```

## Module Types and Organization

```mermaid
classDiagram
    class Module {
        +kustomization.yaml
        +CHANGELOG.md
        +namespace.yaml
    }

    class InfrastructureModule {
        +Provides core services
        +Often has multiple apps
    }

    class ApplicationModule {
        +Single or multiple apps per module
        +End-user functionality
    }

    class ComponentModule {
        +Cross-cutting concerns
        +Configuration patches
    }

    Module <|-- InfrastructureModule
    Module <|-- ApplicationModule
    Module <|-- ComponentModule
```

### Infrastructure Modules

Infrastructure modules provide the foundational capabilities that both the cluster itself and its applications require. These modules:

- Supply core services (monitoring, storage, networking)
- Focus on platform capabilities and operational needs
- May provide end-user functionality, but it's not their primary purpose

### Application Modules

Application modules focus on delivering end-user functionality. They:

- Provide services directly consumed by end users
- Depend on capabilities provided by infrastructure modules
- Are typically more focused in scope than infrastructure modules

### Component Modules

Component modules provide cross-cutting configuration and capabilities:

- Apply consistent configuration across multiple modules
- Manage cross-cutting concerns like SSO or backup capabilities
- Can be applied to both infrastructure and application modules
- Structured as Kustomize components for flexible application

### Core vs Extra Pattern

Modules, particularly infrastructure modules, often follow a core/extra pattern to manage complex dependencies:

```text
infrastructure/subsystems/
├── security-core/     # Core security services
├── security-extra/    # Additional security features
├── networking-core/   # Essential networking
└── networking-extra/  # Advanced networking features
```

This pattern:

- Breaks circular dependencies between modules
- Allows gradual deployment of complex systems
- Core modules contain essential services
- Extra modules contain additional features that depend on other modules

Example scenario:

```text
Module X (apps a,b,c) and Module Y (apps p,q)
- If c depends on q, but p depends on a and b
- Solution: Split into X-core (a,b) and X-extra (c)
- Deployment order: X-core → Y → X-extra
```

## Dependencies

### Types of Dependencies

#### Hard Dependencies

- Required for system functionality
- Used when module needs resources from another module to function
- Examples:
  - storage capabilities from storage-core module
  - secret-store for  from security-core module
- Defined at point of use, not within modules themselves
  - Explicitly declared in FluxCD Kustomization's `spec.dependsOn`
- Used sparingly and only when necessary due to:
  - Added complexity in troubleshooting
  - Increased deployment time (blocks parallel reconciliation)
- Valuable for:
  - Ensuring systemic dependencies (e.g., external-secrets secrets stored from security-core module)
  - Eliminating preventable errors during first-time deployments
  - Maintaining upgrade safety between dependent modules

Examples:

```yaml
# At point of use in cluster configuration
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-storage-core
spec:
  dependsOn:
  - name: infra-security-core
```

#### Soft Dependencies

- Required for end-user functionality
- Not explicitly declared
- Rely on Kubernetes's eventually consistent model
- Monitored via Prometheus `ServiceMonitor`s and `PrometheusRule`s
- Examples:
  - Ingress controller availability
  - Load balancer readiness

### Dependency Management

1. Only hard dependencies are explicitly declared
2. Dependencies are verified during testing
3. Module versioning is independent of one another
4. Changes to a dependency don't automatically cascade as dependency relationship is codified at point of use in FluxCD kustomization that includes the module.
5. Core/Extra pattern used to break circular dependencies

### Dependency Flow Example

```mermaid
flowchart LR
    subgraph core ["Core Modules"]
        direction LR
        sec-core["infra-security-core"]
        store-core["infra-storage-core"]
        net-core["infra-networking-core"]
        db-core["infra-database-core"]
    end

    subgraph extra ["Extra Modules"]
        direction LR
        sec-extra["infra-security-extra"]
        net-extra["infra-networking-extra"]
    end

    %% Core dependencies
    store-core --> sec-core
    net-core --> sec-core

    %% Extra dependencies
    sec-extra --> sec-core
    sec-extra --> store-core
    sec-extra --> db-core

    net-extra --> sec-core
    net-extra --> store-core
    net-extra --> net-core

    style core fill:#d1fae5
    style extra fill:#fee2e2
```

### Complete Module Dependency Graph

Having covered dependency types, management approaches, and seen a simplified example, here is the complete dependency graph showing all current infrastructure modules and their relationships. This represents the actual module hierarchy and interdependencies within the Kubernetes platform, illustrating how core services, extended components, and applications interconnect.

```mermaid
flowchart TB
    %% Color scheme with better contrast
    classDef core fill:#dcfce7,stroke:#059669,color:#064e3b
    classDef extra fill:#fee2e2,stroke:#dc2626,color:#7f1d1d
    classDef apps fill:#dbeafe,stroke:#3b82f6,color:#1e3a8a
    classDef subgraphStyle fill:#ffffff,stroke:#94a3b8,color:#334155
    classDef legend fill:none,stroke:none

    subgraph Infrastructure["Infrastructure"]
        %% Core Components
        security-core[security-core]:::core
        storage-core[storage-core]:::core
        kubernetes-core[kubernetes-core]:::core
        networking-core[networking-core]:::core
        clusterops-core[clusterops-core]:::core
        observability-core[observability-core]:::core
        database-core[database-core]:::core

        %% Extended Components
        kubernetes-extra[kubernetes-extra]:::extra
        security-extra[security-extra]:::extra
        networking-extra[networking-extra]:::extra
        observability-extra[observability-extra]:::core
    end

    %% Core Dependencies
    storage-core & networking-core & observability-core --> security-core
    observability-core --> storage-core
    observability-core --> kubernetes-core

    %% Extra Dependencies
    security-extra --> security-core & storage-core & database-core
    networking-extra --> security-core & storage-core & networking-core
    observability-extra --> observability-core
    kubernetes-extra --> kubernetes-core

    subgraph Apps["Applications"]
        direction TB
        apps-ai[ai]:::apps
        apps-bitwarden[bitwarden]:::apps
        apps-coder[coder]:::apps
        apps-downloaders[downloaders]:::apps
        apps-harbor[harbor]:::apps
        apps-home-automation[home-automation]:::apps
        apps-media[media]:::apps
    end

    %% Main dependency
    Infrastructure --> Apps

    %% Simple legend at bottom
    subgraph Legend[" "]
        direction LR
        leg_core[Core]:::core
        leg_extra[Extended]:::extra
        leg_apps[Apps]:::apps
    end

    class Legend legend
```

## Configuration

### Configuration Methods

#### 1. Kustomize Patches

- Preferred for module-specific parameterization
- Applied through Flux Kustomization
- Examples:

  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  spec:
    patches:
    - target:
        kind: HelmRelease
        name: app-release
      patch: |-
        - op: replace
          path: /spec/values/replicaCount
          value: 3
  ```

#### 2. FluxCD Post-build Variables

- Primarily used for cluster-wide settings
- Additionally used in scenarios where Kustomize patching is too limited to handle a need type of parameterization
- Applied through Flux Kustomization
- Example:

  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  spec:
    postBuild:
      substitute:
        domain_name: cluster.example.com
      substituteFrom:
      - kind: Secret
        name: cluster-secrets
  ```

#### 3. Component Overlays

- Applied through Kustomize components
- Used for cross-cutting concerns
- Example:

  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  spec:
    components:
    - ../../../components/sso
    - ../../../components/db-backups
  ```

## Credentials, Secrets, and RBAC

Module-scoped lessons only — cluster-wide RBAC policy (what a given
cluster-scoped role should actually contain) is the consuming clusters
repo's concern, documented in its own DESIGN.md, not here.

- **Cluster-wide grants are a prerequisite, not something a module ships.** A
  module ships only its own namespaced ServiceAccount(s); any
  ClusterRole/ClusterRoleBinding it needs is a documented prerequisite the
  consuming cluster must provide (see [Hard Dependencies](#hard-dependencies)
  and each module's own README `## Dependencies`/`## Prerequisites` section)
  — never shipped by the module and never implied as something the module
  itself grants.
- **Prefer a file-mounted secret over an env var for a credential to
  something outside the cluster.** An env var is fixed for the life of the
  process; a mounted file can be re-read on rotation — but only if the
  consuming process actually re-reads it. Verify that per application: where
  a process only loads the file at startup, a restart trigger (e.g. a
  Reloader annotation) is required for rotation to mean anything.
- **Never mount a secret via `subPath` if its value can rotate.** `subPath`
  mounts are resolved once at pod start and never updated, silently
  defeating any external rotation mechanism. Relatedly, never mount anything
  — `subPath` or otherwise — at a path nested inside another volume's own
  mount root; container init fails outright.
- **An application's own allowlist is not a network boundary.** An
  app-level egress/SSRF allowlist constrains only that application's own
  outbound calls; it says nothing about, and does not restrict, any other
  workload in the cluster.
- **Unauthenticated in-cluster access needs a named trust boundary.** Where a
  service is reached without its own authentication, identify what actually
  enforces access control (a gateway doing key/token scoping, a
  NetworkPolicy, etc.) and confirm it's real, rather than assuming
  in-cluster proximity is a boundary by itself.

## Testing and Validation

Each module is tested as a complete unit in CI, even when only one component
changes, and all manifests are validated with `kubeconform` on every pull
request. The full test flow, test components, and validation strategy are
documented in [TESTING.md](./TESTING.md).

## Bootstrap and CRDs

### Bootstrap Process

```mermaid
flowchart TD
    A[New Cluster] --> B[Install FluxCD]
    B --> C[Apply CRDs]
    C --> D[Create namespaces]
    D --> E[Deploy Modules]

    subgraph bootstrap [Bootstrap Phase]
        A
        B
        C
        D
    end

    subgraph deployment [Module Deployment]
        direction TB
        E
        note["Modules deploy according to their dependency relationships"]
    end
```

### CRD Management

- Location: `bootstrap/crds/`
- Only engaged during:
  1. First-time cluster setup
  2. Disaster recovery scenarios
- Updates to CRDs handled by:
  - Helm charts in modules
- Primary purpose:
  - Enable custom resource creation prior to the module that normally installs the CRDs is deployed
  - Example:
    - Custom resource types like `ServiceMonitor` or `PrometheusRule` from prometheus operator are available for use in any modules that need them before the `observability-core` module that installs the prometheus operator is deployed.
    - Other examples include `Certificate`s from `cert-manager` or `ExternalSecret`s from `external-secrets` operator.

## Design Principles

### 1. Module Independence

- Self-contained functionality
- Clear boundaries
- Independent versioning
- Any dependencies between modules are specified at point of use than within the module
- Cluster or deployment environment specific details are specified external to the module.
  - This enables this aspects to vary from cluster to cluster or from production environment to testing environment.
  - Examples:
    - secret store to fetching secrets from
    - storage class used for PVCs

### 2. Configuration Flexibility

- Multiple configuration methods
- Environment-specific settings
- Component-based customization
- Patch-based modifications

### 3. Dependency Management

- Explicit hard dependencies
- Implicit soft dependencies
- Dependency cycle prevention
- Core/Extra pattern usage

### 4. Testing Integrity

- Module-level testing
- Complete dependency validation
- Resource state verification

### 5. Operational Clarity

- Clear module categorization
- Consistent naming patterns
- Change tracking
- Version update automation

## Development Workflow

Changes flow through local pre-commit checks, PR validation, and per-module CI
tests before landing on main; modules are then versioned and released
independently via release-please, with dependency bumps automated by Renovate.
The quality controls, version management, release process, and maintenance
practices are documented in [OPERATIONS.md](./OPERATIONS.md).

## End-to-End Infrastructure Automation: How Everything Comes Together

| Category | Tool/Mechanism | Purpose | Key Features & Data |
| --- | --- | --- | --- |
| **GitOps & Continuous Sync** | FluxCD GitOps | Cluster deployment & state reconciliation | - Continuously syncs desired state from Git<br>- Uses FluxCD Kustomization CRDs for automated module deployments<br>- Acts as the central control plane for GitOps workflows<br>- Propagates changes via FluxCD's continuous reconciliation |
| **Application Deployment** | HelmRelease via FluxCD | Deploy applications & version upgrades | - FluxCD HelmRelease defines how a helm deployment can be carried out<br>- Coordinates version upgrades<br> |
| **Configuration Management** | Kustomize Patches via FluxCD | Module-specific parameterization | - Applies inline patches for targeted configuration adjustments<br>- Modifies resource definitions<br> |
| **Configuration Management** | Kustomize Overlays via FluxCD | Environment-specific & cross-cutting customization | - Implements composable overlays for configurations that must be selectively applied<br>- Separates cross-cutting concerns (e.g., SSO, backups) from core module logic |
| **Dependency Orchestration** | Module Dependency Orchestration | Define module dependencies & deployment sequencing | - Declares explicit hard dependencies using FluxCD's `spec.dependsOn`<br>- Makes hard dependencies explicit<br>- Uses a Core/Extra pattern to prevent circular dependencies and enforce reliable deployment order |
| **Cluster Setup** | Manual Bootstrap | Initial cluster setup & CRD enablement | - Bootstraps new clusters by installing FluxCD, applying CRDs, and creating namespaces<br>- Ensures CRDs are established for custom resource creation prior to module deployment<br> |
| **CI/CD & Validation** | GitHub Actions | Automated testing, linting & validation | - Integrates GitHub Actions workflows for continuous integration and validation<br>- Executes quality checks (e.g., YAML Lint, ShellCheck)<br>- Uses kubeconform to validate Kubernetes manifests and pre-commit hooks for ensuring code quality |
| **Version Management** | Renovate Bot via Github Actions | Automated version upgrades | - Scans for dependency updates across and within modules<br>- Triggers automated PRs merges for patch/minor updates<br>- Requires human review for major version changes |
| **Release Coordination** | Release-Please | Automates release processes & changelog management | - Generates release PRs with version bumps<br>- Automatically updates changelog files<br>- Creates git tags as part of the release process<br> |
