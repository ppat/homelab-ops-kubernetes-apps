---
name: upgrade-chart-version
description: >
  Use this skill when a Helm chart/app upgrade in this repo needs a
  human-designed fix, not just a version bump — Renovate's own bump already
  failed, or the bump is one you already know needs judgment (a major version,
  a chart/CRD with a track record of breaking changes, a deprecated feature
  being removed, a new required dependency). Runs a fixed, ordered research →
  plan → implement → verify → rollout-scoping procedure, delegating research
  and CI-log analysis to subagents. Do NOT use this for a bump that would just
  work with Renovate — this skill is specifically for the ones that don't.
---

# Upgrading a chart/app version by hand

## Required Procedure — Execute Every Step, In Order

Before anything else: read [`README.md`](../../../README.md) and
[`projectBrief.md`](../../../projectBrief.md) for the module catalog, the three
configuration mechanisms, and the core/extra dependency rules, plus the target
module's own `README.md` (`infrastructure/subsystems/<module>/README.md` or
`apps/subsystems/<module>/README.md`) for its Dependencies section (Required By
/ Depends On) — quick, local, cheap, do these reads directly.

Then, before any other file read, grep, or subagent spawn: call `TaskCreate`
once per step below (9 tasks, in order), copying that step's delegation
requirement into the task's *description*, not just its title. Work through
them via `TaskUpdate` — `in_progress` before starting a step, `completed`
before moving to the next.

This isn't ceremony. The steps below are a specification of who does what, not
a script your next tool call automatically follows — and a request like
"upgrade X to latest" pattern-matches straight to "go inspect X's files,"
which is exactly the shortcut that skips step 1's mandatory delegation. Once
the steps are tracked tasks, "which step am I on, and does it require
delegation" becomes a fact you can check against tool state — not something
reconstructed from scrollback, which gets unreliable fast once background
research agents start reporting back interleaved with your own tool calls.

1. Research our usage and configuration of the helm chart in question
   - Who:
     - Delegate to subagent (Mandatory; see **Delegating to subagents** below)
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
   - Where:
     - Within this repo & the ../homelab-ops-kubernetes-clusters repo
   - How:
     - Utilize local file reads
     - Use the cheapest viable LLM model (usually Haiku) for the subagent
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
         earliest-of(
           current version from chart reference within module's HelmRelease in this repo,
           chart version corresponding to module version utilized within cluster repo
         )
     - TO-version:
       - There is nothing to interpret here, if a user said to upgrade to an
         explicit version, pick that. If the user said, latest then that is also
         clear cut.
3. Research what changed between FROM and TO versions
   - Who:
     - Delegate to subagent (Mandatory; see **Delegating to subagents** below)
   - What:
     - Helm Chart itself (values.yaml, Chart.yaml, rendered chart w/ defaults,
       rendered chart with current effective HelmRelease values, app versions corresponding
       to chart versions in question, a list of CRDs maintained by the Helm Chart)
     - Release Notes of chart
   - Where:
     - External sources
   - How:
     - Research as described within **references/research-and-diagnosis.md**
     - Use the cheapest viable LLM model (usually Haiku) for the subagent
     - Fan out to subagents for each `What` so that research can run in parallel
     - Response to main should capture
       - all findings covering `What`
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
       could affect our task outcome negatively if we don't review?
     - Did any of the CRDs that we actually use include any changes? Sometimes CRDs get additive
       changes that don't result in version changes, so as long as there were changes, it might be
       useful to review
     - Do we have reason to believe that special migration steps or intervention are necessary
       for data or infrastructure that's not already captured by the chart or app itself?
5. Conduct further research if deemed warranted
   - If:
     - Gate run on whether step 4 determined this is necessary
   - Who:
     - Delegate to subagent (Mandatory; see **Delegating to subagents** below)
   - What:
     - What was deemed warranted in step 4
   - Where:
     - External sources
   - How:
     - same as `How` of step 3
6. Synthesize all researched insights into an actionable upgrade plan
   - Who:
     - main loop
   - What:
     - create an upgrade plan that spans,
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
     - Use knowledge and insights from previous steps
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
       Delegate to subagent (Mandatory; see **Delegating to subagents** below)
     - ci run failure insights driven changes and looping this step till success -> main loop
   - What:
     - Implementation according to plan
   - Where:
     - This repository
   - How:
     - Commit to branch, push and create PR to trigger CI run
     - Diagnose failures by narrowing with evidence, not by guessing and re-pushing. Every
       failure has a specific cause that this repo's tooling can usually surface directly
     - Ensure the CI watch itself also occurs within the subagent, don't poll it yourself
       while you wait, and don't wait to delegate until a failure shows up.
     - See **references/diagnostic-approach.md**
     - In this scenario, the subagent may need a more capable model than the cheapest, fastest
       one (say maybe Sonnet instead of Haiku) as it needs to perform root cause analysis
     - When a test run fails, do not fix within the subagent itself — subagents should review ci
       run logs, derive insights and perform root cause identification and hand off the
       resulting findings to main loop
