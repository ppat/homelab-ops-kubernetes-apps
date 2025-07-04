# Security Core

Provides foundational security services that enable cluster services to obtain certificates and sync secrets from external secret stores. Additionally enables policy auditing and/or enforcement through Kyverno.

## Quick Links

<a href="https://cert-manager.io/" target="_blank"><img src="../../../.static/images/logos/cert-manager.svg" width="32" height="32" alt="cert-manager"></a> <a href="https://external-secrets.io/" target="_blank"><img src="../../../.static/images/logos/external-secrets.svg" width="32" height="32" alt="external-secrets"></a> <a href="https://cert-manager.io/docs/trust/trust-manager/" target="_blank"><img src="../../../.static/images/logos/cert-manager.svg" width="32" height="32" alt="trust-manager"></a> <a href="https://bitwarden.com/" target="_blank"><img src="../../../.static/images/logos/bitwarden.svg" width="32" height="32" alt="Bitwarden SDK Server"></a>
<a href="https://kyverno.io/" target="_blank"><img src="../../../.static/images/logos/kyverno.png" width="32" height="32" alt="Kyverno"></a>
<a href="https://kyverno.github.io/policy-reporter/" target="_blank"><img src="../../../.static/images/logos/kyverno.png" width="32" height="32" alt="Policy Reporter"></a>

## Overview

The security-core module provides three main capabilities:

1. Certificate Management
   - Automated certificate lifecycle management

2. Secret Management
   - Integration with external secret management services
   - Automated synchronization of external secrets to Kubernetes secrets

3. Trust Distribution
   - Enables sharing certificates between namespaces
   - Uses certificate bundles to define distribution rules
   - Automates certificate copying based on bundle definitions

4. Policy Management
   - Kubernetes policy enforcement
   - Policy validation and mutation
   - Policy reporting and visualization
   - Grafana dashboards for policy metrics
   - Web UI for policy reports

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| cert-manager | Certificate lifecycle management | • Manages the full lifecycle of certificates within the cluster<br>• Provides a self-signed issuer for development environments<br>• Enables configuration of production certificate issuers like Let's Encrypt |
| external-secrets | Secret management and synchronization | • Integrates with external secret management services<br>• Synchronizes external secrets into Kubernetes secrets<br>• Supports multiple secret store configurations |
| trust-manager | Certificate trust distribution | • Enables defining certificate distribution rules via bundles<br>• Copies certificates between namespaces based on bundle rules<br> |
| Bitwarden SDK Server | Bitwarden integration service | • Enables using Bitwarden Secrets Manager as a secret provider<br>• Provides secure access to Bitwarden secrets via external-secrets<br>• Utilized only when using Bitwarden as a secret store |
| Kyverno | Policy enforcement | • Validates resources against policies<br>• Mutates resources to enforce standards<br>• Generates policy reports<br>• Integrates with Prometheus for metrics<br>• Supports high availability (3 replicas) |
| Policy Reporter | Policy visualization | • Collects policy reports<br>• Provides web UI for policy violations<br>• Integrates with Grafana<br>• Processes Kyverno events<br>• Exposes metrics for monitoring |

## Prerequisites

None

## Usage

This depicts how this module can be used to fetch secret from Bitwarden Secret Manager by defining a `ClusterSecretsStore` for Bitwarden.

1. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | bitwarden-machine-account | Bitwarden Secrets Manager access | access-token |

2. Required Variables

   | Variable | Purpose | Required By |
   |----------|---------|-------------|
   | BITWARDEN_ORGANIZATION_ID | Organization identifier for Bitwarden | external-secrets |
   | BITWARDEN_PROJECT_ID | Project identifier for Bitwarden | external-secrets |

3. Secret Store Configuration

To use Bitwarden Secrets Manager as a secret store, create a ClusterSecretStore:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: bitwarden-secrets
spec:
  provider:
    bitwardensecretsmanager:
      # Bitwarden API endpoints
      apiURL: https://vault.bitwarden.com/api
      identityURL: https://vault.bitwarden.com/identity

      # Authentication
      auth:
        secretRef:
          credentials:
            name: bitwarden-machine-account
            key: access-token
            namespace: external-secrets

      # Bitwarden SDK Server configuration
      bitwardenServerSDKURL: https://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998

      # Organization and project identifiers
      organizationID: ${BITWARDEN_ORGANIZATION_ID}
      projectID: ${BITWARDEN_PROJECT_ID}
```

Then create an ExternalSecret to fetch secrets:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example-secret
spec:
  secretStoreRef:
    name: bitwarden-secrets
    kind: ClusterSecretStore
  target:
    name: example-k8s-secret
  data:
  - secretKey: database-password
    remoteRef:
      key: database-credentials
```

## Dependencies

### Required By

- [storage-core](../storage-core)
- [networking-core](../networking-core)
- [observability-core](../observability-core)

### Depends On

None (foundational module)
