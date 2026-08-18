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
   - Cross-engine disk-amplification and per-engine recovery-event recording rules, tracking long-term object-store health independent of which engine is live

3. Network Storage
   - Dynamic provisioning of volumes from external NFS shares
   - Flexible mount options
   - Storage class customization
   - FSGroup policy support

4. Single-Node Object Storage (Garage)
   - S3-compatible API and admin API served by a single-replica Garage `Deployment`, run as plain Kubernetes resources with no operator or CRDs
   - S3, website, and admin endpoints each reachable through their own Ingress hostname; the admin Ingress routes only the bearer-token-guarded `/v2` path, leaving Garage's unauthenticated `/metrics`, `/health`, and `/check` endpoints unreachable from outside the cluster
   - Metadata and data volumes on separate, externally-provisioned PVCs, referenced by claim name
   - Cluster layout (the one imperative step Garage needs before it serves any request) assigned and applied in-process at startup via Garage's own `--single-node` flag, before any listener binds
   - Public bucket website hosting through Garage's `[s3_web]` module, reachable at `<bucket>.garage-web.${domain_name}` for any bucket via a wildcard `Ingress` rule and `Certificate`, since Garage has no S3 bucket-policy support
   - Deployed alongside MinIO while it is evaluated as MinIO's eventual replacement
   - `PrometheusRule` alerting on node reachability, internal RPC error rate, block resync health, and disk space -- queryable state only, since this estate has no AlertManager routing configured
   - Grafana dashboard shipped with the module, covering capacity, disk reclamation, S3 workload and integrity -- Garage has no admin UI of its own, so this is the operator's console

### Component Details

| Component | Primary Role | Integration Points |
| ----------- | ------------- | ------------------- |
| Longhorn | Distributed block storage | • Provides replicated persistent volumes for stateful applications<br>• Manages volume snapshots and backups<br>• Ensures data availability through replication<br>• Enables volume expansion and data integrity checks |
| MinIO | S3-compatible object storage | • Provides S3-compatible storage for applications<br>• Manages bucket policies and user access<br>• Enables object lifecycle management<br>• Exposes metrics for monitoring |
| Garage | Single-node S3-compatible object storage | • Runs as a plain single-replica `Deployment` with `Recreate` strategy, referencing externally-provisioned metadata/data PVCs by claim name<br>• Started with `garage server --single-node`, which assigns and applies its one-time cluster layout in-process before any listener binds, gated by a `startupProbe` on `/health`<br>• Serves opted-in bucket contents anonymously through Garage's website hosting module<br>• Exposes S3, website, and admin APIs through three separate Ingresses (`garage-s3`, `garage-web`, `garage-admin`); the admin Ingress's hostname is `garage.${domain_name}` (its resource name stays `garage-admin` to avoid stranding an orphaned object under `prune: false`), scoped to the `/v2` path only to keep Garage's unauthenticated `/metrics`/`/health`/`/check` off that hostname<br>• The website Ingress carries both an apex and a wildcard host (`garage-web.${domain_name}` and `*.garage-web.${domain_name}`), covered by one `cert-manager` `Certificate`, so any bucket is reachable by name as a subdomain with no per-bucket Ingress or alias<br>• Exposes Prometheus metrics scraped via a `ServiceMonitor`<br>• A `PrometheusRule` alerts on node-down, RPC error rate, block resync errors/queue depth, and low disk space, and separately records recovery-event KPI series (block corruptions, currently-errored blocks)<br>• Ships a Grafana dashboard as a labelled `ConfigMap`, discovered by the Grafana sidecar deployed by observability-core<br>• Bucket/key provisioning is out of this module's scope |
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
   | domain_name | Base domain used to compose every Ingress hostname in this module | MinIO ingress and console ingress, Longhorn UI ingress, Garage S3 API, website, and admin ingresses, Garage's `[s3_web]` root_domain |
   | cert_issuer | `ClusterIssuer` name used to request the Garage website endpoint's TLS certificate | Garage's `garage-web-tls-cert` Certificate (`certificate-web.yaml`) |
   | secret_store | Bitwarden `ClusterSecretStore` name | minio-admin-credentials and garage-credentials ExternalSecrets |
   | minio_admin_username_key | Bitwarden key for the MinIO root username | minio-admin-credentials ExternalSecret |
   | minio_admin_password_key | Bitwarden key for the MinIO root password | minio-admin-credentials ExternalSecret |
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

