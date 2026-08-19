# `external-secrets` fixture

The External Secrets operator on its own, for a suite whose module under test ships `ExternalSecret` objects
and resolves them through a `fake` `ClusterSecretStore`.

Shared conventions (naming, namespaces, post-build variables, waiting, `retryInterval`) are in
[../README.md](../README.md). Only what is specific to this fixture is below.

## Provides

- `HelmRepository/external-secrets-repository` (`flux-system`)
- `HelmRelease/external-secrets-release` (`external-secrets`) — the controller, the validating webhook, and
  the built-in certController that issues that webhook's certificates
- `Namespace/external-secrets`, supplied by this fixture

That is enough for `ClusterSecretStore`, `SecretStore` and `ExternalSecret` to work.

## Removed, and why

This component directory is mostly Bitwarden. Four of its six files exist to let the `bitwarden-sdk-server`
subchart terminate TLS, and all four need cert-manager running. A `fake` store never talks to Bitwarden, so
all of it comes out:

| removed | what it was for |
| --- | --- |
| `Issuer/bitwarden-ca-issuer`, `Certificate/bitwarden-ca-cert`, `Issuer/bitwarden-cert-issuer`, `Certificate/bitwarden-sdk-server-cert` | the self-signed CA and leaf certificate for `bitwarden-sdk-server` |
| `Bundle/bitwarden-ca-cert` | distributing that CA into namespaces labelled `bitwarden-secrets/enabled` |
| `HelmRelease/trust-manager-release` | reconciling that `Bundle`, and nothing else |
| `spec.values.bitwarden-sdk-server.enabled: true` → `false` | the provider sidecar itself |
| `spec.dependsOn: cert-manager-release` | see below |

**The `dependsOn` removal is not independently justifiable.** That dependency is load-bearing in production:
`bitwarden-sdk-server` cannot start without a certificate, and cert-manager is what issues it. It is safe to
remove here *only because* the rows above it have already taken every object that needs a certificate out of
this fixture and turned the subchart off. If a future change puts anything back that needs cert-manager, the
dependency has to come back with it.

What removing it buys: the dependency serialises cert-manager and external-secrets in every suite that uses
this fixture, whether or not the test needs certificates at all — and a lost dependency race is not merely
slow. `HelmRelease` has no `retryInterval`, so `interval` is also how long a release blocked on an unready
dependency waits before re-checking; that has already caused an outright suite failure (#3685).

Two things checked rather than assumed:

- The chart defaults `webhook.certManager.enabled` to `false` and this module does not override
  it, so the operator's own webhook certificates come from its built-in certController, not from
  cert-manager.
- The chart's `Chart.yaml` declares the subchart with `condition: bitwarden-sdk-server.enabled`, and
  `helm template` with that value false renders exactly three fewer objects — the
  `bitwarden-sdk-server` ServiceAccount, Service and Deployment — and no other difference.

## What a consumer would lose

A suite that actually needs to resolve secrets **through the Bitwarden provider** cannot use this fixture:
there is no `bitwarden-sdk-server`, no CA, and no `SecretStore` pointing at one. It would need the whole
`security-core` module, with cert-manager alongside it. No suite in this repo does that today — every one of
them uses a `fake` `ClusterSecretStore`.

A suite that needs trust-manager for its own reasons (any `Bundle` of its own) also cannot use this fixture.

## Consumer must supply

- The `fake` `ClusterSecretStore` its own module's `ExternalSecret` objects resolve against. This stays
  per-suite — the keys differ per module, so it is suite data, not a shared fixture.
- A wait. The usual form:

  ```yaml
  - description: Reconcile helmrelease/external-secrets-release
    script:
      content: ../chainsaw/scripts/flux-reconcile.sh --resource-type=helmrelease --resource-name=external-secrets-release --namespace=external-secrets --timeout=2m
      timeout: 2m
  ```

  This wait cannot be moved late: the module's own manifests contain `ExternalSecret` objects, so the CRD
  must be established and the webhook serving before the module `Kustomization` is applied at all. See
  [TESTING.md](../../../../TESTING.md#move-a-wait-to-where-the-dependency-actually-is).

## Migrating a suite that used the whole security module

Read this before adopting. Dropping `dependsOn: cert-manager-release` also drops something a
consumer may not realise it had: a suite that waited only on `external-secrets-release` was
**transitively** waiting on cert-manager too, because external-secrets would not go Ready until
cert-manager had. That guarantee disappears with the dependency.

The trigger is **"does the module under test, or any chart it installs, need cert-manager?"** — not
"does the module ship a `Certificate`". Those differ, and the narrower reading is wrong.

`infra-database` is the case that proves it: `database-core` ships no `Certificate` at all, yet needs
cert-manager, because the **Barman Cloud plugin's chart** issues its own gRPC TLS certificates through
it. Grepping the module's manifests would have said no, and `Validate plugin-barman-cloud` would have
gone red. **Check the module's own README `Dependencies` / `Prerequisites` section**, which states it.

Where the answer is yes, adopting this fixture means:

1. compose `../cert-manager` as well, **and**
2. add an explicit reconcile-and-wait step for `cert-manager-release`, which the suite previously
   got for free.

`apps-misc` is the live case: maddy ships `Certificate/smtp-tls` against `${cert_issuer}`, mounts
the resulting Secret, and asserts the Certificate is Ready. Adopting external-secrets alone would
have turned that suite red rather than fast.

## Unproven

The objects are the same ones eleven suites deploy today, but **no suite has yet run external-secrets with
the Bitwarden half removed** — today every suite gets it with `bitwarden-sdk-server` enabled and cert-manager
alongside. The subchart toggle is verified by `helm template`, and the certController default by the chart's
values, but neither has been observed on a live cluster in this configuration. The first suite to adopt this
should treat run one as validation.
