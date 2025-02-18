# Storage Core

Provides storage capabilities for the cluster through distributed block storage, object storage, and network filesystem support.

## Quick Links

- [Longhorn Documentation](https://longhorn.io/docs/)
- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [CSI Driver NFS Documentation](https://github.com/kubernetes-csi/csi-driver-nfs/blob/master/docs/README.md)

## Overview

The storage-core module provides three main capabilities:

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

### Component Details

| Component | Primary Role | Integration Points |
|-----------|-------------|-------------------|
| Longhorn | Distributed block storage | • Provides replicated persistent volumes for stateful applications<br>• Manages volume snapshots and backups<br>• Ensures data availability through replication<br>• Enables volume expansion and data integrity checks |
| MinIO | S3-compatible object storage | • Provides S3-compatible storage for applications<br>• Manages bucket policies and user access<br>• Enables object lifecycle management<br>• Exposes metrics for monitoring |
| CSI Driver NFS | External NFS share integration | • Enables using external NFS shares as persistent volumes<br>• Supports dynamic volume provisioning from NFS shares<br>• Manages mount options and access modes<br>• Integrates with Kubernetes storage classes |

## Prerequisites

1. Required Secrets

   | Secret Name | Purpose | Required Keys |
   |-------------|---------|---------------|
   | minio-admin-credentials | MinIO administrator access | rootUser, rootPassword |

2. Required Variables

   | Variable | Purpose | Required By |
   |----------|---------|-------------|
   | domain_name | Domain for MinIO endpoints | MinIO ingress |

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
