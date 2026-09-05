# Storage Core

Provides storage capabilities for the cluster through distributed block storage, object storage, and network filesystem support.

## Quick Links

<a href="https://garagehq.deuxfleurs.fr/" target="_blank"><img src="../../../.static/images/logos/garage.svg" width="32" height="32" alt="Garage"></a> <a href="https://longhorn.io/" target="_blank"><img src="../../../.static/images/logos/longhorn.svg" width="32" height="32" alt="Longhorn"></a> <a href="https://min.io/" target="_blank"><img src="../../../.static/images/logos/minio.svg" width="32" height="32" alt="MinIO"></a> <a href="https://github.com/kubernetes-csi/csi-driver-nfs" target="_blank"><img src="../../../.static/images/logos/nfs-csi-driver.png" width="32" height="32" alt="NFS CSI Driver"></a> <a href="https://www.versity.com/products/versitygw/" target="_blank"><img src="../../../.static/images/logos/versitygw.svg" width="32" height="32" alt="VersityGW"></a>

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

5. Backup Object Storage (VersityGW)
   - An S3 API served directly over a plain POSIX tree: one object is one ordinary file, the key is its path beneath the bucket directory unencoded and 1:1, and per-object metadata lives in `user.*` extended attributes on the inode -- so the stored form is readable by anything that can read a filesystem, with no index to lose
   - S3 API, WebUI, and admin API on three separate listeners, each behind its own Ingress hostname, so the endpoint the backup producers use carries no account-management surface
   - Only the gateway's own root credential is owned here; consumer accounts and bucket ownership have no declarative representation and are converged outside the module, because which accounts and buckets exist is a cluster fact rather than a property of the gateway
   - A startup gate that refuses to serve over a tree it cannot write extended attributes to, and a scheduled sweep that reclaims the multipart residue no S3 API can reach
   - Prometheus metrics from two producers deployed alongside, since the gateway itself publishes only UDP counters: a StatsD translator for the traffic it serves, and a read-only inventory exporter for what the store actually holds

### Component Details

| Component | Primary Role | Integration Points |
| ----------- | ------------- | ------------------- |
| Longhorn | Distributed block storage | • Provides replicated persistent volumes for stateful applications<br>• Manages volume snapshots and backups<br>• Ensures data availability through replication<br>• Enables volume expansion and data integrity checks |
| MinIO | S3-compatible object storage | • Provides S3-compatible storage for applications<br>• Manages bucket policies and user access<br>• Enables object lifecycle management<br>• Exposes metrics for monitoring |
| Garage | Single-node S3-compatible object storage | • Runs as a plain single-replica `Deployment` with `Recreate` strategy, referencing externally-provisioned metadata/data PVCs by claim name<br>• Started with `garage server --single-node`, which assigns and applies its one-time cluster layout in-process before any listener binds, gated by a `startupProbe` on `/health`<br>• Serves opted-in bucket contents anonymously through Garage's website hosting module<br>• Exposes S3, website, and admin APIs through three separate Ingresses (`garage-s3`, `garage-web`, `garage-admin`); the admin Ingress's hostname is `garage.${domain_name}` (its resource name stays `garage-admin` to avoid stranding an orphaned object under `prune: false`), scoped to the `/v2` path only to keep Garage's unauthenticated `/metrics`/`/health`/`/check` off that hostname<br>• The website Ingress carries both an apex and a wildcard host (`garage-web.${domain_name}` and `*.garage-web.${domain_name}`), covered by one `cert-manager` `Certificate`, so any bucket is reachable by name as a subdomain with no per-bucket Ingress or alias<br>• Exposes Prometheus metrics scraped via a `ServiceMonitor`<br>• A `PrometheusRule` alerts on node-down, RPC error rate, block resync errors/queue depth, and low disk space, and separately records recovery-event KPI series (block corruptions, currently-errored blocks)<br>• Ships a Grafana dashboard as a labelled `ConfigMap`, discovered by the Grafana sidecar deployed by observability-core<br>• Bucket/key provisioning is out of this module's scope |
| CSI Driver NFS | External NFS share integration | • Enables using external NFS shares as persistent volumes<br>• Supports dynamic volume provisioning from NFS shares<br>• Manages mount options and access modes<br>• Integrates with Kubernetes storage classes |
| VersityGW | S3 gateway over a POSIX filesystem | • Deployed from the upstream chart via an `OCIRepository` + `HelmRelease`, over a PVC this module references by claim name and never provisions<br>• Serves S3, the WebUI, and the admin API on three listeners behind three Ingresses (`versitygw-s3`, `versitygw`, `versitygw-admin`); setting the admin port is what keeps account-management routes off the listener the backup producers use<br>• Backend data and file-backed IAM are separate subpaths of one volume, so the IAM store is not inside the gateway root and `users.json` is not reachable as an object -- asserted both by a postRenderer tripwire and by the module's test suite<br>• An init container writes, reads back and removes an extended attribute before the gateway starts, so a tree that cannot hold per-object metadata holds the pod in `Init` instead of being served over<br>• A six-hourly `CronJob` -- the only one this component ships -- reclaims aged multipart residue, including the two forms invisible to every S3 API<br>• Holds a single `ExternalSecret` for the gateway's root credential; consumer accounts and bucket ownership are provisioned outside the module<br>• A `statsd_exporter` `Deployment` and `Service` translate the gateway's UDP counters into a scrapeable endpoint; no `ServiceMonitor` ships here<br>• A second `Deployment` and `Service` walk the object tree read-only on a timer and export per-bucket object counts, bytes stored, and both residue forms the sweep reclaims -- staged `.sgwtmp` parts, and overwrite-race files beside their objects -- with the walk's completion timestamp beside them<br>• Reachable only at this module's component path -- it is deliberately absent from the module-root `kustomization.yaml` |