9. Record the clusters-repo rollout as a github issue — only if needed
   - Who:
     - main loop
   - What:
     - Corresponding parts of plan from step 6 w.r.t. rollout to production
   - Where:
     - clusters repo (`../homelab-ops-kubernetes-clusters`)
   - How:
     - Gate this on step 6's plan: does the clusters repo need anything beyond
       the version bump itself — a patch targeting a value path the upgrade
       changed, a new required substitution variable, a new dependency, a new
       secret/resource? If nothing in the plan required a clusters-repo
       change, Renovate's own routine bump PR will pick up the new released
       tag with no manual step — say so explicitly and skip filing an issue.
     - Only when the plan did identify something Renovate's routine bump
       can't do alone, create a github issue (under clusters repo) that
       captures in detail what needs to happen within the clusters repo, plus
       a short but descriptive summary of what was implemented in this repo.

## Why this is a skill and not "just bump the version"

This skill only gets invoked once it's already established that Renovate's own
bump won't just work — either it already failed, or the bump is one you already
know needs judgment (a major version, a chart with a track record of breaking
changes). Take it as given and go straight to finding *why* it needs help: a
values key moved, a CRD's schema changed in a way that breaks an existing CR,
the chart now needs a resource this repo doesn't have yet (a database, a cert-manager
Issuer, a new HelmRepository), or the app deprecated/removed something this repo's
manifests still use. Finding *which* of those it is — and finding all of it, not
just the first symptom CI shows you — is the actual work. Guessing costs the same
repeated-failed-CI-round-trip cycle this skill exists to avoid; reading structurally
is what actually shortens it.

## Delegating to subagents — two distinct reasons, don't conflate them

**Coverage delegation** (steps 1, 3 and 5):

- Research of local files within repositories and external sources to capture factual insights via
  simple tool calls, local file reads or simple log analysis. A cheap/fast-model subagent handles
  these as well as the main model, at a fraction of the cost — the value is in coverage (did we check
  every consumer, every configuration mechanism, every clusters-repo reference, every version for
  release notes, every helm chart templated out, etc), not in deep insight, judgement or open ended
  design or planning effort. Spawn `Agent` calls so they run in parallel, one per independent research
  surface.

**Context-isolation delegation** (step 8, and anywhere a fetch returns a large
payload):

- `gh run view --log-failed` on a real CI run is the main case in this repo. That log can run to
  thousands of lines that are mostly noise relative to the one answer you need — and because that
  content is new every time, it's never a prompt-cache hit, so once it's in your
  context it's paid for in full and stays there.
- If the run fails, that same subagent (not a fresh one) fetches the log and finds a specific
  question ("find the actual underlying error and the endpoint/config it used"), and returns the
  extracted answer, its own brief read of anything else in the log that looked notable, and a short
  postmortem of its own approach — what it tried that didn't pan out, what eventually worked. It already
  paid the cost of reading the whole dump, so let all three of those benefit you, including the parts
  you didn't think to ask about. This is **not** about the task being easy — a genuinely hard diagnosis
  can still get this treatment, with the subagent running on a better than the most cheapest model. The
  two delegation reasons compose independently: a fetch can be both noisy *and* need a strong model to
  interpret, in which case delegate to a strong-model subagent anyway, just to keep the raw payload
  out of the main thread. See **references/diagnostic-approach.md** and **references/cost-tradeoffs.md**
  for the reasoning behind each axis.

Reserve the main-thread reasoning model for the steps that need actual judgment that benefits from
you keeping full session context, overall planning, design, implementation and orchestration of the
task at hand.

## Reference files

| File | Read it for |
| --- | --- |
| `references/research-and-diagnosis.md` | Release notes vs. `values.yaml` vs. `Chart.yaml` vs. CRD spec — what each source actually tells you; the `helm template` old-vs-new diffing method; when a chart-repo clone beats a rendered dump |
| `references/config-surfaces.md` | Every place a module's config can live in this repo, and how to grep for each one exhaustively |
| `references/diagnostic-approach.md` | The evidence-gathering tools this repo actually has (CI log fetching, local repro, secret/state comparison) and the general narrow-before-you-fix pattern — deliberately not a symptom-lookup table; the specific hypothesis for a specific error is yours to form each time |
| `references/cost-tradeoffs.md` | When upfront token spend (deeper research, local repro, an instrumented diagnostic commit) lowers total session cost, grounded in how prompt caching and CI round-trip cost actually work |

## Iteration protocol

> **STATUS: DRAFT.** This skill has gone through three worked examples so far —
> Loki (the upgrade that produced the first draft), Bitwarden (first fresh-session
> run, learnings folded back in), and Traefik (the first run that executed the
> procedure cleanly end-to-end, aside from one same-session ordering correction
> that produced the "Required Procedure" section above). Drop this status line
> once two or three more independent upgrades go through it without needing a
> same-session correction.

