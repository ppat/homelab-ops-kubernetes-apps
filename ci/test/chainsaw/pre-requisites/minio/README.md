# `minio` fixture

MinIO as an S3 endpoint, for a suite whose module under test needs object storage — Loki's chunk store,
CloudNativePG's backup target.

Shared conventions (naming, namespaces, post-build variables, waiting, `retryInterval`) are in
[../README.md](../README.md). Only what is specific to this fixture is below.

## Provides

- `HelmRepository/minio-repository` (`flux-system`)
- `HelmRelease/minio-release` (`minio`) — a single standalone MinIO with a 1Gi PVC
- `Secret/minio-admin-credentials` (`minio`) — a plain Secret, see below
- `Namespace/minio`, supplied by this fixture

It needs no `ClusterSecretStore` and no external-secrets. This fixture composes with nothing.

## Removed, and why

| removed | reason |
| --- | --- |
| `ExternalSecret/minio-admin-credentials` | replaced by a plain `Secret` of the same name |
| `Probe/minio-bucket`, `Probe/minio-resource` | storage-core's own Prometheus scrape configuration for MinIO |
| `persistence.size` 500Gi → 1Gi | the chart default; nothing here stores more than a few objects |

The admin-credential swap is the substantive one and its reasoning is written out in full in
`minio-admin-credentials.yaml`, including the four-run measurement behind it and the misreading of that
measurement that had to be corrected. Short version: MinIO's install was gated on external-secrets becoming
ready (measured T0+117s), so MinIO could not finish before T0+188s and everything waiting on MinIO inherited
both. Taking the credential directly narrows the MinIO wait from `2s / 100s` to `2s / 2s` — a quarter of the
spread — and lets a suite use object storage without standing up external-secrets at all.

## What a consumer would lose

- A suite that wants to test **MinIO resolving its own admin credential through external-secrets** must not
  use this fixture. That is storage-core's behaviour and `infra-storage` exercises it properly, with the
  `ExternalSecret` kept, because there MinIO is the subject rather than scaffolding. A consuming suite's own
  `ExternalSecret` objects are untouched and still resolve through its fake `ClusterSecretStore`.
- A suite that wants MinIO's blackbox-style `Probe` targets scraped gets nothing; re-add them in the suite.
- A suite storing more than ~1Gi must patch `persistence.size` back up.

## Consumer must supply

- `infrastructure/bootstrap/crds/`, for `monitoring.coreos.com` (the chart creates a `ServiceMonitor`) and
  for `external-secrets.io` if the suite has `ExternalSecret` objects of its own. Every suite already
  includes it.
- **Buckets, users and policies.** The `HelmRelease` reads them from a `ConfigMap/minio-extra-config` in the
  `minio` namespace via `valuesFrom`, and every one of those entries is `optional: true`, so the fixture
  works without it. It is deliberately not part of the fixture: the bucket names, access keys and policies
  are per-suite data — `homelab-loki-chunks` for `infra-observability`, `nas-cloudnativepg-backups` for
  `infra-database`. Keep the existing `pre-requisites/minio/` directory that generates it, and the
  `Secret/minio-user-credentials` it references.
- A wait. This is the one fixture a consumer may wait on at the `Kustomization` level, because `wait: true`
  is set here with a measured 4m health-check budget:

  ```yaml
  - description: Reconcile kustomization/pre-requisites-minio
    script:
      content: ../chainsaw/scripts/flux-reconcile.sh --resource-type=kustomization --resource-name=pre-requisites-minio --namespace=flux-system --timeout=5m
      timeout: 5m
  ```

  The script's timeout must **exceed** this object's own 4m health check, or the script gives up first and
  reports a deadline instead of the health-check failure that explains it. Waiting on
  `helmrelease/minio-release` directly (as `infra-observability` does) works equally well.
- **A late wait, not an early one.** MinIO supplies no CRD and no admission webhook, so by the criterion in
  [TESTING.md](../../../../TESTING.md#move-a-wait-to-where-the-dependency-actually-is) the wait belongs
  immediately before the first step that actually uses S3, not in the prerequisite block. Moving it took
  `infra-database` from 451s to 341s and `infra-observability` from 370s to 341s.

## Unproven

Least unproven of the six. Every patch here except the namespace is carried verbatim from
`ci/test/{infra-observability,infra-database}/pre-requisites/minio.yaml` on `fix/chainsaw-timing-and-order`,
where they were measured across several CI runs and a stress rig (MinIO reconcile 2,2,2,2,2,3s against 42-120s
before). What has not been run is this **as a fixture directory** with its own `Namespace` and the
`pre-requisites-minio` name: no suite consumes it yet.