## Prerequisites

1. Required Secrets

   | Secret Name             | Purpose                                                             | Required Keys                        |
   | ----------------------- | ------------------------------------------------------------------- | ------------------------------------ |
   | minio-admin-credentials | MinIO administrator access                                          | rootUser, rootPassword               |
   | garage-credentials      | Garage admin API token and inter-node RPC shared secret             | admin-token, rpc-secret              |
   | versitygw-credentials   | VersityGW's root S3 credential -- the only account this module owns | rootAccessKeyId, rootSecretAccessKey |

2. Required Variables

   | Variable | Purpose | Required By |
   | ---------- | --------- | ------------- |
   | domain_name | Base domain used to compose every Ingress hostname in this module | MinIO ingress and console ingress, Longhorn UI ingress, Garage S3 API, website, and admin ingresses, Garage's `[s3_web]` root_domain, VersityGW's S3/WebUI/admin ingresses and the WebUI's CORS origin and gateway URLs |
   | cert_issuer | `ClusterIssuer` name used to request the Garage website endpoint's TLS certificate | Garage's `garage-web-tls-cert` Certificate (`certificate-web.yaml`) |
   | secret_store | Bitwarden `ClusterSecretStore` name | minio-admin-credentials, garage-credentials and versitygw-credentials ExternalSecrets |
   | minio_admin_username_key | Bitwarden key for the MinIO root username | minio-admin-credentials ExternalSecret |
   | minio_admin_password_key | Bitwarden key for the MinIO root password | minio-admin-credentials ExternalSecret |
   | garage_admin_token_key | Bitwarden key for the Garage admin API token | garage-credentials ExternalSecret |
   | garage_rpc_secret_key | Bitwarden key for the inter-node RPC shared secret | garage-credentials ExternalSecret |
   | garage_metadata_claim | Name of the pre-provisioned PVC to use for Garage's metadata volume | Garage Deployment |
   | garage_data_claim | Name of the pre-provisioned PVC to use for Garage's data volume | Garage Deployment |
   | garage_s3_region | AWS-style region Garage signs/validates S3 requests against; must match every S3 client's own configured region (e.g. `loki_s3_region` at Loki's eventual cutover) | Garage `[s3_api]` config |
   | versitygw_s3_region | Region VersityGW validates SigV4 credential scopes against; a client whose configured region differs is rejected outright | VersityGW HelmRelease values (`gateway.region`) |
   | versitygw_data_claim | Name of the pre-provisioned PVC holding the object tree | VersityGW HelmRelease values, sweep CronJob, inventory exporter Deployment |
   | versitygw_root_accesskey_key | Bitwarden key for VersityGW's root access key | versitygw-credentials ExternalSecret |
   | versitygw_root_secretkey_key | Bitwarden key for VersityGW's root secret key | versitygw-credentials ExternalSecret |

