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
