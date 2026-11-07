# What the research means for this repo

The research-version-changes report (steps 3 and 5) says what changed upstream and how it
bears on our configuration. This file covers what that research does not decide for you:
how to scope the upgrade, and the consequences for this repo and its consumers that steps
4 and 6 have to work out.

## Historical CI runs are not research material

Don't inspect this repo's past GitHub Actions run history (an open Renovate PR's failed
checks, a previous manual attempt's log, unrelated branches' CI state) as part of scoping
this upgrade or deciding what to research. None of that is signal about what actually
changed in the chart/app between versions. At best it tells you *something* about one
attempt failed, which isn't the same question as *why*, and reading it costs real context
for no research value. Decide the target version and scope from the research (release
notes, `values.yaml`, `Chart.yaml`, the CRD spec), not from what a bot's PR happened to
propose or how its CI happened to go.

The one place a past or concurrent run's pass/fail state is legitimate evidence is later
and narrower, when diagnosing a failure in *your own* current run. See
`diagnostic-approach.md`'s "Recognizing a pre-existing or unrelated CI failure". Even there,
it's something the subagent watching your run checks to rule in or out an environmental
cause, not something to go digging into speculatively before you have a failure to
diagnose.

## App-level docs can describe manual steps the chart has already automated

Many projects' own operational documentation (clustering, HA, leader election) is written
for someone deploying the software directly on hosts, not through this chart. That doc's
"you must configure X, Y, Z for HA" can describe exactly what the chart has already wired
into its defaults or templates, unconditionally, as part of turning the app into a
StatefulSet + Service. Treating the doc's manual-deployment steps as a checklist to
replicate in `values.yaml`, without first checking whether the chart's own templates
already provide the equivalent, adds real, unneeded complexity.

This showed up once with Loki. grafana.com's own "HA monolithic" doc describes manually
configuring a `memberlist` ring, a dedicated `horizontal_scaling_mode: main` compactor
role, and a Thanos object-storage client, all real requirements if running Loki binaries
on raw hosts. Checking the chart's actual templates (not the doc) showed all of that was
already automatic. `memberlist.join_members` is wired into the rendered config
unconditionally regardless of deployment mode. The compactor already self-elects a single
leader via its own ring, with `horizontal_scaling_mode` defaulting to `disabled` (an
*optional* work-distribution feature, not a safety requirement). Thanos-objstore is an
unrelated alternate storage-client implementation. None of the extra config the doc
described was actually necessary.

The generalizable move is to check, when an app's own docs describe manual coordination or
HA setup, what the chart's *templates* actually render by default before treating the doc's
steps as something you need to add. The doc is often written for a different deployment
shape than the one you're using.

## Checking for downstream CR breakage

**Gate the whole CRD investigation on actual usage, first.** If the chart installs a CRD,
before spending any effort on "did its schema change", check whether this repo (or the
clusters repo) creates any CR of that `kind`/`apiVersion` at all, with a quick `rg`/`grep`
for the `kind:` across `apps/`, `infrastructure/`, `components/`, and
`../homelab-ops-kubernetes-clusters/clusters/`. If nothing uses it, there's nothing to
check further. Skip straight past this section. Only if there's a real hit does it become
worth reading the CRD's release notes and schema for what changed, and then checking
whether any field a live CR sets was renamed, restructured, or deprecated.

**If the CRD did change and this repo does use it, the bootstrap CRDs bundle almost
certainly needs the matching version bump too.**
[`DESIGN.md#bootstrap-and-crds`](../../../../DESIGN.md#bootstrap-and-crds) covers what
`infrastructure/bootstrap/crds/` is for and when it's engaged (first-time cluster setup,
disaster recovery). This skill adds one more scenario to that list, chainsaw test
prerequisites, since a fresh kind cluster in CI is functionally a first-time setup too. A
live cluster's Helm release keeps its own CRDs current on every upgrade, so this bundle
only matters for those scenarios. Within them, an out-of-date bootstrap CRD is exactly the
kind of gap that only surfaces once you try to test the upgrade, not during the
chart-version research itself.

## Checking for new/dropped dependencies

Read the chart's `Chart.yaml` (`dependencies:`) and the app's own prerequisite docs (TLS,
a database, a message queue) for the target version, and diff that against what this
repo's module already declares as a prerequisite in its own `README.md`. A new dependency
the module doesn't yet satisfy is a structural gap, not a config typo. It changes the
module's own `dependsOn` story (`DESIGN.md#dependencies`) and needs a decision, not just a
manifest edit.
