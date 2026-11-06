# Maintaining upgrade-chart-version

For maintainers of this skill, not for a run of it. Nothing here is loaded when the skill
runs.

## Where a learning goes

The best source of a learning is the session that just ran an upgrade, which holds the
ground truth of what worked once what did not had been ruled out. Ask it directly what the
skill should say that it does not, or says wrong.

| Learning about | Goes in |
| --- | --- |
| Finding out what changed upstream (sources, fetching, classifying, the report) | [research-version-changes](../research-version-changes/SKILL.md), its references, or its [MAINTAINER.md](../research-version-changes/MAINTAINER.md) |
| Where config lives in this repo and the clusters repo | `references/config-surfaces.md` |
| Turning research into a plan | `references/planning-checks.md` |
| Diagnosing a failing run | `references/diagnostic-approach.md` |
| The step order or who does each step | `SKILL.md` |

Prefer a reference file over growing `SKILL.md`, which is loaded on every run.

Validate an edit by running the skill fresh, in a new session, on a real upgrade. The
session that wrote the edit fills gaps from its own context and cannot see them. The same
holds for run feedback: delegates report what would have helped in their situation, so
filter it through the criteria below before it becomes text.

## What's worth adding, and what isn't

A skill that accumulates every fact from every upgrade stops being general and becomes one
session's runbook under a generic name. Trust the model running a future upgrade to work
out chart-specific behaviour when it meets it. Capture a learning only when it is
extensible, meaning it shows how to handle a class of situation that will recur under a
different name. Check each candidate against these:

- **A transferable mechanism, not a one-off fact.** "Flux applies `spec.patches` before
  `postBuild.substitute`" belongs, because it is a property of Flux and true for any module.
  A chart-specific fact belongs only as a brief named example of a transferable pattern,
  and the test is whether the pattern would help with a different chart's unrelated bug.
  CNPG's sidecar injection restarting the instance pod and racing a one-shot `Backup`
  created in the same reconcile is a fine example of "a chart's normal startup behaviour
  can race a resource created alongside it". It is not a rule.
- **A method, not a conclusion.** "Render both versions with our values and diff them" is
  a method. "CNPG 1.30 made `ScheduledBackup.spec.cluster` immutable" is a conclusion about
  one chart version. It belongs in the PR that made that change.
- **Not a restatement of what lives elsewhere.** Link to `DESIGN.md`, `README.md` or
  `CLAUDE.md` rather than repeating them, so there is one copy of each instruction to keep
  current.
- **A diagnostic approach, not a diagnostic answer.** "An error that is a catch-all for
  several causes needs a disambiguating step before you patch anything" is a reusable move.
  "`SignatureDoesNotMatch` from barman-cloud can mean a trailing-dot endpoint breaking
  SigV4" is an answer. Resist building a symptom lookup table one entry at a time.
- **Stated repo facts as facts, but no false generalizations.** A correction about this
  repo's conventions or environment ("we pin only the chart version") is captured as a
  plain fact, not re-derived with hedging each time. A syntax convention that one upstream
  happens to use (a tag naming scheme, a CLI invocation) is not stated as universal. Check
  before generalizing.