- **Garage runs as plain Kubernetes resources, with no operator and no CRDs.** A single-replica `Deployment`, a config `ConfigMap`, an `ExternalSecret`-sourced `Secret`, a `Service`, three `Ingress`es (S3 API, website, admin), a `ServiceMonitor`, a `PrometheusRule`, and a dashboard `ConfigMap` are the entire module — nothing reconciles a custom resource, and nothing needs cluster-wide RBAC.
- **A `Deployment`, not a `StatefulSet`.** Nothing in this module depends on stable per-pod network identity: Garage's node identity comes from a key persisted in its metadata volume, not from the pod's hostname, and the RPC address it advertises points at the `Service`, never a per-pod DNS name. That makes this the same single-instance-on-RWO-volumes shape as MinIO, including MinIO's `Recreate` update strategy — Garage's LMDB metadata store does not tolerate two processes writing to the same volume.
- **Metadata and data PVCs are provisioned externally and referenced by claim name**, matching this repo's storage convention (a module never owns a PVC's lifecycle) — the cluster can pre-provision or statically bind either volume instead of the Deployment forcing dynamic provisioning.
- **Garage serves no request until its cluster layout is assigned and applied**, which is imperative and versioned rather than reconciled. This module runs Garage with `garage server --single-node` (added in v2.3.0, the version this module pins), which stages and applies a one-node layout in-process before any listener binds — no separate bootstrap step, no call to Garage's own admin API from outside the process. Capacity is auto-detected from the data volume's total filesystem size and zone is hardcoded by Garage itself to `dc1`; both are inert at one node (100% of partitions land on the only node regardless) but become real placement inputs the moment a second node exists. **`--single-node` hard-errors at startup once the cluster layout version exceeds 1** — it does not skip or no-op against an existing layout past that point — so it must be removed before any deliberate layout change beyond the initial one (a capacity/zone correction, or adding a second node), or that change crashloops the Deployment; see `deployment.yaml`'s own comment on the flag for the exact failure mode.
- **No Garage buckets or keys ship with this module.** Bucket/key provisioning is out of scope here and lives in Terraform instead; the admin API this module exposes (bearer-token authenticated via the `garage-credentials` Secret's `admin-token` key) is what a Terraform provider talks to.
- **The admin API is reachable both in-cluster (the `garage` Service's `admin` port) and from outside the cluster, through a `garage-admin` Ingress at hostname `garage.${domain_name}`** — added so Terraform runs against the Garage workspace no longer need a `kubectl port-forward`. The Ingress resource keeps the name `garage-admin` (this is the module's planned end-state hostname for the admin endpoint; the S3 and website endpoints' own hostnames stay `garage-s3.${domain_name}` and `garage-web.${domain_name}`/`*.garage-web.${domain_name}` for now). That Ingress routes only the `/v2` path prefix, the bearer-token-guarded surface Terraform's garage/terracurl providers actually call. Garage also serves `/health`, `/check`, and `/metrics` on that same port with no authentication at all, by design — `metrics_token` is deliberately unset so this module's own `ServiceMonitor` can scrape `/metrics`, matching MinIO's scrape in this module. Routing only `/v2` keeps those three paths unreachable through the admin hostname (no matching rule, so they 404) without needing a `metrics_token` secret or touching the `ServiceMonitor`. This does not make the admin API internet-reachable — see `ingress-admin.yaml`'s own comment for the exact reachability boundary.
- **`metadata_fsync` is set explicitly to `true`.** Garage defaults this to off, and upstream's own documentation reports LMDB corruption after an unclean shutdown with it off. At `replication_factor = 1` there is no second copy to fall back on, so this is a deliberate durability-over-throughput choice.
- **Garage resolves a website bucket from the Host header via two independent mechanisms, both reachable through this module.** Garage's `[s3_web]` module matches a Host with an extra label beyond `root_domain` as a suffix (`<bucket>.garage-web.${domain_name}` → bucket `<bucket>`), and falls back to looking up the whole Host string as a bucket name/global alias when there is no extra label (i.e. the apex host itself). Unlike MinIO's ingresses, which rely on Traefik's cluster-wide default certificate, the `garage-web` `Ingress` carries its own `cert-manager` `Certificate` spanning both the apex and wildcard host, so every bucket is reachable by name as a subdomain with no per-bucket `Ingress`, alias, or manual step.
- **First issuance of the apex-plus-wildcard `garage-web-tls-cert` Certificate is slow, and if a consuming Kustomization health-checks it, a red status for several minutes is expected during that first issuance — not a fault.** An apex plus a nested wildcard produces two ACME DNS-01 challenges that share one `_acme-challenge.garage-web.${domain_name}` TXT name; cert-manager won't run them concurrently, since they'd collide on that record, so the second challenge doesn't even start until the first reaches `valid`. Each challenge's own DNS self-check backs off between retries, and the first attempt typically fires before the record has propagated, so cert-manager sits `pending` waiting out its own backoff rather than being stuck (observed on this module's own rollout: ~14 minutes end-to-end for both challenges). If you're watching and want it to finish sooner, restarting the cert-manager controller short-circuits that backoff. Do **not** delete the Certificate or its Order to try to unstick it — that forces a fresh failed validation, and Let's Encrypt rate-limits failed validations at 5 per account per hostname per hour, turning a slow issuance into an hour-long block. Renewals are unaffected: the Certificate stays `Ready: True` throughout, and renewal starts 30 days before expiry.
- **Garage runs alongside MinIO, not in place of it.** Both are deployed by this module while Garage is evaluated as MinIO's eventual replacement.
- **Garage's `PrometheusRule` only covers conditions meaningful at `replication_factor = 1` / one node.** Half of the alert set this module was evaluated against (quorum health, peer connectivity, storage-node and partition consistency across replicas) is deliberately omitted: at a single node those conditions are trivially satisfied whenever the process is up, so keeping them would just repeat the node-down alert under different names, not add signal. `PrometheusRule` defines queryable alert state only — this estate has no AlertManager routing configured, so nothing pages or notifies on these.
- **The Garage dashboard is a console replacement, not a decoration.** Garage ships no admin UI, so Grafana is the only place bucket-store health, capacity and reclamation are visible without shelling into a pod. It is shipped from this module rather than from observability-core so that a cluster which does not deploy Garage never inherits a dashboard with nothing behind it. The coupling is one-way and soft: the `ConfigMap` is inert unless a Grafana dashboard sidecar is watching for its label, and nothing in this module fails if one is not.
- **Two things an operator will look for are not in Garage's metric surface, and the dashboard says so rather than approximating them silently.** Garage v2.3.0 publishes no per-bucket or per-key dimension on any metric, so usage cannot be split by consumer — separating Loki's footprint from Authentik's requires the admin API (`GetBucketInfo`), not Prometheus. It also publishes no live-bytes total, which is the denominator a true consumed-vs-live amplification ratio needs; the dashboard substitutes bytes-per-object and bytes-per-referenced-block, labels both as proxies, and states what they cannot distinguish.
- **Most of Garage's counters do not exist until they first increment.** Its OpenTelemetry counters and histograms — every `api_s3_*`, the block I/O and corruption counters, the RPC error counters — are absent from a healthy node's `/metrics` entirely rather than present and zero, while its observable gauges (`table_*`, `block_rc_size`, `garage_local_disk_*`, `cluster_*`) are always emitted. This is why any expression combining them coalesces each term with `or vector(0)`: in PromQL an empty vector added to anything yields an empty vector, so an uncoalesced sum of absent counters renders nothing at all and cannot be told apart from zero.
- **The dashboard coalesces empty panels selectively, and the distinction is deliberate.** Grafana cannot render custom empty-state text when a query returns no series at all — `noValue` is only honoured for series that exist but contain nulls — so an unemitted metric looks exactly like a broken panel. Where zero is the truthful reading (a counter that has never incremented: S3 requests, S3 errors, block corruptions) the query coalesces to an explicit zero line, guarded by `and on() absent(...)` so the placeholder disappears by itself the moment the real series appears. Where zero would be a false claim it is **not** coalesced: disk consumed drawn at 0 would assert the engine is storing nothing (kubelet emits volume stats only for a PVC a running pod has mounted, so that series is genuinely absent until the engine runs), and `0/0` ratios like versions-per-object or bytes-per-object with no objects are undefined, not zero. Those panels stay empty, and each one's description says which of the two it is — the only place a reader can see it.
- **`object-store-disk-amplification` (module root) and `object-store-recovery-events` (`garage/prometheusrule-garage.yaml`) are permanent, not scoped to the MinIO→Garage trial that motivated them (homelab-ops-kubernetes-apps#3611).** They were built for that trial's 30-day decision window but outlive it deliberately: raw disk consumed per engine (`object_store:disk_used_bytes{engine="minio"|"garage"}`, each a `sum(kubelet_volume_stats_used_bytes)` over that engine's own namespace) is the measurement whose *absence* let MinIO silently accumulate 3.25M delete markers, and the unreclaimed noncurrent versions standing behind them, over months before anyone noticed — deleting this rule at trial end would recreate the blind spot the migration exists to fix. The recovery-event rules (`object_store:recovery_block_corruptions_total`, `object_store:recovery_blocks_currently_errored`) are the durability signal for a single-replica object store generally, with no second copy to fall back on — not a trial-only concern either. Both are recording rules over series this module already scrapes (kubelet's volume-stats collector, Garage's `ServiceMonitor`), so keeping them costs no exporter, no CronJob, and no new scrape target. Contrast the CronJob that ran the trial's third KPI (byte-for-byte LogQL query correctness against Loki): that one *is* trial-scoped — its job is proving a storage-backend change didn't alter query results, a question that stops being live once cutover is proven — and lives in the clusters repo instead, retired by deleting a directory rather than by a module release.
- **The disk KPI is raw bytes per engine, not an amplification ratio — the ratio that shipped first was removed rather than repaired.** It was wrong in a way that read as verified: it divided PVC used bytes by `minio_cluster_usage_total_bytes`, justified as "live bytes" because that metric excludes delete markers. Delete markers are zero-byte placeholders, so excluding them subtracts nothing; the bytes that made the denominator wrong are the **noncurrent versions** those markers stand in front of, which the crawler counts in full. Keep the two apart — the denominator was version-inclusive, not live, so it already contained most of the accumulation it was supposed to be measured against, and the "confirmed against production at ~3.22×, matching the 3.2× figure in #3611" note it carried was not a verification: both numbers come from that same denominator and agreed because they shared the defect (against genuinely live bytes, MinIO's amplification is nearer 55×). It was also only ever half a KPI: verified live against this module's own Garage deployment (production, 2026-08-13), Garage's `/metrics` exposes no bucket/object byte-total series at all, only `garage_local_disk_*` — so no live-bytes denominator exists on that side and the ratio is not computable for Garage, now or after cutover. `kubelet_volume_stats_used_bytes` is symmetric instead: already scraped identically for both engines, needing no exporter and no cooperation from the engine being measured, and a *filesystem-level* fact — so Longhorn's block-level behaviour underneath, including its weekly `fstrim`, changes how much of the backing volume is reclaimed but does not enter this number. Both series select by namespace rather than by claim name, because neither claim name is a module fact (MinIO's comes from the consuming cluster's `persistence.existingClaim` patch, Garage's from `${garage_metadata_claim}`/`${garage_data_claim}`) and because summing per namespace counts each engine's whole footprint — MinIO keeps data and metadata on one volume, Garage splits them across two. **Read it as a trend across the trial, never as a single reading**: MinIO's figure is months of accumulation while Garage's on day one is a fresh copy of the retained window, so any post-cutover snapshot flatters Garage for free. One lifetime caveat comes with it — the `PrometheusRule` lives in the `minio` namespace, which #3644 deletes at decommission, taking the `engine="garage"` series with it; relocating it is a deliberate change that must also delete the original by hand, since Flux prune is disabled cluster-wide and a move strands rather than relocates.
- **The recovery-event rules gate through an explicit `object_store:garage_up` rather than this module's usual `or vector(0)` convention for Garage's lazily-emitted counters.** `or vector(0)` (see `GarageHighRPCErrorRate`'s comment) is the right call for a dashboard panel a human reads next to other liveness context, but wrong for a KPI whose pass bar is "zero over 30 days": unconditionally coalescing to `0` would make "Garage was never deployed" and "Garage ran healthy the whole trial" render identically, so a gap in collection could pass the KPI on a metric that was never measured. `object_store:garage_up` (`max(up{job="garage"})`, recorded first in its rule group so the later rules can reference it) keeps those states apart — genuinely absent while Garage isn't scraped, an explicit `0` while it is and healthy. Verified live (production, 2026-08-13) which of Garage's counters this actually matters for: `block_corruption_counter` is absent entirely from a healthy node's `/metrics` — not present-and-zero — while the gauge `block_resync_errored_blocks` is always emitted. `block_resync_error_counter` (attempt failures, including ordinary transient retries) was deliberately left out of both rules as a noisier proxy than confirmed corruption or an unresolved backlog for a KPI whose bar is "zero".
