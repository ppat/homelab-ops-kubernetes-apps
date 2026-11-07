# Maintaining upgrade-chart-version

This file is for changing the skill, not for running it. Nothing here is loaded when the
skill runs.

## Where learnings come from

The best source of a learning is a session that did an upgrade with the skill. It holds the
ground truth of what actually worked, reformulated after what didn't. Ask it directly what
the skill should say that it currently doesn't, or says wrong, rather than re-deriving that
from the diff alone. Fold confirmed learnings into the relevant `references/*.md` file in
preference to growing `SKILL.md`, which is loaded on every run.

Validate a change by running the updated skill fresh, in a new session, on a real pending
upgrade. The session that wrote a change fills its gaps from its own context and cannot see
them.

Learnings about finding out what changed upstream (sources, fetching, classifying, the
report) belong to [research-version-changes](../research-version-changes/SKILL.md), not here.

## What's worth adding to the skill, vs. what isn't

Not everything a past session learned belongs here. A skill that accumulates every specific
fact from every upgrade stops being general and starts being that one session's runbook
wearing a generic skill's name. Trust the model running a future upgrade to work out
app/chart-specific behavior on its own when it encounters it. That's a normal,
well-equipped part of doing the work, not a gap this skill needs to pre-fill. Only capture a
specific learning when it's *extensible*, meaning illustrative of how to handle a class of
unusual situation that will recur under a different name next time, not just a fact about
one chart. Before folding a learning in, check it against these:

- **Transferable mechanism, not a one-off fact.** "Flux applies `spec.patches` before
  `postBuild.substitute`" belongs, because it's a property of Flux itself, true for any
  module. A specific fact like "the barman-cloud sidecar restarts the instance pod" doesn't
  belong as a rule. It's fine to keep *briefly, as a named example* illustrating a
  transferable point, e.g. "a chart's own documented behavior can interact badly with a
  one-shot resource created around the same reconcile, which showed up once as [CNPG's
  sidecar-injection restart racing a one-shot Backup]", because the pattern ("check whether
  a chart's normal startup/upgrade behavior can race something you're about to create
  alongside it") generalizes even though the CNPG specifics don't. The test is whether the
  *pattern* the example demonstrates would help with a different chart's unrelated bug, not
  whether the example itself is memorable.
- **A method, not a conclusion.** "Render both versions with this module's effective values
  and diff them" is a transferable method. "CNPG 1.30 made `ScheduledBackup.spec.cluster`
  immutable" is a conclusion about one chart's one version with no generalizable pattern
  behind it. It belongs in the PR or commit that made that specific change (per this repo's
  own comment-authoring convention), not here.
- **Don't restate what already lives elsewhere.** If it's already covered by
  `DESIGN.md`/`README.md`/this repo's `CLAUDE.md`, link to it, don't duplicate it. This skill
  already does that for the configuration mechanisms, the bootstrap-CRDs purpose, and the
  comment-authoring rules. A skill that re-explains what CLAUDE.md already says just gives
  the same instruction two places to drift out of sync.
- **A diagnostic *approach*, not a diagnostic *answer*.** The pattern "an error that's a
  catch-all for multiple causes needs a disambiguating step before you patch anything" is
  worth keeping as a named, reusable move. The specific fact "`SignatureDoesNotMatch` from
  barman-cloud can mean a trailing-dot endpoint breaking SigV4 signing" isn't something to
  add as its own entry. That's the kind of thing this skill should trust the model to work
  out fresh each time, the same way `references/diagnostic-approach.md` already argues.
  Resist the pull to build a symptom-lookup table one entry at a time. That's a different
  (and much larger, and eventually stale) document than this skill is trying to be.
- **Don't assume unstated constraints generalize.** A correction like "we almost never set
  both chart and app version" is about *this repo's actual conventions*. Capture it as a
  stated fact, not as something to re-derive with hedging every time ("often",
  "sometimes", "it depends"). But be wary of the opposite mistake. Don't state a *syntax*
  convention (a branch/tag naming scheme, a specific CLI invocation) as universal when it's
  actually just what one chart repo happens to do. Check before generalizing, the same way
  this skill avoids being prescriptive about tag naming precisely because different chart
  repos use different schemes.
- **A situation is not a section.** A run will meet situations the steps don't spell out (an
  image rather than a chart, an existing pull request to fix, a CRD-only bump). The steps
  already say what each one is for. Adding a playbook per situation turns the skill into a
  list of scenarios. Add text only when a situation exposed a wrong statement, a
  contradiction, or a transferable mechanism.
