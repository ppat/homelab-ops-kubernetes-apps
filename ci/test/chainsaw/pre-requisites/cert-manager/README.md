# `cert-manager` fixture

For a suite whose module under test ships `Certificate` or `Issuer` objects, and for anything else that needs
the cert-manager CRDs established and its validating webhook serving before the module is applied.

Shared conventions (naming, namespaces, post-build variables, waiting, `retryInterval`) are in
[../README.md](../README.md). Only what is specific to this fixture is below.

## Provides

Everything in `infrastructure/subsystems/security-core/cert-manager/`, unmodified:

- `HelmRepository/cert-manager-repository` (`flux-system`)
- `HelmRelease/cert-manager-release` (`cert-manager`) — controller, cainjector, webhook, startupapicheck
- `ClusterIssuer/selfsigned-issuer`
- `Namespace/cert-manager`, supplied by this fixture

`selfsigned-issuer` is the value every suite already passes as the `cert_issuer` post-build variable, so a
module that templates an issuer name has a working one to point at.

## Removed

Nothing. This fixture is the component directory as-is; there is nothing in it a consumer would not want.

### Do not disable `startupapicheck` to make this faster

It is the obvious thing to strip — a Job that only *checks*, adding roughly 37s between cert-manager's own
Deployments going Ready and the release going Ready — and stripping it would break consumers
nondeterministically.

That Job is `helm.sh/hook: post-install`, so Helm waits for it and the `HelmRelease` does not go Ready until it
passes. What it runs is `cert-manager ctl check api --wait=1m`, which **creates a real `CertificateRequest`
through the API server**. So it does not test that the webhook Deployment is Ready — it tests that the webhook
is *admitting writes*, and the gap between those two is exactly what the 37s is.

Every consumer of this fixture waits on `helmrelease/cert-manager-release` being Ready and then applies a
module containing `Certificate` or `Issuer` objects. The validating webhook matches `CREATE`/`UPDATE` on all
`cert-manager.io` and `acme.cert-manager.io` v1 resources with `failurePolicy: Fail`, so an apply that lands
in that gap is rejected outright rather than merely delayed. With `retryInterval: 1m0s` the recovery costs
longer than the check saves, and it is intermittent, which is worse — it would surface as suite flakiness with
no obvious cause.

Verified by rendering the chart at the pinned v1.21.1 rather than from documentation: the hook annotation, the
`check api` argument, the `certificaterequests: ["create"]` RBAC the Job is granted, and the webhook's
`failurePolicy`.

## Consumer must supply

- `infrastructure/bootstrap/crds/`, which is where the `cert-manager.io` CRDs come from. Without them the
  `ClusterIssuer` in this fixture fails to apply. Every suite already includes it.
- A wait. The usual form:

  ```yaml
  - description: Reconcile helmrelease/cert-manager-release
    script:
      content: ../chainsaw/scripts/flux-reconcile.sh --resource-type=helmrelease --resource-name=cert-manager-release --namespace=cert-manager --timeout=2m
      timeout: 2m
  ```

  2m is what `infra-database` uses today; size it from the adopting suite's own runs.

## Unproven

Nothing about the objects — this is the same component `infra-security`, `infra-database` and nine other
suites already deploy today, only reached by a shorter path. What has not been run is this fixture *as a
directory*: no suite consumes it yet.
