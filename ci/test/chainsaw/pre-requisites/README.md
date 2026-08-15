# Shared chainsaw pre-requisite fixtures

Composable fixtures for the infrastructure a chainsaw suite needs standing *before* the module under test can
be applied. Each directory supplies **one capability and nothing else**. A suite adopts one by adding a single
line to its own `pre-requisites/kustomization.yaml`:

```yaml
resources:
- ../../chainsaw/pre-requisites/cert-manager/
```

| fixture | provides | module path it points at |
| --- | --- | --- |
| `cert-manager/` | cert-manager + `ClusterIssuer/selfsigned-issuer` | `security-core/cert-manager` |
| `external-secrets/` | the External Secrets operator alone | `security-core/external-secrets` |
| `cnpg-operator/` | the CloudNativePG operator alone | `database-core/cloudnative-pg` |
| `dragonfly-operator/` | the Dragonfly operator | `database-core/dragonfly` |
| `minio/` | MinIO as an S3 endpoint | `storage-core/minio` |
| `garage/` | Garage as an S3 endpoint (**never yet run**, see its README) | `storage-core/garage` |

## Why these exist

Before these, a suite that needed one component pulled in the **whole module** that contains it and then
patch-deleted the parts it did not want. Measured cost: eleven suites spent 66-127s in their prerequisite
phase against 21-28s for the five suites that used no module fixture at all (`infra-security`,
`infra-virtualization`, `infra-kubernetes`, `infra-clusterops`, `apps-media`). `apps-misc` spent 66s standing
up a fixture to run a 15s test.

Component subdirectories of a module are standalone kustomizations, so a fixture can point a Flux
`Kustomization` at a *component* path directly and skip everything else in the module.

## What a suite gives up by adopting these

Eleven suites reached cert-manager and external-secrets by deploying the whole `security-core` module, so
adopting these fixtures also stops them deploying kyverno, policy-reporter and trust-manager. Per component,
what that costs:

- **kyverno** acts on resources only through `Policy`/`ClusterPolicy` objects, and there are none anywhere in
  this repository — every policy in this homelab lives in the sibling clusters repo under `policies/`, applied
  by cluster-level Flux `Kustomization`s that CI never deploys. So in CI kyverno runs with an empty policy set
  and its mutating webhook configuration is generated with no rules: it intercepts nothing. Outside
  `ci/test/infra-security/`, no suite asserts anything about it.
- **policy-reporter** reports on kyverno policies, of which there are none — and all eleven suites already
  patch-deleted it before these fixtures existed, so nothing changes for it at all.
- **trust-manager** provides the `Bundle` API. Exactly one assertion in the repo reads a `Bundle`
  (`infra-security/validate-external-secrets.yaml`, via `assertions/bundle-synced.yaml`), and it is in the
  suite that still deploys trust-manager.

So what the eleven stop exercising is "these three install cleanly alongside the module under test", which
`ci/test/infra-security/` covers as its own subject. A suite needing a `Bundle` of its own cannot use the
`external-secrets` fixture; see its README.

## Conventions every fixture follows

Read these once here rather than six times in the individual READMEs.

### Naming

Flux `Kustomization` objects are named `pre-requisites-<fixture>`. The prefix does two things: it cannot
collide with a module-under-test `Kustomization` (all of those are named `apps-*` / `infra-*`), and in a
`catch` dump it says at a glance that a failing object is scaffolding rather than the subject of the test. It
matches the name of the parent `Kustomization` (`pre-requisites`) that applies these objects, and the
`pre-requisites` spelling the repo already uses.

### Namespaces

**A fixture owns every namespace it needs.** Four of the six supply one, because the module keeps its
namespaces in the module root (`security-core/namespace.yaml`, `storage-core/namespace.yaml`) rather than in
the component directory the fixture points at — so pointing at the component alone would leave the namespace
unowned. `cnpg-operator` and `dragonfly-operator` supply none, because those two component directories ship
their own `namespace.yaml`.

No two fixtures create the same namespace, so composing any combination of them is safe. What is *not* safe
is a fixture and the adopting suite's own `namespaces.yaml` both declaring one — kustomize refuses to build a
duplicate resource id, which surfaces as the `pre-requisites` `Kustomization` failing at
`Assert kustomization/pre-requisites`. The fix is to delete the line from the suite's `namespaces.yaml`; that
belongs in the PR that adopts the fixture.

The namespaces here are plain, without the `kustomize.toolkit.fluxcd.io/prune: disabled` and `ssa: merge`
annotations the module's own carry. Those govern production lifecycle, and every test `Kustomization` in this
repo already sets `prune: false`.

### Post-build variables

**A fixture supplies every `${...}` its built output references. A consumer supplies none.** Consistency
matters more here than the direction, because the alternative — each suite guessing which of six fixtures
needs which variable — is exactly the per-suite duplication these replace. `cert-manager`,
`external-secrets`, `cnpg-operator` and `dragonfly-operator` reference no variables at all and therefore
carry no `postBuild` block.

Note that Flux applies `spec.patches` **before** `postBuild.substitute`, so a variable referenced only by an
object a fixture deletes never needs a value.

### Waiting

Five of the six set `wait: false` and leave the wait to the consumer, which is what all sixteen suites
already do: a `Reconcile pre-requisites` step running
`../chainsaw/scripts/flux-reconcile.sh --resource-type=helmrelease --resource-name=<release> ...` with a
timeout sized from that suite's own measurements. Putting a `wait: true` health-check budget on the fixture
would mean inventing a number that no run has ever produced, which
[TESTING.md](../../../../TESTING.md#size-budgets-from-measurement-in-both-directions) treats as a defect in
its own right.

`minio` is the exception and it is measured rather than sloppy: `infra-database` waits on
`kustomization/minio` instead of on the release, and that object's `wait: true` / `timeout: 4m0s` pair was
sized on observed CI (28.1/82.1/94.1s green) and exercised on the branch it came from. Its README says so.

### `retryInterval`

Every fixture sets `retryInterval: 1m0s`. Flux defaults `retryInterval` to `interval` when it is unset, and
`interval` here is `15m0s` — so a single transient failure parks the object for a quarter of an hour, far
longer than any suite runs. Confirmed against the Flux v2.9.4 CRD schema and observed in run logs: after a
health check expired, the `minio` `Kustomization` still read `False` 3m32s after its own `HelmRelease` had
gone Ready, with no retry in between. See #3685.

### What a consumer still has to supply

- `infrastructure/bootstrap/crds/` in its own `pre-requisites/kustomization.yaml`. All sixteen suites
  already do; `cert-manager`, `minio` and `garage` apply objects whose CRDs come from there.
- A `fake` `ClusterSecretStore`, **only** if the module under test has its own `ExternalSecret` objects. No
  fixture here needs one — `minio` and `garage` deliberately take their credentials as plain Secrets. The
  fake store stays per-suite because its keys differ per module: it is suite data, not a shared fixture.
