# Storage Core

Provides storage capabilities for the cluster through distributed block storage, object storage, and network filesystem support.

## Quick Links

<a href="https://garagehq.deuxfleurs.fr/" target="_blank"><img src="../../../.static/images/logos/garage.svg" width="32" height="32" alt="Garage"></a> <a href="https://longhorn.io/" target="_blank"><img src="../../../.static/images/logos/longhorn.svg" width="32" height="32" alt="Longhorn"></a> <a href="https://min.io/" target="_blank"><img src="../../../.static/images/logos/minio.svg" width="32" height="32" alt="MinIO"></a> <a href="https://github.com/kubernetes-csi/csi-driver-nfs" target="_blank"><img src="../../../.static/images/logos/nfs-csi-driver.png" width="32" height="32" alt="NFS CSI Driver"></a>

## Overview

The storage-core module provides four main capabilities:

1. Block Storage
   - Distributed block storage across cluster nodes
   - Volume replication and auto-balancing
   - Snapshot and backup management
   - Data integrity verification

2. Object Storage
   - S3-compatible API access
   - Multi-user access control
   - Bucket lifecycle management
   - Web-based administration console

3. Network Storage
   - Dynamic provisioning of volumes from external NFS shares
   - Flexible mount options
   - Storage class customization
   - FSGroup policy support

4. Declarative Object Storage (Garage)
   - S3-compatible API and admin API served by an operator-managed Garage cluster
   - Bucket/key/layout lifecycle declared through `GarageCluster`/`GarageBucket`/`GarageKey` custom resources rather than imperative Helm-chart provisioning
   - Configurable replication factor, with independently sized metadata and data volumes
   - Public bucket website hosting through Garage's `[s3_web]` module, since Garage has no S3 bucket-policy support
   - Deployed alongside MinIO while it is evaluated as MinIO's eventual replacement

### Component Details

| Component | Primary Role | Integration Points |
| ----------- | ------------- | ------------------- |
| Longhorn | Distributed block storage | • Provides replicated persistent volumes for stateful applications<br>• Manages volume snapshots and backups<br>• Ensures data availability through replication<br>• Enables volume expansion and data integrity checks |
| MinIO | S3-compatible object storage | • Provides S3-compatible storage for applications<br>• Manages bucket policies and user access<br>• Enables object lifecycle management<br>• Exposes metrics for monitoring |
| Garage | Declaratively provisioned S3-compatible object storage | • Garage operator reconciles `GarageCluster`/`GarageBucket`/`GarageKey`/`GarageNode` custom resources into a running Garage `StatefulSet`<br>• Configurable replication factor with independently sized metadata and data volumes<br>• Serves opted-in bucket contents anonymously through Garage's website hosting module<br>• Exposes Prometheus metrics generated directly from the `GarageCluster` resource |
| CSI Driver NFS | External NFS share integration | • Enables using external NFS shares as persistent volumes<br>• Supports dynamic volume provisioning from NFS shares<br>• Manages mount options and access modes<br>• Integrates with Kubernetes storage classes |

## Prerequisites

1. Required Secrets

   | Secret Name                | Purpose                                                    | Required Keys             |
   | -------------------------- | ---------------------------------------------------------- | ------------------------- |
   | minio-admin-credentials    | MinIO administrator access                                 | rootUser, rootPassword    |
   | garage-credentials         | Garage admin API token and inter-node RPC shared secret    | admin-token, rpc-secret   |

