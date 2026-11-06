# Checks between research and plan

The research report (step 3) says what changed upstream. These checks turn that into what
it means for this repo and the clusters that consume it.

## Past CI runs are not research material

Do not inspect this repo's GitHub Actions history (an open Renovate PR's failed checks, a
previous manual attempt's log, other branches' CI state) to scope the upgrade or decide
what to research. None of it says what changed between versions. At best it says that one
attempt failed, which is not the same question as why, and reading it costs real context
for no research value. Scope the upgrade from the research report, not from what a bot's PR
proposed or how its CI went.

A past or concurrent run's result becomes legitimate evidence only later, when diagnosing a
failure in your own run. See
[diagnostic-approach.md](diagnostic-approach.md#recognizing-a-pre-existing-or-unrelated-ci-failure).
Even there, the subagent watching your run checks it to rule an environmental cause in or
out, after there is a failure to explain.

## App docs can describe manual steps the chart already automates

An app's own operational docs (clustering, HA, leader election) are often written for
someone running the software directly on hosts, not through this chart. "You must
configure X, Y and Z for HA" can describe exactly what the chart already wires into its
defaults or templates. Treating those steps as a checklist to replicate in values adds
real, unneeded complexity.

This showed up with Loki. grafana.com's "HA monolithic" doc describes manually configuring
a `memberlist` ring, a dedicated `horizontal_scaling_mode: main` compactor and a Thanos
object-storage client. The chart's templates already wired `memberlist.join_members`
unconditionally, the compactor already elected a single leader through its own ring (with
`horizontal_scaling_mode` defaulting to `disabled`, an optional work-distribution feature
rather than a safety requirement), and Thanos objstore is an unrelated alternative storage
client. None of the doc's extra config was needed.

When app docs describe manual coordination or HA setup, check what the chart's templates
render by default before adding anything.

## Downstream CR breakage

**Gate the CRD investigation on actual usage first.** Before asking whether a CRD's schema
changed, check whether this repo or the clusters repo creates any resource of that kind at
all, by searching for the `kind:` across `apps/`, `infrastructure/`, `components/` and
`../homelab-ops-kubernetes-clusters/clusters/`. If nothing uses it, there is nothing to
check. If something does, compare the CRD pair the research produced for every field those
resources set, looking for renames, restructuring, new required fields and versions no
longer served.

**If a CRD we use changed, the bootstrap CRD bundle almost certainly needs the matching
bump.** [`DESIGN.md#bootstrap-and-crds`](../../../../DESIGN.md#bootstrap-and-crds) covers
what `infrastructure/bootstrap/crds/` is for. Chainsaw suites are one more place it
matters, because a fresh kind cluster is a first-time setup too. A live cluster's Helm
release keeps its own CRDs current, so the bundle only matters in those scenarios, but in
them an out-of-date bootstrap CRD is a gap that surfaces only once you test the upgrade.

## New or dropped dependencies

Compare the TO chart's `dependencies` and the app's stated prerequisites (TLS, a database,
a message queue) with what the module's own `README.md` declares. A new dependency the
module does not yet satisfy is a structural gap, not a config typo. It changes the module's
`dependsOn` story ([`DESIGN.md#dependencies`](../../../../DESIGN.md#dependencies)) and needs
a decision, not just a manifest edit.
