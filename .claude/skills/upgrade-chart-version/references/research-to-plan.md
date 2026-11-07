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

## Which version our HelmReleases pin

Our HelmReleases almost always pin only the chart version (`spec.chart.spec.version`) and
rely on the chart to say which app version it ships. Say so when handing step 1's findings
to the research, along with any image tag our values pin.

## Worth adopting is not part of the plan

The research reports features worth adopting on every run. They are not part of the
upgrade plan unless the user asks for them. Report them to the user.

## When a CRD we use changed

The research checks changed CRDs against the CRs we create and the fields they set. What it
does not cover is this repo's own copy of those CRDs.

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

## New or dropped dependencies

When the research reports a new or dropped dependency (a subchart, or an app prerequisite
such as TLS, a database or a message queue), diff it against what this repo's module
already declares as a prerequisite in its own `README.md`. A new dependency
the module doesn't yet satisfy is a structural gap, not a config typo. It changes the
module's own `dependsOn` story (`DESIGN.md#dependencies`) and needs a decision, not just a
manifest edit.
