# Consuming release notes and chart source

Several different sources answer different questions. Don't conflate them —
each tells you something the others don't:

- **Release notes** (the project's changelog/release page) — what the maintainers
  say changed, in their own words, including deprecations and breaking changes
  they thought worth calling out.
- **`values.yaml`** — the chart's configurable surface and its defaults. Its
  *comments* are often the only place a value's intent or valid options are
  documented at all.
- **`Chart.yaml`** — the chart's own metadata: its version, its `appVersion`, its
  `dependencies:`.
- **The CRD spec** (if the chart installs one) — the schema a live CR is
  validated against; this is what actually breaks if a field's type or
  requiredness changed, independent of anything the chart's values do.

Skipping straight to "diff the values.yaml" without also checking release notes
and the CRD spec (when relevant) misses the two sources most likely to contain an
actual breaking change.

## Chart version vs. app version — don't expect both to be set

In this repo's HelmReleases, `spec.chart.spec.version` (the **chart** version) is
almost always the only version pinned — check any `helm-release-*.yaml` in this
repo and you'll see `version: X.Y.Z` with no separate app-version field anywhere.
We don't track the app version ourselves; we rely on the chart to state which
app version a given chart version ships.

**The relationship between the two is asymmetric, not proportional.** A major
app version bump can be expected to be reflected in a major chart version bump —
chart maintainers cut a new major chart release to carry a major app change, so
a chart major bump is a reasonable signal that *something* app-level changed.
But the reverse doesn't hold: a chart can bump its own major version many times
over for reasons entirely internal to the chart (values restructuring, a
templating rework, a subchart dependency change) with no corresponding app
version change at all — sometimes not even a minor one. Loki's chart went
`7.0.0 → 18.5.1` (11 chart majors) while its app version moved only
`3.6.7 → 3.7.3` (one app minor); nearly every breaking change in that jump was
pure chart-schema/values churn, not app behavior.

This means the chart version number alone doesn't tell you *how much* changed,
or on which side — regardless of which side moved more, both need checking.
Confirm the target app version explicitly (`Chart.yaml`'s `appVersion:` field,
see below, or `helm show chart <repo>/<chart> --version X.Y.Z`) and do the
chart-side research either way. For *which* release notes to actually read: the
chart's own release notes/changelog (or a README "Upgrading" section — see
below) usually already capture the deployment-relevant implications of an
app-level change, since that's precisely the audience the chart maintainers
write for. But sometimes an app behavior change doesn't manifest as any
chart-level values/schema difference at all, or the chart's own docs lag behind
the app's — in those cases, go read the app's own release notes directly rather
than assuming the chart's notes are a complete proxy.

## Historical CI runs are not research material

Don't inspect this repo's past GitHub Actions run history — an open Renovate
PR's failed checks, a previous manual attempt's log, unrelated branches' CI
state — as part of scoping this upgrade or deciding what to research. None of
that is signal about what actually changed in the chart/app between versions;
at best it tells you *something* about one attempt failed, which isn't the
same question as *why*, and reading it costs real context for no research
value. Decide the target version and scope from the sources this file already
names (release notes, `values.yaml`, `Chart.yaml`, the CRD spec) — not from
what a bot's PR happened to propose or how its CI happened to go.

The one place a past or concurrent run's pass/fail state is legitimate
evidence is later and narrower: diagnosing a failure in *your own* current
run. See `diagnostic-approach.md`'s "Recognizing a pre-existing or unrelated
CI failure" — and even there, it's something the subagent watching your own
run checks to rule in/out an environmental cause, not something to go digging
into speculatively before you have a failure to diagnose.

## Getting release notes

`gh release view <tag> --repo <org>/<repo>` (or `gh api
repos/<org>/<repo>/releases` for the whole list) returns the release notes as
clean structured text — this is the right tool, and cheaper than it looks: the
payload is just the release body, not a full webpage.

**Fetch the notes for the from-version and to-version (both inclusive), plus
every major version in between** at minimum — a deprecation introduced two
versions back and only *removed* in the target is easy to miss if you read just
the final delta. Then check whether this particular project is one that ships
breaking/major changes inside what looks like a *minor* bump — some do
(Kubernetes itself, Flux, Longhorn, and others use minor version numbers for
changes that would conventionally be "major" elsewhere). If so, fetch every
minor version's notes in the range too, not just the majors — a project's own
versioning conventions determine how fine-grained this needs to be, so check
that before assuming major-only coverage is enough.

If a project's release notes are thin or don't cover what you need, a docs-site
migration guide (when the project publishes one for exactly this transition) is
usually the next-best source — it's already synthesized by the maintainers rather
than something you have to infer yourself.

## Diffing chart versions: `helm template`, not a raw values/templates diff

The most direct way to see what changed for *your specific upgrade* is to render
the chart both ways and diff the output:

1. **`helm template <chart> --version <old>` vs. `--version <new>`, with no
   values file** — shows what changed in the chart's own *defaults*. Useful for
   understanding the chart's evolution in general.
2. **The same, but with `-f` pointed at this module's actual effective values**
   (reconstructed from its HelmRelease `spec.values` + `spec.valuesFrom` +
   `postRenderers`, per `config-surfaces.md`) — shows what changes **for the
   config this repo actually ships**, which is the one that matters. If this
   render fails outright on the new version, that failure *is* the diagnostic
   signal — it's telling you a value this repo sets is no longer valid, before
   you've touched a single manifest.
