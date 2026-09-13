# `garage` fixture

Garage as an S3 endpoint. Garage is MinIO's intended successor here: after a planned 30-day trial of
Loki-on-Garage the intention is to move everything across and decommission MinIO. This fixture exists so that
it is ready when that happens.

> **This fixture has never been run.** Nothing consumes it, and no CI run has ever deployed Garage in this
> configuration. The first suite to adopt it should treat run one as **validation, not regression** — a
> failure is at least as likely to be a defect in this directory as in whatever change is being tested.
> Details in [Unproven](#unproven).

Shared conventions (naming, namespaces, post-build variables, waiting, `retryInterval`) are in
[../README.md](../README.md). Only what is specific to this fixture is below.

## Provides

- `Deployment/garage` (`garage`), single instance, `--single-node`, `replication_factor = 1`
- `Service/garage` — S3 API on 3900, RPC 3901, web 3902, admin 3903
- `Ingress/garage-s3` and `Ingress/garage-admin`
- `ConfigMap/garage-config` (from `conf.d/garage.toml`), `ServiceMonitor`, `PrometheusRule`, and the Garage
  Grafana dashboard `ConfigMap`
- `Secret/garage-credentials` (`garage`) — a plain Secret, see below
- `PersistentVolumeClaim/garage-data` (200Mi) and `PersistentVolumeClaim/garage-metadata` (100Mi)
- `Namespace/garage`, supplied by this fixture

It needs no `ClusterSecretStore`, no external-secrets and no cert-manager. This fixture composes with
nothing.

## Removed, and why

| removed | reason |
| --- | --- |
| `Certificate/garage-web-tls-cert` | needs cert-manager |
| `Ingress/garage-web` | the only consumer of that certificate |
| `ExternalSecret/garage-credentials` | replaced by a plain `Secret` of the same name |

The first two are the only objects in this component that pull cert-manager in, and a fixture that drags
cert-manager along is not supplying one thing. `Ingress/garage-s3` and `Ingress/garage-admin` both set
`tls: []` and are kept — neither needs a certificate of its own.

The credential swap is the same trade [`../minio/`](../minio/README.md) makes, for the same reason: wherever
this fixture is used Garage is scaffolding, so resolving its own credential through external-secrets is
storage-core's behaviour and belongs in `infra-storage`, where Garage is the subject and the `ExternalSecret`
is kept. It removes the last reason a suite would need external-secrets standing just to get object storage.
Note this goes one step beyond the two removals originally specified for this fixture.

## What a consumer would lose

- **Bucket-per-subdomain static web serving.** Garage resolves a bucket from the `Host` header two ways
  (`conf.d/garage.toml`, `[s3_web]`): a suffix match on `<bucket>.garage-web.${domain_name}`, and a
  whole-host fallback for the apex. Without `Ingress/garage-web` neither hostname routes to the Service, and
  without the `Certificate` the wildcard host has no cert. A suite testing the web endpoint cannot use this
  fixture; use `infra-storage`, which keeps both.
- **Garage resolving its own credentials through external-secrets** — likewise `infra-storage`'s job. A
  consuming suite's own `ExternalSecret` objects are untouched.
- Nothing else. The S3 API, the admin API, metrics and the dashboard are all intact.

## Consumer must supply

- `infrastructure/bootstrap/crds/`, for `monitoring.coreos.com` — the component ships a `ServiceMonitor` and
  a `PrometheusRule`. Every suite already includes it.
- A wait, budgeted generously:

  ```yaml
  - description: Assert deployment/garage
    assert:
      bindings:
      - name: name
        value: garage
      - name: namespace
        value: garage
      file: ../chainsaw/assertions/deployment-ready.yaml
      timeout: 5m
  ```

  5m is what `infra-storage` uses. Garage's `readinessProbe` is a cluster-health check and its `startupProbe`
  suppresses readiness until `/health` first returns 200, so the Deployment cannot report Available until
  Garage itself is up rather than merely started.
- **A late wait, not an early one.** Garage supplies no CRD and no admission webhook, so by the criterion in
  [TESTING.md](../../../../TESTING.md#move-a-wait-to-where-the-dependency-actually-is) the wait belongs
  immediately before the first step that actually uses S3.
- **Buckets and access keys.** Unlike MinIO's chart, nothing here creates them; Garage's own admin API does,
  behind the `GARAGE_ADMIN_TOKEN` in `garage-credentials.yaml`. `ci/test/chainsaw/scripts/garage-roundtrip.sh`
  is the existing seam for that.
- A different `domain_name` or `garage_s3_region`, if the suite needs one, by patching this fixture's
  `Kustomization` from the suite's own `pre-requisites/kustomization.yaml`. Note that
  `garage_s3_region` is half of a contract with whatever consumes Garage as an S3 client: a client signing
  with a different region is rejected outright (`AuthorizationHeaderMalformed`), and Loki's own
  `loki_s3_region` must match this exact value or its compactor crashloops on first delete-store init
  (see #3611).

## Unproven

Everything, in the sense that matters. Specifically, none of the following has been observed even once:

- Garage running with `Ingress/garage-web` and `Certificate/garage-web-tls-cert` absent. Nothing in the
  Deployment, the Service or `garage.toml` references either object, so it is expected to be inert — but the
  `[s3_web]` listener still binds on 3902 and `root_domain` is still set, so the only thing actually removed
  is external routing. That reasoning is from reading the manifests, not from a run.
- Garage taking its credentials from a plain `Secret` rather than through the `ExternalSecret`. The
  `Deployment`'s `secretKeyRef` names the Secret and its two keys directly, and the values here are the ones
  `infra-storage`'s fake store already feeds through, so the bytes the container sees should be identical.
  Read, not run.
- The PVC names `garage-data` / `garage-metadata`. `infra-storage` uses `-test` suffixes, so these exact
  names have never been substituted into the Deployment.
- Garage in any namespace configuration other than `infra-storage`'s.

What *has* been exercised, in `infra-storage` on every run of that suite, is the component itself: the
Deployment, the `--single-node` layout bootstrap, the S3 and admin APIs, and an S3 round-trip.
