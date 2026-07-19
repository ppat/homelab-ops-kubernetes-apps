---
name: upgrade-chart-version
description: >
  Use this skill when a Helm chart/app upgrade in this repo needs a human-designed
  fix, not just a version bump — Renovate already tried and it broke (a renovate PR
  is red, a chart/CRD major bump failed CI, values got restructured upstream, a new
  CRD or a new required dependency appeared, or a deprecated feature is being
  removed). Covers finding what actually changed between two chart/app versions,
  locating every place this repo configures the module (HelmRelease
  values/valuesFrom/postRenderers, Kustomization patches/postBuild substitutions),
  checking CRD schema changes for downstream CR breakage, reworking the module's
  chainsaw test suite, and scoping (but not making) the production rollout in the
  sibling clusters repo. Do NOT use this for a bump that would just work with
  Renovate — this skill is specifically for the upgrades that don't.
---

# Upgrading a chart/app version by hand

> **STATUS: DRAFT.** This skill was written from a single worked example (the CNPG
> operator + barman-cloud backup migration, PR #3290 / branch `fix-test-dbs`) and
> has not yet been run against a second, independent upgrade. See **Iteration
> protocol** at the bottom before treating anything here as settled.

Read [`README.md`](../../../README.md) and [`projectBrief.md`](../../../projectBrief.md)
first for the module catalog, the three configuration mechanisms, and the
core/extra dependency rules — this skill assumes that context and does not repeat
it. The module's own `README.md` (`infrastructure/subsystems/<module>/README.md` or
`apps/subsystems/<module>/README.md`) has its specific Dependencies section
(Required By / Depends On) — read that too before touching it.

## Why this is a skill and not "just bump the version"

This skill only gets invoked once it's already established that Renovate's own
bump won't just work — either it already failed, or the bump is one you already
know needs judgment (a major version, a chart with a track record of breaking
changes). Don't spend a step re-confirming that; take it as given and go straight
to finding *why* it needs help: a values key moved, a CRD's schema changed in a
way that breaks an existing CR, the chart now needs a resource this repo doesn't
have yet (a database, a cert-manager Issuer, a new HelmRepository), or the app
deprecated/removed something this repo's manifests still use. Finding *which* of
those it is — and finding all of it, not just the first symptom CI shows you — is
the actual work. Guessing costs the same repeated-failed-CI-round-trip cycle this
skill exists to avoid; reading structurally is what actually shortens it.

## The shape of the work

1. **Scope the diff — by chart version, then confirm the app version it ships.**
   This repo's HelmReleases almost always pin only `spec.chart.spec.version`; a
   separate app-version field is rare. Don't assume the two move in lockstep,
   though — confirm what app version the target chart version actually ships
   (its `Chart.yaml` `appVersion:`, or `helm show chart`) rather than inferring it
   from the version number alone. See **references/research-and-diagnosis.md**.
2. **Fan out research in parallel, before writing anything.** This is retrieval,
   not judgment, and it's independent per topic — cheap to parallelize, cheap to
   run on a smaller model. See **Delegating to subagents** below.
3. **Consume release notes, `values.yaml`, `Chart.yaml`, and the CRD spec as
   separate sources — don't conflate them.** Each tells you something the others
   don't. The most direct way to see what changes *for this repo's actual
   config* is `helm template` old-vs-new with this module's real values, not a
   raw values/templates diff. See **references/research-and-diagnosis.md** for
   the full method, including when a chart-repo clone (for comments a rendered
   values dump strips) beats rendering.
4. **Enumerate every configuration surface this repo actually uses for the
   module** — including any `components/*` layered on in production even if
   untested — not just the obvious one. See **references/config-surfaces.md**.
5. **If the chart installs a CRD, gate the investigation on actual usage
   first** — grep for the `kind`/`apiVersion` across this repo and the clusters
   repo before spending any effort on whether its schema changed. If it's used
   and the schema did change, the bootstrap CRDs bundle
   (`infrastructure/bootstrap/crds/`) almost certainly needs the same version
   bump. Also check whether the new version needs (or drops) a dependency this
   repo doesn't declare yet. See **references/research-and-diagnosis.md**.
6. **Make the change, then reproduce locally before pushing to CI.** A `kustomize
   build` or `helm template` that runs in seconds beats a CI round trip that
   takes 10 minutes and returns a large, non-cacheable log dump. See
   **references/cost-tradeoffs.md** for why this isn't just "be careful" advice —
   it's the correct trade given how the costs actually stack up here.
