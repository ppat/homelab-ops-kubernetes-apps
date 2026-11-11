# research-renovate-pr

The prompt and Claude Code settings for
[`.github/workflows/research-renovate-pr.yaml`](../../../.github/workflows/research-renovate-pr.yaml).
That workflow runs the
[research-version-changes](../../../.claude/skills/research-version-changes/SKILL.md) skill on a
Renovate pull request that makes a major or minor bump under `infrastructure/`, and posts the
report as one comment.

## How it decides what to research

The workflow parses nothing. It hands the model the pull request's description and its diff
under `infrastructure/`, and the model finds each moved chart or image, its FROM and TO, and the
HelmRelease it sits in. Renovate words its descriptions and diffs in many ways, and reading them
is judgment, not parsing.

The only usage the report judges against is that HelmRelease's `spec.values`. Patches,
components, post-build variables and the clusters repo are not considered, and the report's
Coverage says so.

## Invariants

- **Major and minor only.** The job runs only when the title starts with `feat`. The shared
  renovate-presets give a major or minor update `feat` and a patch, digest or pin update `fix` or
  `chore`, and this repo's calver override keeps that split.
- **Once per pull request.** The comment carries the marker
  `<!-- pr-comment-id: research-version-changes -->` (written by the `comment-on-pr` action), and
  the first step stops the job when it is already there. Delete the comment to get a fresh report.
- **It never blocks automerge.** Renovate waits for every check, not only required ones. Each step
  that can fail is `continue-on-error`, so a failure leaves a green job, no comment, and a retry
  on the next push.
- **A change to it is tested before it lands.** A pull request that changes the workflow, this
  directory or the research skill runs the workflow in test mode. It researches the fixture
  Renovate pull request named in the workflow, with `infrastructure/` as at that bump, posts the
  report on the changing pull request under a separate marker, and fails when the research fails.
  Every push repeats it.
- **The token reads the repository and comments on pull requests, nothing else.**
- **The model and its provider are not in this repository.** The `RESEARCH_AGENT_ENV` secret
  holds `NAME=VALUE` lines of the environment Claude Code reads for its endpoint, credential and
  models. Set every model role, subagents included, so that no call falls back to a default model.

## Gotchas

- **Project settings are ignored in an untrusted workspace.** In print mode, Claude Code drops the
  allow rules of `.claude/settings.json` in a directory nobody has accepted the trust dialog for,
  which a CI checkout never has. The settings therefore come in through `--settings`.
- **A denied command can make the model abandon the skill's scripts.** In testing, a model whose
  first chained shell command was denied stopped using the scripts and scraped release pages with
  WebFetch instead, which gave a report with no render, values diff or CRD check. The prompt states
  the only command forms the settings allow.
- **The settings are what keep the credential in.** The model's environment holds the endpoint
  credential, and release notes are untrusted text. `claude-settings.json` runs in `dontAsk` mode,
  allows only the research skill, its two scripts and `git ls-remote` in Bash, and denies reads of
  `/proc` and `/etc`. Do not deny the home directory: on a GitHub runner the checkout is inside
  it, and the deny would block every read and write in the workspace. Widening the Bash allow
  list re-opens the way to the environment.