This skill is being deliberately iterated **across sessions**, not within one —
each upgrade is its own large context window, and folding "run the skill" and
"critique the skill" into the same session defeats the point of writing it down.
The intended loop:

1. Resume a **past** session that did a manual chart/app upgrade (this one, or a
   future one) and ask it directly: *"given everything that happened in this
   session, what should the `upgrade-chart-version` skill draft say that it
   currently doesn't, or say wrong?"* That session has the ground truth of what
   actually worked, reformulated after what didn't — pull from it, don't
   re-derive it from the diff alone.
2. Fold confirmed learnings into this file and its `references/*.md` — prefer
   editing the relevant reference file over growing `SKILL.md` past its current
   size.
3. Try the updated draft **fresh, in a new session**, on a real pending upgrade.
4. Repeat. Drop the "DRAFT" status line at the top once two or three independent
   upgrades have gone through it without needing a same-session correction.

When resuming a past session for step 1, it already has the full context of its
own upgrade — no need to re-explain the skill's purpose, just ask the question
directly and it can compare its own experience against what's written here.

### What's worth adding to the skill, vs. what isn't

Not everything a past session learned belongs here — a skill that accumulates
every specific fact from every upgrade stops being general and starts being that
one session's runbook wearing a generic skill's name. Trust the model running a
future upgrade to work out app/chart-specific behavior on its own when it
encounters it — that's a normal, well-equipped part of doing the work, not a gap
this skill needs to pre-fill. Only capture a specific learning when it's
*extensible*: illustrative of how to handle a class of unusual situation that
will recur under a different name next time, not just a fact about one chart.
Before folding a learning in, check it against these:

- **Transferable mechanism, not a one-off fact.** "Flux applies `spec.patches`
  before `postBuild.substitute`" belongs — it's a property of Flux itself, true
  for any module. A specific fact like "the barman-cloud sidecar restarts the
  instance pod" doesn't belong as a rule, but it's fine to keep *briefly, as a
  named example* illustrating a transferable point — e.g. "a chart's own
  documented behavior can interact badly with a one-shot resource created around
  the same reconcile, which showed up once as [CNPG's sidecar-injection
  restart racing a one-shot Backup]" — because the pattern ("check whether a
  chart's normal startup/upgrade behavior can race something you're about to
  create alongside it") generalizes even though the CNPG specifics don't. The
  test is whether the *pattern* the example demonstrates would help with a
  different chart's unrelated bug, not whether the example itself is memorable.
- **A method, not a conclusion.** "Fetch release notes via `gh release view`,
  it's cheap and structured" is a transferable method. "CNPG 1.30 made
  `ScheduledBackup.spec.cluster` immutable" is a conclusion about one chart's one
  version with no generalizable pattern behind it — it belongs in the PR/commit
  that made that specific change (per this repo's own comment-authoring
  convention), not here.
- **Don't restate what already lives elsewhere.** If it's already covered by
  `projectBrief.md`/`README.md`/this repo's `CLAUDE.md`, link to it, don't
  duplicate it — this file already does that for the configuration mechanisms,
  the bootstrap-CRDs purpose, and the comment-authoring rules. A skill that
  re-explains what CLAUDE.md already says just gives the same instruction two
  places to drift out of sync.
- **A diagnostic *approach*, not a diagnostic *answer*.** The pattern "an error
  that's a catch-all for multiple causes needs a disambiguating step before you
  patch anything" is worth keeping as a named, reusable move. The specific fact
  "`SignatureDoesNotMatch` from barman-cloud can mean a trailing-dot endpoint
  breaking SigV4 signing" isn't something to add as its own entry — that's the
  kind of thing this skill should trust the model to work out fresh each time,
  the same way `references/diagnostic-approach.md` already argues. Resist the
  pull to build a symptom-lookup table one entry at a time; that's a different
  (and much larger, and eventually stale) document than this skill is trying to
  be.
- **Don't assume unstated constraints generalize.** A correction like "we almost
  never set both chart and app version" or "assume all these tools are installed
  locally" is about *this repo's actual conventions and environment* — capture it
  as a stated fact, not as something to re-derive with hedging every time
  ("often," "sometimes," "it depends"). But be wary of the opposite mistake:
  don't state a *syntax* convention (a branch/tag naming scheme, a specific CLI
  invocation) as universal when it's actually just what one chart repo happens to
  do — check before generalizing, the same way this file avoids being
  prescriptive about tag naming precisely because different chart repos use
  different schemes.

## Before you touch anything

If you haven't called `TaskCreate` for all 9 steps in
[Required Procedure](#required-procedure--execute-every-step-in-order), stop
and do that now — before another file read, grep, or subagent spawn. This is
the one failure mode that has actually derailed a run of this skill. Everything
else here is recoverable mid-session; skipping the task list at the start
isn't, because by the time it's noticed, research has already happened in the
main loop instead of a subagent, and has to be thrown away and redone.