7. **Update the module's chainsaw suite** (`ci/test/<module>/`) to exercise
   whatever changed — reuse `ci/test/chainsaw/assertions/*-ready.yaml` and an
   existing similar module's prerequisite pattern before writing anything new.
8. **Push, watch CI, and diagnose failures by narrowing with evidence, not by
   guessing and re-pushing.** Every failure has a specific cause that this repo's
   tooling can usually surface directly — you don't need this skill to tell you
   *what* is wrong with a given error, only *how to go get the evidence* that
   tells you (and how to keep that evidence-gathering from flooding your own
   context). See **references/diagnostic-approach.md**.
9. **Scope the clusters-repo rollout — don't do it in this PR.** Check
   `../homelab-ops-kubernetes-clusters/clusters/*/kustomizations/` for how the
   module is consumed today (tag pin, `dependsOn`, `postBuild.substitute`) so you
   know what the follow-up needs, but land it separately once this repo releases.

## Delegating to subagents — two distinct reasons, don't conflate them

**Coverage delegation** (steps 2 and 4): "what files exist," "what does this
HelmRelease currently set," "which consumers use this Kind," "how does the
clusters repo reference this module today" are enumeration, not reasoning. A
cheap/fast-model subagent handles these as well as the main model, at a fraction
of the cost — the value is in coverage (did we check every consumer, every
configuration mechanism, every clusters-repo reference), not in insight. Spawn
`Agent` calls in a **single message** (so they run in parallel), one per
independent research surface, e.g.:

- "explore the module's current chart/CRD version and every HelmRelease/HelmRepository file"
- "explore `components/` for every db/cache/storage-related Kustomize component touching this module, and whether any consuming cluster applies it in production"
- "explore every consumer app/infra subsystem that uses this module, quoting their current config"
- "explore `../homelab-ops-kubernetes-clusters/clusters/*/` for how this module is referenced today"

Pass `model: "haiku"` (or the fastest model available) on these — they're
read-only `Explore`-style sweeps with a clear "report back what you found"
contract, not open-ended design work.

**Context-isolation delegation** (step 8, and anywhere a fetch returns a large
payload): `gh run view --log-failed` on a real CI run is the main case in this
repo — there's no local cluster, so a chainsaw test's `describe`/`get`/
`podLogs`/`events` output only exists as whatever got captured into that CI log,
never as a command you can run directly. That log can run to thousands of lines
that are mostly noise relative to the one answer you need — and because that
content is new every time, it's never a prompt-cache hit, so once it's in your
context it's paid for in full and stays there. Delegate the fetch itself to a
subagent with a specific question ("find the actual underlying error and the
endpoint/config it used"), and have it return the extracted answer **plus** its
own brief read of anything else in the log that looked notable — it already paid
the cost of reading the whole dump, so let that coverage benefit you even where
you didn't think to ask. This is **not** about the task being easy — a genuinely
hard diagnosis can still get this treatment, with the subagent running on the
main/reasoning model rather than a cheap one. The two delegation reasons compose
independently: a fetch can be both noisy *and* need a strong model to interpret,
in which case delegate to a strong-model subagent anyway, just to keep the raw
payload out of the main thread. See **references/diagnostic-approach.md** and
**references/cost-tradeoffs.md** for the reasoning behind each axis.

Reserve the main-thread reasoning model for the steps that need actual judgment
that benefits from you keeping full session context: deciding whether a
release-note callout applies to how *this* repo uses the resource, weighing
competing hypotheses for a live failure, and writing the actual manifests. Don't
fan a live diagnosis *decision* out to a cheap model just because it's a
subagent call — narrowing between competing hypotheses is where a weaker model's
answer isn't trustworthy enough to act on, and re-diagnosing after a wrong turn
costs more than the model-tier savings.

## Reference files

| File | Read it for |
| --- | --- |
| `references/research-and-diagnosis.md` | Release notes vs. `values.yaml` vs. `Chart.yaml` vs. CRD spec — what each source actually tells you; the `helm template` old-vs-new diffing method; when a chart-repo clone beats a rendered dump |
| `references/config-surfaces.md` | Every place a module's config can live in this repo, and how to grep for each one exhaustively |
| `references/diagnostic-approach.md` | The evidence-gathering tools this repo actually has (CI log fetching, local repro, secret/state comparison) and the general narrow-before-you-fix pattern — deliberately not a symptom-lookup table; the specific hypothesis for a specific error is yours to form each time |
| `references/cost-tradeoffs.md` | When upfront token spend (deeper research, local repro, an instrumented diagnostic commit) lowers total session cost, grounded in how prompt caching and CI round-trip cost actually work |

## Iteration protocol

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