3. Storage Requirements

   | PVC (by claim name) | Purpose | Access Mode |
   | ---------------------- | --------- | ------------- |
   | ${garage_metadata_claim} | Garage's metadata volume (its LMDB database) | Provisioned externally by the cluster; not defined by this module |
   | ${garage_data_claim} | Garage's object data volume | Provisioned externally by the cluster; not defined by this module |
   | ${versitygw_data_claim} | VersityGW's object tree, plus its file-backed IAM store as a sibling subpath | Provisioned externally by the cluster; not defined by this module. **Must carry a store-identity sentinel — see below** |

4. Filesystem Preparation (VersityGW)

   VersityGW's volume is the one prerequisite in this module that is not satisfied by supplying a
   Kubernetes object. Before the gateway is deployed for the first time, the prepared filesystem must
   carry a `.versitygw-store-identity` file at the **volume root** — a sibling of the `data` and `iam`
   subpaths, never inside either, because anything at the top of the gateway root is served as a
   bucket.

   | Requirement | Detail |
   | ------------- | -------- |
   | Path | `.versitygw-store-identity`, at the root of the volume |
   | Written by | The operator, once, as part of preparing the filesystem — alongside `mkfs`, before the gateway first runs |
   | Contents | `key=value` lines, one per line, no quoting. A `store_id` of exactly 32 lowercase hex characters is **required**; a sentinel without one is rejected, because it says a store was prepared without saying which |
   | Never written by | The gateway, the module, or any check in it |

   The `data/` and `iam/` subdirectories are not part of what must be prepared by hand: the kubelet
   creates a missing subPath directory at mount, and it lands group-owned by the pod's `fsGroup`
   because `fsGroup` leaves the setgid bit on the volume root. That inheritance is the whole reason
   the gateway can write into directories nothing explicitly chowned — and it is why the root's
   ownership matters more than it looks. Under `fsGroupChangePolicy: OnRootMismatch` the kubelet
   inspects only the volume root and skips the recursive pass when it already matches, so **a
   successful mount is not evidence that the ownership pass ran.** Restore the tree from a clone
   whose root ownership differs and the first mount walks and chowns every object on the volume —
   precisely the startup `OnRootMismatch` was chosen to avoid. What catches a tree the gateway
   cannot write is not the mount but the write-check init container, which fails the pod at `Init`
   rather than letting it serve reads and fail at the first write.

   `store_id` identifies the **tree**, not the device, and that distinction is the whole point of it.
   Generated once when the store is prepared and never regenerated, it is carried unchanged by a
   volume-level clone — so it still answers "is this the store I am recovering" on the recovery path
   that goes through one. A device identifier in its place would be guaranteed to mismatch on every
   legitimate clone, i.e. go red during the one operation the check exists to protect, which is how a
   check teaches an operator to bypass it. Whether a volume is the original LUN or a copy of it is a
   different question, answered against the identifier the operator's runbook recorded.

   The gateway asserts that a well-formed `store_id` is present and prints it on every start; it does
   not compare it to an expected value. Which store this cluster should be mounting is a cluster fact
   and not the module's, and the comparison belongs to the operator holding the runbook.

   **The gateway refuses to start without it**, and that refusal reads two ways. On a **new store** it
   means the preparation step has not been done yet — do it, and the pod proceeds. On a store that was
   **already serving** it means the volume presented is not that store, and the file must not be
   created. The two are indistinguishable from disk, which is why the sentinel exists at all and why
   nothing automates it: a check that created what it verifies would accept every blank volume
   thereafter, silently and permanently.

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

