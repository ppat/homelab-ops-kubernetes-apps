---
name: upgrade-chart-version
description: >
  Use this skill when a Helm chart/app upgrade in this repo needs a
  human-designed fix, not just a version bump. Either Renovate's own bump already
  failed, or the bump is one you already know needs judgment (a major version,
  a chart/CRD with a track record of breaking changes, a deprecated feature
  being removed, a new required dependency). Runs a fixed, ordered research →
  plan → implement → verify → rollout-scoping procedure, delegating research
  and CI-log analysis to subagents. Do NOT use this for a bump that would just
  work with Renovate. This skill is specifically for the ones that don't.
---

# Upgrading a chart/app version by hand

## Required Procedure: Execute Every Step, In Order

Before anything else, read [`README.md`](../../../README.md) and
[`DESIGN.md`](../../../DESIGN.md) for the module catalog, the three configuration
mechanisms, and the core/extra dependency rules, plus the target module's own `README.md`
(`infrastructure/subsystems/<module>/README.md` or `apps/subsystems/<module>/README.md`)
for its Dependencies section (Required By / Depends On). These reads are quick, local and
cheap, so do them directly.

Then, before any other file read, grep, or subagent spawn, write the nine steps below as a
checklist in your working notes, one item per step, in order. Copy each step's `Who` into
its item, not just the step's title. Mark an item in progress before starting its step, and
done before moving to the next.

This isn't ceremony. The steps below are a specification of who does what, not a script
your next tool call automatically follows. A request like "upgrade X to latest"
pattern-matches straight to "go inspect X's files", which is exactly the shortcut that
skips step 1's mandatory delegation. Once the steps are a written checklist, "which step
am I on, and does it require delegation" becomes a fact you can check, not something
reconstructed from scrollback, which gets unreliable fast once background research agents
start reporting back interleaved with your own tool calls.

1. Research our usage and configuration of the helm chart in question
   - Who:
     - Delegate to subagent (Mandatory)
   - What:
     - Every configuration surface affecting this helm chart (see
       **references/config-surfaces.md**), including but not limited to:
       - HelmRelease values
       - HelmRelease patches or postRender configurations
       - Kustomization patches or post build variables
       - Kustomize components
       - Explicitly referenced versions (of charts, docker images, modules, etc)
       - Differences in cfg between module and chainsaw tests
       - Differences between module and production (i.e. clusters repo cfg)
       - List of CRDs (`Group`/`Kind`/`Version`) in use
       - What depends on the chart's behaviour rather than its configuration, such as what
         our chainsaw suites assert about it, and annotations, labels or resources it reads
         from other modules
   - Where:
     - Within this repo & the ../homelab-ops-kubernetes-clusters repo
   - How:
     - Utilize local file reads
     - For each CRD in use, list the CRs we create from it (`rg` for its `kind:` across
       `apps/`, `infrastructure/`, `components/`, `ci/test/` and the clusters repo's
       `clusters/`) and the fields each one sets. Step 3 judges CRD schema changes against those fields
     - Use the cheapest viable LLM model (usually Haiku) for the subagent. This is coverage
       work. The value is in checking every consumer and every configuration mechanism, not
       in judgment. Run one subagent per independent surface, in parallel
     - Response to main should capture
       - all findings covering `What`
       - any additional notable (or unusual) insights
       - post mortem summary of approach taken, what worked, what didn't, what eventually succeeded
       - provide context appropriate sources for all findings and notable insights
2. Determine the range of chart versions affected
   - Who:
     - main loop
   - What:
     - FROM-version:

       ```text
       earliest-of(
         current version from chart reference within module's HelmRelease in this repo,
         chart version corresponding to module version utilized within cluster repo
       )
       ```

     - TO-version:
       - There is nothing to interpret here. If the user said to upgrade to an explicit
         version, pick that. If the user said latest, that is also clear cut.
