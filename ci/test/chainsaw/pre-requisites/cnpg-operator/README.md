# `cnpg-operator` fixture

The CloudNativePG operator, for a suite whose module under test creates a `Cluster` (a Postgres database).

Shared conventions (naming, namespaces, post-build variables, waiting, `retryInterval`) are in
[../README.md](../README.md). Only what is specific to this fixture is below.

## Provides

- `HelmRepository/cloudnative-pg-repository` (`flux-system`)
- `HelmRelease/cloudnative-pg-release` (`cnpg-system`) — the operator and the `postgresql.cnpg.io` CRDs
- `Namespace/cnpg-system`, which comes from the component directory itself

No namespace is supplied by this fixture; `database-core/cloudnative-pg/` ships its own.

## Removed, and why

`HelmRelease/plugin-barman-cloud-release`.

Barman Cloud is a second capability — backing a `Cluster` up to object storage — rather than part of "an
operator that reconciles `Cluster` objects". It is only reachable through the `components/db-backups` and
`components/db-restore` overlays, and the only suite that exercises those is `infra-database`, where
`database-core` is the module under test and this fixture is therefore not used at all.

## What a consumer would lose

A suite that applies `components/db-backups` or `components/db-restore` to its `Cluster` **cannot use this
fixture**: the `barmancloud.cnpg.io` CRDs are not installed and the plugin Deployment is not running, so the
`Cluster` will not reconcile. It would need `database-core/cloudnative-pg` in full.

There is deliberately no seventh fixture for the plugin alone. Nothing would consume it — the one suite that
needs backups is the one that tests the module itself.

## Consumer must supply

- `infrastructure/bootstrap/crds/`. Not for this fixture's own objects, but because a module that creates a
  `Cluster` references `postgresql.cnpg.io` from the moment it is applied. Every suite already includes it.
- A wait. The usual form:

  ```yaml
  - description: Reconcile helmrelease/cloudnative-pg-release
    script:
      content: ../chainsaw/scripts/flux-reconcile.sh --resource-type=helmrelease --resource-name=cloudnative-pg-release --namespace=cnpg-system --timeout=4m
      timeout: 4m
  ```

  Size it from the adopting suite's own runs, and note that this particular reconcile has form: it killed
  eight `apps-downloaders` runs at exactly 120-121s against a 2m budget.

## Unproven

The operator is the same one eleven suites deploy today. What has not been run is CloudNativePG **without**
the Barman plugin installed alongside it — no suite has that combination today. The plugin is a separate
`HelmRelease` with no `dependsOn` either way and the operator does not reference it, so nothing is expected
to change; but it has not been observed.
