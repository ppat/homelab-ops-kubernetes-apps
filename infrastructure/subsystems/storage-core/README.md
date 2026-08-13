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

4. Single-Node Object Storage (Garage)
   - S3-compatible API and admin API served by a single-replica Garage `Deployment`, run as plain Kubernetes resources with no operator or CRDs
   - Metadata and data volumes on separate, externally-provisioned PVCs, referenced by claim name
   - Cluster layout (the one imperative step Garage needs before it serves any request) assigned and applied in-process at startup via Garage's own `--single-node` flag, before any listener binds
   - Public bucket website hosting through Garage's `[s3_web]` module, since Garage has no S3 bucket-policy support
   - Deployed alongside MinIO while it is evaluated as MinIO's eventual replacement
   - `PrometheusRule` alerting on node reachability, internal RPC error rate, block resync health, and disk space -- queryable state only, since this estate has no AlertManager routing configured
   - Grafana dashboard shipped with the module, covering capacity, disk reclamation, S3 workload and integrity -- Garage has no admin UI of its own, so this is the operator's console

### Component Details

| Component | Primary Role | Integration Points |
| ----------- | ------------- | ------------------- |
| Longhorn | Distributed block storage | • Provides replicated persistent volumes for stateful applications<br>• Manages volume snapshots and backups<br>• Ensures data availability through replication<br>• Enables volume expansion and data integrity checks |
| MinIO | S3-compatible object storage | • Provides S3-compatible storage for applications<br>• Manages bucket policies and user access<br>• Enables object lifecycle management<br>• Exposes metrics for monitoring |
| Garage | Single-node S3-compatible object storage | • Runs as a plain single-replica `Deployment` with `Recreate` strategy, referencing externally-provisioned metadata/data PVCs by claim name<br>• Started with `garage server --single-node`, which assigns and applies its one-time cluster layout in-process before any listener binds, gated by a `startupProbe` on `/health`<br>• Serves opted-in bucket contents anonymously through Garage's website hosting module<br>• Exposes Prometheus metrics scraped via a `ServiceMonitor`<br>• A `PrometheusRule` alerts on node-down, RPC error rate, block resync errors/queue depth, and low disk space<br>• Ships a Grafana dashboard as a labelled `ConfigMap`, discovered by the Grafana sidecar deployed by observability-core<br>• Bucket/key provisioning is out of this module's scope |
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
   | domain_name | Base domain for all object-storage endpoints; hostnames are composed in-module | MinIO ingress, Garage S3 API and website ingresses, Garage's `[s3_web]` root_domain |
   | secret_store | Bitwarden `ClusterSecretStore` name | minio-admin-credentials and garage-credentials ExternalSecrets |
   | garage_admin_token_key | Bitwarden key for the Garage admin API token | garage-credentials ExternalSecret |
   | garage_rpc_secret_key | Bitwarden key for the inter-node RPC shared secret | garage-credentials ExternalSecret |
   | garage_metadata_claim | Name of the pre-provisioned PVC to use for Garage's metadata volume | Garage Deployment |
   | garage_data_claim | Name of the pre-provisioned PVC to use for Garage's data volume | Garage Deployment |
   | garage_s3_region | AWS-style region Garage signs/validates S3 requests against; must match every S3 client's own configured region (e.g. `loki_s3_region` at Loki's eventual cutover) | Garage `[s3_api]` config |

3. Storage Requirements

   | PVC (by claim name) | Purpose | Access Mode |
   | ---------------------- | --------- | ------------- |
   | ${garage_metadata_claim} | Garage's metadata volume (its LMDB database) | Provisioned externally by the cluster; not defined by this module |
   | ${garage_data_claim} | Garage's object data volume | Provisioned externally by the cluster; not defined by this module |

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