3. Research what changed between FROM and TO versions
   - Who:
     - Delegate to subagent (Mandatory)
   - What:
     - Helm Chart itself (values.yaml, Chart.yaml, rendered chart w/ defaults,
       rendered chart with current effective HelmRelease values, app versions corresponding
       to chart versions in question, a list of CRDs maintained by the Helm Chart)
     - Release Notes of chart
   - Where:
     - External sources
   - How:
     - The subagent runs the [research-version-changes](../research-version-changes/SKILL.md)
       skill for the chart, FROM and TO. That skill knows nothing about this repo, so hand it
       everything it judges against
       - step 1's findings, as its usage context, so it judges every change against what we
         actually configure
       - the effective HelmRelease values, as one values file per layer in merge order.
         Inline `spec.values` (`yq '.spec.values'`), ConfigMap-sourced `spec.valuesFrom`,
         each component overlay, and the consuming cluster's patches on the HelmRelease. Say
         which configuration the files describe (the module, its chainsaw test, or a
         cluster). Name what a file cannot carry (Secret-sourced `spec.valuesFrom`,
         `spec.postRenderers`) so the report lists it as not covered
       - the post-build variables step 1 found, as `--var` values, and the Kubernetes version
         and API versions served (`group/version`) of the clusters that run it, where known
       - that Renovate's bump failed, when it did. The fact only, not its logs
     - Use the model that skill's Model sizing names for the subagent
     - Response to main should capture
       - all findings covering `What` (the skill's report, plus the paths of its output
         directories, which later steps read directly)
       - any additional notable (or unusual) insights
       - post mortem summary of approach taken, what worked, what didn't, what eventually succeeded
       - provide context appropriate sources for all findings and notable insights
4. Decide whether further research is warranted
   - Who:
     - main loop
   - What:
     - Is app version change research warranted?
     - Is research of CRD specs warranted?
     - Is a specific data or infrastructure migration necessary?
   - Where:
     - Use knowledge acquired from previous steps
   - How:
     - Do we have reason to believe that significant changes were made between app versions that
       could affect our task outcome negatively if we don't review? The research report's
       Coverage section gives the app version range and whether the chart notes appear to
       cover it
     - Did any of the CRDs that we actually use include any changes? Sometimes CRDs get additive
       changes that don't result in version changes, so as long as there were changes, it might be
       useful to review. Step 3's chart output marks each CRD as changed or not
     - Do we have reason to believe that special migration steps or intervention are necessary
       for data or infrastructure that's not already captured by the chart or app itself?
     - See **references/research-to-plan.md** for what the findings mean for this repo
5. Conduct further research if deemed warranted
   - If:
     - Gate run on whether step 4 determined this is necessary
   - Who:
     - Delegate to subagent (Mandatory)
   - What:
     - What was deemed warranted in step 4
   - Where:
     - External sources
   - How:
     - same as `How` of step 3. App version research is the research-version-changes skill
       again, for the app's own repo and tag family over the app version range. CRD spec
       research reads the CRDs step 3's chart output already holds for both versions
6. Synthesize all researched insights into an actionable upgrade plan
   - Who:
     - main loop
   - What:
     - create an upgrade plan that spans
       - chart versions
       - chart configuration and customizations in all its forms (see
         **references/config-surfaces.md**) including but not limited to
         configmaps and secrets
       - how downstream use of chart provided constructions like CRs based on CRDs
         need adaptation, if any
       - changes to tests
       - did chart essentially change the overall shape of infrastructure that requires a deep
         re-think of downstream consequences or implications
   - Where:
     - Use knowledge and insights from previous steps, and **references/research-to-plan.md**
7. Execute the plan and make the necessary changes
   - Who:
     - main loop
   - What:
     - plan from step 6
   - Where:
     - this repository
   - How:
     - create branch and implement plan's changes scoped for entirety of this repo (version, cfg,
       tests, etc)
     - reproduce locally before pushing to CI. A `kustomize build` or `helm template` that runs
       in seconds beats a CI round trip that takes 10 minutes and returns a large, non-cacheable
       log dump. See **references/cost-tradeoffs.md** for why
     - be acutely aware that you may also need to adjust the plan as you go along. keep track.
