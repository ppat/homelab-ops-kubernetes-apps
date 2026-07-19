# Finding every place a module is configured

`projectBrief.md#configuration` documents the three mechanisms (Kustomize
patches, Flux post-build variables, component overlays) — read that for what each
mechanism is *for*. This file is about the practical problem specific to an
upgrade: a value the old chart version read might now live somewhere else, or a
patch that targeted a field that no longer exists silently no-ops instead of
failing, so you have to go looking rather than trust that "no error" means
"nothing broke."

## Where a HelmRelease's effective values can come from

A chart's rendered values are the merge of all of these — check every one that's
present, because a value set in one silently overrides or is overridden by
another and you need the full picture before you can tell what the new chart
version will actually receive:

- `spec.values` inline in the HelmRelease itself
- `spec.valuesFrom` (a Secret/ConfigMap key merged in — easy to forget because it
  isn't in the file you're editing)
- Consuming clusters' `spec.patches` on the HelmRelease (JSON6902/strategic) — the
  module itself never shows these; you have to check
  `../homelab-ops-kubernetes-clusters/clusters/*/kustomizations/` for any patch
  targeting this HelmRelease
- `spec.postRenderers[].kustomize.patches` — post-render patches operate on the
  chart's *rendered output*, not its values, so a field that moved between chart
  versions can silently stop matching a `postRenderers` patch's `target`/`path`
  (JSON6902 patches fail loudly on a missing path with `op: remove`/`replace`;
  `op: add` on a changed path succeeds but adds the field somewhere unintended —
  don't assume either failure mode announces itself the same way)

## Where a Kustomization's effective config can come from

- `spec.patches` on the module's own `Kustomization` resources within this repo
- `spec.postBuild.substitute` / `substituteFrom` — inline vars vs. a
  Secret/ConfigMap (e.g. `cluster-secrets`); a variable renamed in this repo's
  module needs a matching rename in every consuming cluster's
  `postBuild.substitute`
- **Ordering matters and isn't a special case for one repo** — Flux applies
  `spec.patches` at kustomize-**build** time, strictly before
  `postBuild.substitute` runs. A patch that targets a resource by a name
  containing a `${var}` placeholder is matching against the *unsubstituted*
  literal string, not the value it resolves to — target by `kind`/`group`
  instead of by a substituted name whenever the resource's name itself is
  templated. This one is worth remembering rather than rediscovering: it's a
  property of how Flux's Kustomization controller sequences these two features,
  not a quirk of any particular module.

## `components/` may apply to the module even though it's rarely tested

Check whether any cross-cutting `components/*` (`sso`, `db-backups`, `cert-issuer`,
`oidc-credentials`, etc.) is layered onto this module in production — via a
consuming cluster's `spec.components` — even if the module's own chainsaw suite
never exercises it. **Most `components/*` directories have no chainsaw test
coverage at all**; only the ones a past upgrade specifically added test coverage
for (e.g. `db-backups`/`db-restore`, after the CNPG migration) do. A component
with zero test references isn't "not applicable" — check
`../homelab-ops-kubernetes-clusters/clusters/*/kustomizations/` for whether any
cluster actually applies it to this module in production regardless.

If your upgrade changes something a component patches or depends on, decide
whether the component is cheap enough to add real test coverage for (as the
CNPG/`db-backups` migration did — a self-contained dependency with a fakeable
backend like MinIO was tractable in a kind cluster) versus one whose
prerequisites make that impractical (e.g. `sso`/`oidc-credentials` typically
depend on an external IdP and enough other infrastructure that standing it up in
a chainsaw suite isn't a good trade). When it's not testable, that's a reason to
be more conservative in the manifest change itself and to call out the untested
production path explicitly — not a reason to skip checking whether it's affected.

## A changed workload topology needs systems thinking, not a values diff

Some upgrades change the *topology* this repo deploys — not just values, but
the actual shape of the running system: how many workloads exist, what each one
is responsible for, how they're divided up and wired together. When that shape
changes, everything else in this repo and the clusters repo that was configured
*against the old shape* is a candidate for silent invalidation — not just the
config attached to whichever key got renamed. A value, policy, or reference can
survive an upgrade completely untouched and syntactically valid while quietly
describing a system that no longer exists. Reasoning about this needs systems
thinking, not a diff: for each piece of old-shape-specific config, ask what
about the *new* shape it now actually has to hold true for, not whether its key
still resolves.

Resource/storage sizing per role is one instance of this, and the clearest to
spot because it fails loudly (a full disk, an OOM). It's not the only one — the
same reasoning applies to anything else scoped to the old topology: network
policies or firewall rules naming a workload that merged away, PodDisruptionBudgets
or anti-affinity rules assuming an old replica count or role split, monitoring/
alerting rules or dashboards keyed to old component names, or another module's
config referencing a service/endpoint name that only existed under the old
shape. None of these necessarily error — they can keep matching *something*, or
match nothing and simply go quiet, without ever surfacing as a failure.

Loki is a sizing example of this: one deployment mode splits
ingestion-buffering, querying, and compaction across three separately-sized
roles; a newer mode collapses all three onto one role that *already existed*
under the old mode too, but back then only had a small, lightly-loaded job.
Carrying over that role's small pre-merge storage value after the merge — same
key, unchanged — silently under-sized it for the one job (ingestion buffering)
that used to belong to the most heavily-provisioned of the three roles it now
absorbs. The value never errored; it was just wrong for what the role became.

## Exhaustive search, not spot-checks

`rg`/`grep` are the right tool here precisely because the task is coverage, not
judgment — every `helm-release-*.yaml` for the chart's name, every
`kustomization.yaml`/`*.yaml` under this module's directory for `patches:`,
every `components/*` that might layer onto it, and (separately) every consuming
cluster's Kustomization for a patch or substitution touching this module. Don't
rely on memory of "where config usually lives" for this module — a module that
has grown a `postRenderers` block or a `valuesFrom` secret since you last touched
it won't show up unless you actually search for it. This enumeration is a good
candidate for the parallel research fan-out described in the main skill file —
it's coverage work, not diagnosis.
