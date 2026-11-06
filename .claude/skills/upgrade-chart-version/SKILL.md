---
name: upgrade-chart-version
description: >
  Use this skill when a Helm chart/app upgrade in this repo needs a
  human-designed fix, not just a version bump. Renovate's own bump already
  failed, or the bump is one you already know needs judgment (a major version,
  a chart/CRD with a track record of breaking changes, a deprecated feature
  being removed, a new required dependency). Runs a fixed, ordered research →
  plan → implement → verify → rollout-scoping procedure, delegating research
  and CI-log analysis to subagents. Do NOT use this for a bump that would just
  work with Renovate. This skill is specifically for the ones that don't.
---

# Upgrading a chart/app version by hand

## Required procedure, every step in order

Before anything else, read [`README.md`](../../../README.md) and
[`DESIGN.md`](../../../DESIGN.md) for the module catalog, the three configuration
mechanisms and the core/extra dependency rules, plus the target module's own `README.md`
(`infrastructure/subsystems/<module>/README.md` or `apps/subsystems/<module>/README.md`)
for its Dependencies section. These reads are quick and local, so do them directly.

Then, before any other file read, grep or subagent spawn, write the nine steps below as a
checklist in your working notes, each with its delegation requirement, and tick each one
off before starting the next. A request like "upgrade X to latest" pattern-matches straight
to "go inspect X's files", which is exactly the shortcut that skips step 1's delegation.
With the checklist written down, which step you are on and whether it is delegated is
something you can check, rather than something reconstructed from scrollback once
background agents start reporting back between your own tool calls. If your next action is
reading the module's files yourself and step 1 is not ticked, you have skipped step 1.
This is the one slip that cannot be recovered mid-run. Context the main loop has read
cannot be removed, so research done there has to be redone in a subagent anyway.

Every delegated step reports, besides its answer, anything notable it was not asked about
and a short account of what it tried that did not work. It has already paid to read the
material, and its dead ends tell you what the evidence cannot show.

1. **Research our usage and configuration of the chart.**
   - Who: a subagent (mandatory), on the cheapest viable model, usually Haiku. This is
     coverage work, where the value is in checking every surface, not in judgment. Run one
     subagent per independent surface, in parallel.
   - What: every configuration surface affecting the chart (see
     [references/config-surfaces.md](references/config-surfaces.md)), including:
     - HelmRelease values, `valuesFrom`, patches and `postRenderers`
     - Kustomization patches and post-build variables
     - Kustomize components
     - explicitly referenced versions (charts, images, modules)
     - differences between the module and its chainsaw test configuration
     - differences between the module and production (the clusters repo)
     - the CRDs in use (group, kind, version)
   - Where: this repo and `../homelab-ops-kubernetes-clusters`, by local file reads.
   - Report: all findings with their sources, anything notable or unusual, and a short
     account of what the subagent tried, what worked and what did not.