8. Trigger CI test runs, diagnose failures, fix and loop till success
   - Who:
     - change commit, push and ci trigger -> main loop
     - ci run watch, results log analysis, insight generation and root cause identification ->
       Delegate to subagent (Mandatory)
     - ci run failure insights driven changes and looping this step till success -> main loop
   - What:
     - Implementation according to plan
   - Where:
     - This repository
   - How:
     - Commit to branch, push and create PR to trigger CI run
     - Diagnose failures by narrowing with evidence, not by guessing and re-pushing. Every
       failure has a specific cause that this repo's tooling can usually surface directly
     - Ensure the CI watch itself also occurs within the subagent. Don't poll it yourself
       while you wait, and don't wait to delegate until a failure shows up.
     - See **references/diagnostic-approach.md**
     - In this scenario, the subagent may need a more capable model than the cheapest, fastest
       one (say maybe Sonnet instead of Haiku) as it needs to perform root cause analysis
     - When a test run fails, do not fix within the subagent itself. Subagents should review ci
       run logs, derive insights and perform root cause identification and hand off the
       resulting findings to main loop
     - The same subagent, not a fresh one, fetches each failed run's log. Its response to main
       should capture
       - the extracted answer to the specific question you asked
       - its own read of anything else in the log that looked notable
       - post mortem summary of approach taken, what worked, what didn't, what eventually succeeded
9. Record the clusters-repo rollout as a github issue, only if needed
   - Who:
     - main loop
   - What:
     - Corresponding parts of plan from step 6 w.r.t. rollout to production
   - Where:
     - clusters repo (`../homelab-ops-kubernetes-clusters`)
   - How:
     - Gate this on step 6's plan. Does the clusters repo need anything beyond the version
       bump itself, such as a patch targeting a value path the upgrade changed, a new required
       substitution variable, a new dependency, or a new secret/resource? If nothing in the plan
       required a clusters-repo change, Renovate's own routine bump PR will pick up the new
       released tag with no manual step. Say so explicitly and skip filing an issue.
     - Only when the plan did identify something Renovate's routine bump
       can't do alone, create a github issue (under clusters repo) that
       captures in detail what needs to happen within the clusters repo, plus
       a short but descriptive summary of what was implemented in this repo.

## Why this is a skill and not "just bump the version"

This skill only gets invoked once it's already established that Renovate's own bump won't
just work. Either it already failed, or the bump is one you already know needs judgment (a
major version, a chart with a track record of breaking changes). Take it as given and go
straight to finding *why* it needs help. Typically a values key moved, a CRD's schema changed
in a way that breaks an existing CR, the chart now needs a resource this repo doesn't have yet
(a database, a cert-manager Issuer, a new HelmRepository), or the app deprecated or removed
something this repo's manifests still use. Finding *which* of those it is, and finding all
of it, not just the first symptom CI shows you, is the actual work. Guessing costs the same
repeated-failed-CI-round-trip cycle this skill exists to avoid. Reading structurally is
what actually shortens it.

## Reference files

| File | Read it for |
| --- | --- |
| [research-version-changes](../research-version-changes/SKILL.md) | The skill steps 3 and 5 run, covering what each upstream source tells you, the scripts that fetch release notes and diff chart versions, and the report it returns |
| `references/research-to-plan.md` | What the research means for this repo, covering why past CI runs are not research material, which version our HelmReleases pin, keeping worth-adopting items out of the plan, the bootstrap CRDs when a CRD we use changed, new or dropped dependencies |
| `references/config-surfaces.md` | Every place a module's config can live in this repo, and how to grep for each one exhaustively |
| `references/diagnostic-approach.md` | The evidence-gathering tools this repo has (CI log fetching, local repro, secret/state comparison) and the general narrow-before-you-fix pattern. Deliberately not a symptom-lookup table. The specific hypothesis for a specific error is yours to form each time |
| `references/cost-tradeoffs.md` | When upfront token spend (deeper research, local repro, an instrumented diagnostic commit) lowers total session cost, grounded in how prompt caching and CI round-trip cost actually work |

To change this skill, read [MAINTAINER.md](MAINTAINER.md) first.

## Before you touch anything

If you haven't written the checklist of all 9 steps in
[Required Procedure](#required-procedure-execute-every-step-in-order), stop and do that now,
before another file read, grep, or subagent spawn. This is the one failure mode that has
actually derailed a run of this skill. Everything else here is recoverable mid-session.
Skipping the checklist at the start isn't, because by the time it's noticed, research has
already happened in the main loop instead of a subagent, and has to be thrown away and
redone.