- **VersityGW is reachable only at its own component path, and is deliberately absent from the module-root `kustomization.yaml`.** A cluster consuming this module at its root builds everything in that list, so adding a component with new required post-build variables there puts them into a reconciliation shared with Longhorn, MinIO and Garage — the failure this module has already taken twice (see the `cert_issuer` note in `CHANGELOG.md` 0.6.0). A cluster that wants VersityGW declares a second Flux `Kustomization` pointing at `storage-core/versitygw`, the way the single-component consumers of this module already do. The consequence to know: anything VersityGW needs must live inside that directory, including its own namespace, which is why its `namespace.yaml` is there rather than in the module root with the others.
- **The backend root and the file-backed IAM store are separate subpaths of one volume, and that is a security boundary rather than a layout preference.** The gateway serves `/mnt/data` (the volume's `data/` subpath) and keeps accounts in `/mnt/iam` (its `iam/` subpath), so IAM is a sibling of the object namespace rather than inside it. Put an IAM directory *inside* the gateway root and it is enumerated as a bucket, and `users.json` — which holds every account secret in cleartext — becomes readable as an ordinary S3 object by the root account. That was confirmed in both directions against a live gateway. Two independent guards hold the arrangement in place: a `postRenderers` JSON6902 `test` operation that fails the build if the two mount subpaths ever stop being what they are, and a suite assertion that root's `ListBuckets` returns exactly the provisioned buckets and nothing else.
- **Two `postRenderers` patches sit on top of the chart, and they are the whole of what the chart's values cannot express.** One is assertion-only — it changes nothing and exists to turn a silent drift in the chart's pod template into a red `Kustomization`. The other is a strategic-merge patch adding a liveness probe (the chart renders none at any version) and the startup extended-attribute check (the chart has no hook for extra containers). Strategic merge was chosen over JSON6902 for the mutating patch specifically because it keys containers, init containers and volumes by name: a future chart-supplied entry is merged alongside rather than silently replaced.
- **The gateway's readiness probe cannot mean what it appears to.** The chart wires readiness to the gateway's health endpoint and does not make it overridable — and that endpoint is a constant `200` that consults no backend, no mount, and no filesystem. It stays green through an unmounted volume, a read-only remount and a full disk. What actually gates serving is the init container, which creates a file in the gateway root, writes an extended attribute, reads it back, compares it and removes it, failing the pod on anything else. The gateway's own startup check refuses to start on a filesystem with no extended-attribute support at all, but a read-only mount passes it: the process starts clean, serves reads, and fails only at the first write. That gap is what the init container exists to close, and the test suite proves it can go red rather than only that it passes.
- **Accounts and bucket ownership can be converged but not declared, which is why neither ships here.** Bucket ownership has no file representation anywhere — it is the `Owner` field inside the `user.acl` extended attribute on the bucket directory, and the running gateway's admin API is the only thing that writes it. A `role: user` account cannot create buckets at all, so buckets must be pre-provisioned with an owner before any consumer can use them. Which accounts and buckets exist is a cluster fact rather than a property of the gateway, so convergence is driven against the admin API from outside the module; the module owns only the root credential that convergence authenticates as. The gotcha for whatever drives it: `change-bucket-owner` discards the bucket's existing ACL and policy, so it must be issued only when the observed owner actually differs. That distinction is invisible from outside — a converger that reassigns on every run leaves the same owner and the same green result — so the test suite drives a second run and asserts it reports the ownership already correct.
- **Interrupted multipart uploads leave residue that no S3 API can see or reclaim, which is why a sweep ships with the deployment rather than being left to operations.** Three forms exist. An abandoned upload is visible to `ListMultipartUploads` and reclaimable through `AbortMultipartUpload`. An assembly interrupted by a crash leaves a renamed `.inprogress` directory that is invisible to every listing, that `AbortMultipartUpload` answers `NoSuchUpload` for, and that nothing upstream ever collects — observed stranding gigabytes. An overwrite interrupted between its link and its rename leaves a full-size file in the object's *own* directory, outside the hidden `.sgwtmp` prefix, so it is returned by `ListObjectsV2` as an ordinary key. Nothing on disk marks residue as such, so age is the only discriminator — and the clock it reads is not the intuitive one. An upload directory's modification time is set by the last part written and never moves again: the rename that claims the assembly slot leaves it alone, and the assembly only reads the part files. So the threshold has to clear the *sum* of the client's gap between its last part and its completion request and the assembly's own duration, not the assembly duration alone. That distinction is the one a later reader would get wrong while tuning the threshold down. The sweep must run as the same uid as the gateway: the directories are `0755` and owned by it, unlinking needs write on the parent, and a shared `fsGroup` grants traverse but not unlink — so a mismatched uid produces a sweep that finds everything and removes nothing.
- **The gateway refuses to start over a volume that does not carry a store-identity sentinel, and this is deliberately not self-healing.** The in-tree iSCSI plugin identifies its device by portal, IQN and LUN index and by nothing else, then formats it if no filesystem is found — silently, with no Kubernetes event. So a blank device re-presented at the same address yields a bound volume, a running gateway, green reconciliation, and a store serving zero objects. A prepared store always carries a `.versitygw-store-identity` file at the volume root, so its absence is proof rather than suspicion. Three properties are load-bearing: the check **never creates** the file (creating it is exactly how a reformatted volume would be accepted), it reads the **volume root** rather than the gateway root (a file at the top of the gateway root would be enumerated as a bucket and be deletable over S3 by the root credential), and **deleting the sentinel stops the store from starting** — which is the right side of the trade here, but means it must not be removed while debugging a start-up failure. What it does not prove is currency: a stale but populated clone carries a valid sentinel and passes. Identity is asserted from the tree rather than from the device precisely because the sanctioned recovery path mounts a *clone*, whose device identity is expected to differ.
- **Pods sharing the object volume are held to one node by pod affinity, in two deliberately different ways.** The volume is `ReadWriteOnce` and the topology puts more than one pod over it — the gateway read-write and, in a later project, an off-site replication pod read-only — so they must land on the same node. A single-node cluster satisfies that by accident; stating it means the constraint still holds when the cluster grows, and fails at scheduling rather than at attach. The **long-running peers** — the gateway, and later an off-site replication pod — carry `versitygw.storage/shares-object-volume` and an affinity matching it: symmetric, so it binds whichever schedules second, and self-satisfying for a lone pod, so it is inert until that second pod exists. The sweep `CronJob` deliberately does **not** carry that label; it targets the gateway's own identity instead, because a symmetric rule would let a sweep with no gateway schedule anywhere, and a sweep with nothing to reclaim against should stay `Pending` rather than start where the volume is not.
- **`fsGroupChangePolicy` is set to `OnRootMismatch`, and at this volume's size that is not a tuning detail.** The default walks and chowns every file on the volume at every mount; on a store holding hundreds of thousands of backup objects that is a startup that does not finish. Every pod mounting this volume must declare the *same* `fsGroup` for the same reason — two different values make each mount look like a mismatch to the other, and each would then re-walk the whole tree on every start.
- **No `ServiceMonitor` or `PrometheusRule` ships with VersityGW, deliberately.** The gateway publishes no Prometheus endpoint at all — its entire metric surface is six counters emitted as UDP StatsD datapoints — so a `statsd_exporter` is deployed alongside to translate them, and that translator's `Service` -- together with the inventory exporter's -- is the seam a collector attaches to. How this cluster gets scraped is decided elsewhere; inventing a scrape configuration here would be guessing at it. Note what the counters cannot tell you either way: the transport is UDP and the gateway drops datapoints silently when its buffer fills, so a zero is equally consistent with "idle" and "the path is broken" — only a counter that was driven and is expected to be non-zero detects its own failure.
- **The WebUI holds no credential; the browser does.** It is a static page embedded in the gateway binary with no login of its own and no server-side session: the user types an S3 key into a form, it is kept in the browser's `sessionStorage` in cleartext for the life of the tab, and every request is signed client-side and sent directly to the S3 and admin APIs. Its management pages require an admin-role or root key, and with one the UI can delete any object or bucket in the store. This module ships only the gateway's root credential; the admin-role account the WebUI is meant to be driven with is a cluster fact, provisioned outside the module, and exists so that the *root* key — the identity the recovery path depends on — never has to be typed into a browser. Putting SSO in front of the WebUI Ingress (via `components/sso`) gates who reaches the login form and nothing more; the admin and S3 Ingresses are deliberately excluded, the first because the browser's cross-origin calls carry no forward-auth session and would all fail, the second because its clients authenticate with SigV4 and cannot follow a redirect to a login page.
- **The store's contents are exported by a walk, because nothing else can produce them.** The gateway's counters describe traffic, not holdings, and free space reads identically for a store that is empty because it is new and one that is empty because the volume beneath it was reformatted — which the in-tree iSCSI plugin does silently. A resident exporter therefore walks the gateway root read-only and publishes per-bucket object counts and byte totals, with the walk's completion timestamp beside them. Four properties are load-bearing. It mounts the **volume root read-only** and walks the `data` subdirectory rather than mounting `subPath: data`, because the kubelet *creates* a missing `subPath` — so an absent gateway root makes it refuse to start rather than manufacture one and report a store with nothing in it. It declares **no `fsGroup`**, since it only reads and the tree already carries the uid it runs as; adding one re-opens the mismatch hazard in the note above. Its interval is a **floor rather than a schedule** — the walk sleeps after finishing, so a walk slower than the interval degrades cadence instead of stacking load, and a rollout restart forces one immediately. A walk that *raises* does not wait out that interval: one unreadable directory unwinds the whole pass, and at a daily cadence sleeping it off would cost a day of currency, so failures retry on a doubling backoff that settles back to the interval. And its script is generated into its own **content-hashed** `ConfigMap`, unlike the shared one, because it is the only consumer here that reads its script once and holds it. The walk also splits residue the way the sweep does, and the coupling is deliberate: the overwrite-race predicate in `store-inventory.py` is `sweep.sh`'s own, character-for-character, so the two never disagree about what the shape of residue is. What the exporter does *not* share is the sweep's age guard: the classification is age-blind where the sweep reclaims only past its age threshold, so a write in flight legitimately appears in the residue series until it either completes or ages into the sweep's reach. The series is a superset of what the next sweep would reclaim, not a reading of sweep health -- at a daily walk against a six-hourly sweep, a single sample supports no conclusion about the sweep at all; only a level held across successive walks does. Those files are counted in **both** the object totals and the overwrite-residue totals -- they are S3-visible as ordinary keys, so excluding them would break the exported-count-equals-`ListObjectsV2` property, while excluding them from residue is how unreclaimable bytes accumulate with the object count rising and residue flat, both reading reassuring.
- **Two things to know before writing a query against those series.** A per-bucket check of the form `versitygw_store_objects{bucket="x"} < N` returns an *empty* result when that bucket is deleted outright, which reads as "nothing wrong" — the form that fires is `(… or vector(0)) < N`. And an object count of zero is equally consistent with an emptied store and a dead exporter, so it is only interpretable alongside `versitygw_store_last_scan_timestamp_seconds`, which is why that series is exported.
- **The gateway never calls `fsync`.** An acknowledged write becomes durable at the next filesystem journal commit, not at acknowledgement, so a crash inside that window loses a completed, acknowledged object. Nothing in this module closes that window — narrowing it is a mount-option and power-protection concern belonging to the cluster that provides the volume.
- **Garage runs as plain Kubernetes resources, with no operator and no CRDs.** A single-replica `Deployment`, a config `ConfigMap`, an `ExternalSecret`-sourced `Secret`, a `Service`, three `Ingress`es (S3 API, website, admin), a `ServiceMonitor`, a `PrometheusRule`, and a dashboard `ConfigMap` are the entire module — nothing reconciles a custom resource, and nothing needs cluster-wide RBAC.
- **A `Deployment`, not a `StatefulSet`.** Nothing in this module depends on stable per-pod network identity: Garage's node identity comes from a key persisted in its metadata volume, not from the pod's hostname, and the RPC address it advertises points at the `Service`, never a per-pod DNS name. That makes this the same single-instance-on-RWO-volumes shape as MinIO, including MinIO's `Recreate` update strategy — Garage's LMDB metadata store does not tolerate two processes writing to the same volume.
- **Metadata and data PVCs are provisioned externally and referenced by claim name**, matching this repo's storage convention (a module never owns a PVC's lifecycle) — the cluster can pre-provision or statically bind either volume instead of the Deployment forcing dynamic provisioning.
- **Garage serves no request until its cluster layout is assigned and applied**, which is imperative and versioned rather than reconciled. This module runs Garage with `garage server --single-node` (added in v2.3.0), which stages and applies a one-node layout in-process before any listener binds — no separate bootstrap step, no call to Garage's own admin API from outside the process. Capacity is auto-detected from the data volume's total filesystem size and zone is hardcoded by Garage itself to `dc1`; both are inert at one node (100% of partitions land on the only node regardless) but become real placement inputs the moment a second node exists. **`--single-node` hard-errors at startup once the cluster layout version exceeds 1** — it does not skip or no-op against an existing layout past that point — so it must be removed before any deliberate layout change beyond the initial one (a capacity/zone correction, or adding a second node), or that change crashloops the Deployment; see `deployment.yaml`'s own comment on the flag for the exact failure mode.
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
- **The disk KPI is raw bytes per engine, not an amplification ratio — the ratio that shipped first was removed rather than repaired.** Not because it was wrong — a complete read-only traversal of MinIO's largest bucket on the trial cluster (2026-08-18) found 15.42 GB live across 209,406 objects against 46.22 GB of PVC disk (~3.0×), and that bucket's `minio_bucket_usage_total_bytes` read 15.34 GB over the same population, so `minio_cluster_usage_total_bytes` does track live bytes and the ~3.22× the rule recorded was right. Its agreement with the 3.2× figure in #3611 was never an *independent* check — both are computed the same way from the same denominator — but they agreed because both were right, not because they shared a defect. The amplification is real, and it is a **disk** fact rather than a denominator one: a plain `Expiration` rule on a versioned bucket writes a zero-byte delete marker instead of removing an entry, and the **noncurrent versions** those markers stand in front of are never reclaimed. Excluding delete markers from a byte total changes nothing, precisely because they carry no bytes. It was, however, only ever half a KPI: verified live against this module's own Garage deployment (production, 2026-08-13), Garage's `/metrics` exposes no bucket/object byte-total series at all, only `garage_local_disk_*` — so no live-bytes denominator exists on that side and the ratio is not computable for Garage, now or after cutover. A number that can be produced for only one arm of a two-arm comparison cannot decide it. `kubelet_volume_stats_used_bytes` is symmetric instead: already scraped identically for both engines, needing no exporter and no cooperation from the engine being measured, and a *filesystem-level* fact — so Longhorn's block-level behaviour underneath, including its weekly `fstrim`, changes how much of the backing volume is reclaimed but does not enter this number. Both series select by namespace rather than by claim name, because neither claim name is a module fact (MinIO's comes from the consuming cluster's `persistence.existingClaim` patch, Garage's from `${garage_metadata_claim}`/`${garage_data_claim}`) and because summing per namespace counts each engine's whole footprint — MinIO keeps data and metadata on one volume, Garage splits them across two. **Read it as a trend across the trial, never as a single reading**: MinIO's figure is months of accumulation while Garage's on day one is a fresh copy of the retained window, so any post-cutover snapshot flatters Garage for free. One lifetime caveat comes with it — the `PrometheusRule` lives in the `minio` namespace, which #3644 deletes at decommission, taking the `engine="garage"` series with it; relocating it is a deliberate change that must also delete the original by hand, since Flux prune is disabled cluster-wide and a move strands rather than relocates.
- **The recovery-event rules gate through an explicit `object_store:garage_up` rather than this module's usual `or vector(0)` convention for Garage's lazily-emitted counters.** `or vector(0)` (see `GarageHighRPCErrorRate`'s comment) is the right call for a dashboard panel a human reads next to other liveness context, but wrong for a KPI whose pass bar is "zero over 30 days": unconditionally coalescing to `0` would make "Garage was never deployed" and "Garage ran healthy the whole trial" render identically, so a gap in collection could pass the KPI on a metric that was never measured. `object_store:garage_up` (`max(up{job="garage"})`, recorded first in its rule group so the later rules can reference it) keeps those states apart — genuinely absent while Garage isn't scraped, an explicit `0` while it is and healthy. Verified live (production, 2026-08-13) which of Garage's counters this actually matters for: `block_corruption_counter` is absent entirely from a healthy node's `/metrics` — not present-and-zero — while the gauge `block_resync_errored_blocks` is always emitted. `block_resync_error_counter` (attempt failures, including ordinary transient retries) was deliberately left out of both rules as a noisier proxy than confirmed corruption or an unresolved backlog for a KPI whose bar is "zero".