2. **Determine the version range.**
   - Who: you.
   - FROM: the earlier of the chart version in this repo's HelmRelease and the chart
     version that ships in the module version the clusters repo deploys.
   - TO: what the user asked for, an explicit version or the latest. Nothing to interpret.
   - Scope from the research, not from past CI runs. See
     [planning-checks.md](references/planning-checks.md#past-ci-runs-are-not-research-material).
3. **Research what changed between FROM and TO.**
   - Who: a subagent (mandatory) that follows the
     [research-version-changes](../research-version-changes/SKILL.md) skill, usually on
     Sonnet (that skill's Model sizing section says why).
   - Hand it the chart, FROM, TO, and step 1's findings as its usage context, so it judges
     relevance against what we actually configure and does not gather that context again.
   - Report: the research-version-changes report file, plus its chart and notes output
     directories, which later steps read directly.
4. **Decide whether further research is warranted.**
   - Who: you, from what steps 1 to 3 found.
   - Is there reason to believe the app changed in ways that could hurt the outcome if left
     unread? The research skill decides whether to read the app's own notes, and the
     report's Coverage section says whether it did.
   - Did any CRD we create resources of change? `crds.txt` in the chart output marks each
     as `schema-changed`, `docs-only`, `added` or `removed`. Additive changes can land
     without a version change, so a `schema-changed` CRD we use is worth reading.
   - Is a data or infrastructure migration needed that the chart or app does not perform
     itself?
5. **Conduct the further research step 4 called for**, if any.
   - Who: a subagent (mandatory). Close the gaps the report's Coverage declares (for app
     releases, run research-version-changes again for the app). For CRD specs, diff the
     pair under `crds/` for each CRD we use, and check every field our CRs set.
   - Report: as step 3.
6. **Synthesize everything into an upgrade plan.**
   - Who: you.
   - The plan covers
     - chart versions
     - chart configuration and customizations in all their forms (see
       [references/config-surfaces.md](references/config-surfaces.md)), ConfigMaps and
       Secrets included
     - how resources built on the chart's CRDs need to adapt
     - changes to tests
     - whether the chart changed the shape of the deployed system enough to need a
       rethink of its downstream consequences
   - Check the plan against [references/planning-checks.md](references/planning-checks.md).
7. **Execute the plan.**
   - Who: you, in this repo.
   - Create a branch, or work on the pull request's own branch when fixing one, and
     implement the plan across the whole repo (versions, config, tests).
   - Reproduce locally before pushing. A `kustomize build` or `helm template` that runs in
     seconds beats a CI round trip that takes ten minutes and returns a large,
     non-cacheable log. See [references/cost-tradeoffs.md](references/cost-tradeoffs.md).
   - Expect to adjust the plan as you go, and keep track of what changed in it.
8. **Run CI, diagnose failures, fix, and repeat until green.**
   - Who: you commit, push and open the PR. A subagent (mandatory) watches the run,
     analyses the logs and identifies root causes. You make the fixes and loop. A failed
     run's log runs to thousands of lines, new on every run, so it stays out of your
     context.
   - Hand the watch to the subagent as soon as the run starts. Do not poll it yourself, and
     do not wait for a failure before delegating.
   - The subagent may need a stronger model than the cheapest (Sonnet rather than Haiku),
     because it performs root-cause analysis. It does not fix anything, because a fix has to
     fit the plan and what earlier steps found, which only you hold. It reports its findings
     back to you.
   - Narrow with evidence rather than guessing and re-pushing. Every failure has a specific
     cause that this repo's tooling can usually surface directly. See
     [references/diagnostic-approach.md](references/diagnostic-approach.md).
9. **Record the clusters-repo rollout as a GitHub issue, only if needed.**
   - Who: you, in `../homelab-ops-kubernetes-clusters`.
   - Gate it on step 6's plan. Does the clusters repo need anything beyond the version
     bump itself, such as a patch targeting a value path the upgrade changed, a new
     substitution variable, a new dependency, or a new secret or resource? If not,
     Renovate's routine bump picks up the new released tag with no manual step. Say so and
     skip the issue.
   - Otherwise file an issue there that details what has to happen in the clusters repo,
     with a short summary of what was implemented here.

## Why this is a skill and not "just bump the version"

This skill runs once it is established that Renovate's own bump will not just work, either
because it already failed or because the bump is known to need judgment. Take that as given
and go straight to finding why it needs help. A values key moved, a CRD's schema changed in
a way that breaks an existing CR, the chart now needs a resource this repo does not have
yet (a database, a cert-manager Issuer, a new HelmRepository), or the app deprecated or
removed something this repo's manifests still use. Finding which of those it is, and
finding all of it rather than the first symptom CI shows, is the actual work. Guessing costs
the repeated failed CI round trips this skill exists to avoid. Reading structurally is what
shortens the loop.

## Reference files

| File | Read it for |
| --- | --- |
| [research-version-changes](../research-version-changes/SKILL.md) | The research skill steps 3 and 5 delegate to, with its sources, scripts, classification and report format |
| `references/config-surfaces.md` | Every place a module's config can live in this repo, and how to search for each one exhaustively |
| `references/planning-checks.md` | Checks to run against the research before planning: CRD breakage and the bootstrap CRDs, new or dropped dependencies, app docs that describe steps the chart already automates, and why past CI runs are not research material |
| `references/diagnostic-approach.md` | The evidence-gathering tools this repo has (CI log fetching, local repro, secret and state comparison) and the narrow-before-you-fix pattern. Deliberately not a symptom lookup table |
| `references/cost-tradeoffs.md` | When upfront spend (deeper research, local repro, an instrumented diagnostic commit) lowers total session cost, grounded in how prompt caching and CI round-trip cost work |

Maintainers changing this skill should read [MAINTAINER.md](MAINTAINER.md).
