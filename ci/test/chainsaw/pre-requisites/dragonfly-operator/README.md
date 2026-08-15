# `dragonfly-operator` fixture

The Dragonfly operator, for a suite whose module under test creates a `Dragonfly` (a Redis-compatible cache).

Shared conventions (naming, namespaces, post-build variables, waiting, `retryInterval`) are in
[../README.md](../README.md). Only what is specific to this fixture is below.

## Provides

- `OCIRepository/dragonfly-operator` (`flux-system`)
- `HelmRelease/dragonfly-operator-release` (`dragonfly-system`) — the operator and the `dragonflydb.io` CRDs
- `Namespace/dragonfly-system`, which comes from the component directory itself

No namespace is supplied by this fixture; `database-core/dragonfly/` ships its own.

## Removed

Nothing. This fixture is the component directory as-is.

## Consumer must supply

- `infrastructure/bootstrap/crds/`, because a module that creates a `Dragonfly` references `dragonflydb.io`
  from the moment it is applied. Every suite already includes it.
- A wait, and a generous one. This operator is measured Ready at **T0+178s** — one of the last things to
  converge in any cluster it is installed into, which is exactly why it is a separate fixture rather than
  something `cnpg-operator` drags along.

  ```yaml
  - description: Reconcile helmrelease/dragonfly-operator-release
    script:
      content: ../chainsaw/scripts/flux-reconcile.sh --resource-type=helmrelease --resource-name=dragonfly-operator-release --namespace=dragonfly-system --timeout=4m
      timeout: 4m
  ```

  Size it from the adopting suite's own runs.

## Unproven

The operator is the same one every suite that pulls in `database-core` deploys today. What has not been run
is Dragonfly **without** CloudNativePG alongside it. The two releases have no `dependsOn` between them and
share nothing but the `database-core` directory, so nothing is expected to change; but it has not been
observed.