2. Required Variables

   | Variable | Purpose | Required By |
   | ---------- | --------- | ------------- |
   | domain_name | Domain for MinIO and Garage S3 API endpoints | MinIO ingress, Garage S3 API ingress |
   | secret_store | Bitwarden `ClusterSecretStore` name | minio-admin-credentials and garage-credentials ExternalSecrets |
   | cert_issuer | cert-manager `ClusterIssuer` name | Garage website endpoint TLS certificate |
   | garage_admin_token_key | Bitwarden key for the Garage admin API token | garage-credentials ExternalSecret |
   | garage_rpc_secret_key | Bitwarden key for the inter-node RPC shared secret | garage-credentials ExternalSecret |
   | garage_replication_factor | Data replication factor across Garage storage nodes | GarageCluster |
   | garage_storage_replicas | Garage storage node (StatefulSet) replica count | GarageCluster |
   | garage_storage_class | Storage class for Garage's metadata and data volumes | GarageCluster |
   | garage_metadata_size | Size of Garage's metadata volume | GarageCluster |
   | garage_data_size | Size of Garage's data volume | GarageCluster |
   | garage_web_root_domain | Root domain for Garage's anonymous per-bucket website hosting | GarageCluster webApi, website ingress and certificate |

## Usage

### Block Storage

```yaml
# Example: Creating a Longhorn storage class with replication
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-replicated
allowVolumeExpansion: true
parameters:
  fsType: ext4
  numberOfReplicas: "2"              # Maintain 2 replicas for redundancy
  staleReplicaTimeout: "2880"        # 48 hours (in minutes)
  dataLocality: "best-effort"        # Optimize I/O performance
  recurringJobSelector: '[{"name":"default", "isGroup":true}, {"name":"snapshot-ops", "isGroup":true}]'
provisioner: driver.longhorn.io
reclaimPolicy: Retain                # Preserve data when PVC is deleted
volumeBindingMode: WaitForFirstConsumer  # Schedule volume near the pod

---
# Example: Creating a persistent volume claim
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: example-pvc
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: longhorn-replicated
  resources:
    requests:
      storage: 10Gi
```

### Object Storage Configuration

```yaml
# Example: Creating a bucket
apiVersion: v1
kind: ConfigMap
metadata:
  name: minio-extra-config
data:
  minio-buckets.yaml: |
    buckets:
      - name: example-bucket
        policy: none
        purge: false
```

### Network Storage Configuration

```yaml
# Example: Creating an NFS storage class with security options
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs.example.com
  share: /share
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
- vers=4.1       # Use NFSv4.1
- proto=tcp      # Use TCP protocol
- noatime        # Don't update access times
- nodiratime     # Don't update directory access times
- nodev          # Prevent device files
- noexec         # Prevent binary execution
- nosuid         # Prevent suid binaries
```

## Dependencies

### Required By

- [observability-core](../observability-core)
- [security-extra](../security-extra)
- [networking-extra](../networking-extra)

### Depends On

- [security-core](../security-core)

## Notes

- **Garage's operator is not where the data lives.** Garage's storage nodes run as an ordinary `StatefulSet` reconciled from the `GarageCluster` resource; the operator's role is to keep that reconciliation declarative. If the operator project were to be abandoned, the `StatefulSet`s keep serving Garage exactly as deployed and can be adopted and managed manually — the blast radius of losing the operator is "provisioning stops being declarative," not "storage stops working."
- **No Garage buckets or keys ship with this module.** `GarageBucket` and `GarageKey` are cluster-wide custom resources; consuming app modules create their own against this cluster rather than this module pre-declaring any, keeping the module free of application-specific state.
- **Garage's credentials are not Helm `lookup`-generated.** The upstream Garage Helm chart generates its admin/RPC secrets via a `lookup` function, which returns empty on helm-controller's dry-run and silently regenerates on every reconcile. This module sources both secrets from Bitwarden via `ExternalSecret` instead.
- **Garage's `metadataFsync` is set explicitly.** Garage defaults this to off, and upstream's own documentation reports LMDB corruption after an unclean shutdown with it off. It is set to `true` here as a deliberate durability-over-throughput choice, currently under active re-evaluation — treat it as a considered default, not a fixed conclusion.
- **Garage operator image signature verification is not enforced at admission.** The operator publishes cosign keyless-signed images with SLSA provenance and an SBOM, but this repo has no Kyverno `verifyImages` policy yet to check that signature — the chart and image are pinned by version/digest instead.
- **Garage runs alongside MinIO, not in place of it.** Both are deployed by this module while Garage is evaluated as MinIO's eventual replacement.