3. Diff the two rendered outputs. Rendered manifests are large and full of
   low-signal noise (label/annotation ordering, checksums, alphabetical key
   reshuffling) that a raw `diff` will flag even though nothing meaningful
   changed. Pipe both through `yq -P 'sort_keys(..)'` (or equivalent) before
   diffing to normalize structure and cut that noise — this is a local, free
   operation, so there's no reason to skip it before a large rendered-output
   diff. A plain `values.yaml` is usually small enough (rarely more than a few
   hundred lines) that reading it directly is often just as fast as normalizing
   first — reserve the normalize-before-diff step for outputs large enough that
   the noise would otherwise dominate the diff, which in practice means rendered
   templates far more often than `values.yaml` itself.

## Getting `values.yaml`/`Chart.yaml` with their comments intact

`helm template`/`helm show values` strip comments. When a value's *meaning* isn't
obvious from its key name alone, the comments in the source `values.yaml` are
often the only explanation that exists. `helm pull <chart> --repo <url> --version
X.Y.Z --untar --untardir /tmp/...` gets you the exact packaged chart for that
exact version — `values.yaml`, `Chart.yaml`, `templates/`, and often the chart's
own `README.md`, all with comments intact — without needing to guess a chart
repo's tag-naming convention (which varies: `<chart-name>-vX.Y.Z`, bare
`vX.Y.Z`, the app version instead of the chart version). This is simpler than
cloning the chart's source repo for the same goal and should be the default. A
source-repo clone is only worth it if you specifically need something `helm
pull` doesn't give you — commit history, an issue tracker, or a version that
predates what the Helm repo index still serves.

## Templates and the rest of the chart's implementation

Reading the chart's actual template files (not just `values.yaml`) is rarely
useful during this initial research phase — you're trying to scope what changed,
and templates are implementation detail that values/release-notes/CRD-spec
already summarize. They become valuable later, during diagnosis, when a rendered
output or a live failure doesn't match what you expected and you need to see
*why* a template produced what it did. Save that read for when you're actually
stuck on a specific rendering question, not as a first-pass research step.

## App-level docs can describe manual steps the chart has already automated

A fifth thing to check, alongside the four sources above: many projects' own
operational documentation (clustering, HA, leader election) is written for
someone deploying the software directly on hosts — not through this chart.
That doc's "you must configure X, Y, Z for HA" can describe exactly what the
chart has already wired into its defaults or templates, unconditionally, as
part of turning the app into a StatefulSet + Service. Treating the doc's
manual-deployment steps as a checklist to replicate in `values.yaml`, without
first checking whether the chart's own templates already provide the
equivalent, adds real, unneeded complexity.

This showed up once with Loki: grafana.com's own "HA monolithic" doc describes
manually configuring a `memberlist` ring, a dedicated `horizontal_scaling_mode:
main` compactor role, and a Thanos object-storage client — real requirements if
running Loki binaries on raw hosts. Checking the chart's actual templates (not
the doc) showed all of that was already automatic: `memberlist.join_members` is
wired into the rendered config unconditionally regardless of deployment mode,
the compactor already self-elects a single leader via its own ring with
`horizontal_scaling_mode` defaulting to `disabled` (an *optional*
work-distribution feature, not a safety requirement), and Thanos-objstore is an
unrelated alternate storage-client implementation. None of the extra config the
doc described was actually necessary.

The generalizable move: when an app's own docs describe manual
coordination/HA setup, check what the chart's *templates* actually render by
default before treating the doc's steps as something you need to add — the doc
is often written for a different deployment shape than the one you're using.

## Checking for downstream CR breakage

**Gate the whole CRD investigation on actual usage, first.** If the chart
installs a CRD, before spending any effort on "did its schema change," check
whether this repo (or the clusters repo) creates any CR of that `kind`/
`apiVersion` at all — a quick `rg`/`grep` for the `kind:` across `apps/`,
`infrastructure/`, `components/`, and
`../homelab-ops-kubernetes-clusters/clusters/`. If nothing uses it, there's
nothing to check further; skip straight past this section. Only if there's a
real hit does it become worth reading the CRD's release notes and schema for
what changed, and then checking whether any field a live CR sets was renamed,
restructured, or deprecated.

**If the CRD did change and this repo does use it, the bootstrap CRDs bundle
almost certainly needs the matching version bump too.**
[`projectBrief.md#bootstrap-and-crds`](../../../../projectBrief.md#bootstrap-and-crds)
covers what `infrastructure/bootstrap/crds/` is for and when it's engaged
(first-time cluster setup, disaster recovery) — this skill adds one more
scenario to that list: chainsaw test prerequisites, since a fresh kind cluster in
CI is functionally a first-time setup too. A live cluster's Helm release keeps
its own CRDs current on every upgrade, so this bundle only matters for those
scenarios — but within them, an out-of-date bootstrap CRD is exactly the kind of
gap that only surfaces once you try to test the upgrade, not during the
chart-version research itself.

## Checking for new/dropped dependencies

Read the chart's `Chart.yaml` (`dependencies:`) and the app's own prerequisite
docs (TLS, a database, a message queue) for the target version, and diff that
against what this repo's module already declares as a prerequisite in its own
`README.md`. A new dependency the module doesn't yet satisfy is a structural gap,
not a config typo — it changes the module's own `dependsOn` story
(`projectBrief.md#dependencies`) and needs a decision, not just a manifest edit.