- **Garage runs as plain Kubernetes resources, with no operator and no CRDs.** A single-replica `Deployment`, a config `ConfigMap`, an `ExternalSecret`-sourced `Secret`, a `Service`, two `Ingress`es, a `ServiceMonitor`, a `PrometheusRule`, and a dashboard `ConfigMap` are the entire module — nothing reconciles a custom resource, and nothing needs cluster-wide RBAC.
- **A `Deployment`, not a `StatefulSet`.** Nothing in this module depends on stable per-pod network identity: Garage's node identity comes from a key persisted in its metadata volume, not from the pod's hostname, and the RPC address it advertises points at the `Service`, never a per-pod DNS name. That makes this the same single-instance-on-RWO-volumes shape as MinIO, including MinIO's `Recreate` update strategy — Garage's LMDB metadata store does not tolerate two processes writing to the same volume.
- **Metadata and data PVCs are provisioned externally and referenced by claim name**, matching this repo's storage convention (a module never owns a PVC's lifecycle) — the cluster can pre-provision or statically bind either volume instead of the Deployment forcing dynamic provisioning.
- **Garage serves no request until its cluster layout is assigned and applied**, which is imperative and versioned rather than reconciled. This module runs Garage with `garage server --single-node` (added in v2.3.0, the version this module pins), which stages and applies a one-node layout in-process before any listener binds — no separate bootstrap step, no call to Garage's own admin API from outside the process. Capacity is auto-detected from the data volume's total filesystem size and zone is hardcoded by Garage itself to `dc1`; both are inert at one node (100% of partitions land on the only node regardless) but become real placement inputs the moment a second node exists. **`--single-node` hard-errors at startup once the cluster layout version exceeds 1** — it does not skip or no-op against an existing layout past that point — so it must be removed before any deliberate layout change beyond the initial one (a capacity/zone correction, or adding a second node), or that change crashloops the Deployment; see `deployment.yaml`'s own comment on the flag for the exact failure mode.
- **No Garage buckets or keys ship with this module.** Bucket/key provisioning is out of scope here and lives in Terraform instead; the admin API this module exposes (bearer-token authenticated via the `garage-credentials` Secret's `admin-token` key) is what a Terraform provider talks to.
- **`metadata_fsync` is set explicitly to `true`.** Garage defaults this to off, and upstream's own documentation reports LMDB corruption after an unclean shutdown with it off. At `replication_factor = 1` there is no second copy to fall back on, so this is a deliberate durability-over-throughput choice.
- **Garage's website hosting has no wildcard subdomain routing.** The `garage-web` ingress covers only its own host, matching MinIO's ingresses in relying on Traefik's cluster-wide default certificate rather than a per-host `cert-manager` `Certificate`. A bucket that wants its own vhost-style subdomain needs its own `Ingress` and TLS outside this module.
- **Garage runs alongside MinIO, not in place of it.** Both are deployed by this module while Garage is evaluated as MinIO's eventual replacement.
- **Garage's `PrometheusRule` only covers conditions meaningful at `replication_factor = 1` / one node.** Half of the alert set this module was evaluated against (quorum health, peer connectivity, storage-node and partition consistency across replicas) is deliberately omitted: at a single node those conditions are trivially satisfied whenever the process is up, so keeping them would just repeat the node-down alert under different names, not add signal. `PrometheusRule` defines queryable alert state only — this estate has no AlertManager routing configured, so nothing pages or notifies on these.
- **The Garage dashboard is a console replacement, not a decoration.** Garage ships no admin UI, so Grafana is the only place bucket-store health, capacity and reclamation are visible without shelling into a pod. It is shipped from this module rather than from observability-core so that a cluster which does not deploy Garage never inherits a dashboard with nothing behind it. The coupling is one-way and soft: the `ConfigMap` is inert unless a Grafana dashboard sidecar is watching for its label, and nothing in this module fails if one is not.
- **Two things an operator will look for are not in Garage's metric surface, and the dashboard says so rather than approximating them silently.** Garage v2.3.0 publishes no per-bucket or per-key dimension on any metric, so usage cannot be split by consumer — separating Loki's footprint from Authentik's requires the admin API (`GetBucketInfo`), not Prometheus. It also publishes no live-bytes total, which is the denominator a true consumed-vs-live amplification ratio needs; the dashboard substitutes bytes-per-object and bytes-per-referenced-block, labels both as proxies, and states what they cannot distinguish.
- **Most of Garage's counters do not exist until they first increment.** Its OpenTelemetry counters and histograms — every `api_s3_*`, the block I/O and corruption counters, the RPC error counters — are absent from a healthy node's `/metrics` entirely rather than present and zero, while its observable gauges (`table_*`, `block_rc_size`, `garage_local_disk_*`, `cluster_*`) are always emitted. This is why any expression combining them coalesces each term with `or vector(0)`: in PromQL an empty vector added to anything yields an empty vector, so an uncoalesced sum of absent counters renders nothing at all and cannot be told apart from zero.
- **The dashboard coalesces empty panels selectively, and the distinction is deliberate.** Grafana cannot render custom empty-state text when a query returns no series at all — `noValue` is only honoured for series that exist but contain nulls — so an unemitted metric looks exactly like a broken panel. Where zero is the truthful reading (a counter that has never incremented: S3 requests, S3 errors, block corruptions) the query coalesces to an explicit zero line, guarded by `and on() absent(...)` so the placeholder disappears by itself the moment the real series appears. Where zero would be a false claim it is **not** coalesced: an amplification ratio drawn at 0 would assert there is no amplification, and `0/0` ratios like versions-per-object or bytes-per-object with no objects are undefined, not zero. Those panels stay empty, and where the cause is an unshipped change rather than a transient data state, the panel title carries the reason — the only place a reader can see it.
