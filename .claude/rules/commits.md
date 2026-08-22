---
description: How to choose the type and scope of a commit in this repo. The header is a claim about the diff — this rule makes the claim decidable from the diff alone.
---

# Commit types and scopes

## The deciding rule

> **Scope names the released artifact whose directory the diff touches — or, when the diff touches no
> artifact directory, the internal surface it maintains. Type states the kind of change. The release
> machinery listens to neither: release-please routes releases by *path* and sizes bumps by *type*, so
> the header is a claim about the diff that must be kept true, not a routing instruction.**

Consequences that follow directly:

- A scope cannot make a release happen or not happen. Touching `apps/subsystems/ai/` proposes an
  `apps-ai` release whatever the scope says; the scope's job is to say so honestly.
- The release-facing string is the **squash title**: a single-commit PR lands its commit header, a
  multi-commit PR lands its **PR title** (`squash_merge_commit_title: COMMIT_OR_PR_TITLE`). Keep the
  PR title conforming — it is the header that lands on `main`, and it is what release-please parses.
- Interior commit bodies and GitHub's `*`-prefixed squash bullets are inert to release-please. Only the title
  line carries release semantics; bodies are for humans.

## Scopes

Apply **in order, stop at the first match**. The ordering makes the choice deterministic; every scope
below is in `commitlint.config.js`'s enum and the set is closed — a new scope is a design change, not
an improvisation.

| # | Scope | Matches | Ships? |
| --- | --- | --- | --- |
| 1 | `release` | A release cut — commits authored by release-please. Changes to the release *machinery* go to rule 8 | — |
| 2 | `github-actions` | A `uses:`/action ref bumped or re-pinned, anywhere — nothing else | no |
| 3 | `kubernetes-api` | A Kubernetes `apiVersion:` bumped, anywhere — nothing else. Sits above the module scopes because an API migration is grouped by group+Kind across every module using that API, so no module scope can be true of it | yes |
| 4 | module scopes: `apps-*` (8), `infra-*` (12), `infra-bootstrap-crds` | The diff's footprint is one released module: its directory, plus its **1:1** `ci/test/` suite, plus any `components/**` or `.static/**` files riding along | **yes — the scope is the shipped claim** |
| 5 | `components` | Only `components/**` changed, no module directory | by proxy (see below) |
| 6 | `renovate` | This repo's Renovate configuration (`.github/renovate.json`, `.github/renovate/**`) | no |
| 7 | `internal-dependencies` | A toolchain/dev dependency moved, or a tooling config file hand-edited (`mise.toml`, `.pre-commit-config.yaml`, `package.json`, lockfiles) | no |
| 8 | `internal-workflows` | This repo's own CI and release machinery: hand-authored workflow logic, `ci/scripts/`, `ci/validation/`, the shared test harness, `release-please-config.json`, `.release-please-manifest.json`, `commitlint.config.js`, linter configs | no |
| 9 | `agents` | `.claude/**`, `CLAUDE.md`, any other AI-coding-agent instruction surface | no |
| 10 | *(empty)* | Repo-level docs/policy belonging to no single surface; an atomic change spanning ≥2 modules; a fan-in `ci/test/` group change; repo-root and dot-directory residue (`.analysis/`, `.vscode/`, `.gitattributes`, …) | can ship |

The module list itself lives in `commitlint.config.js` and `release-please-config.json` (path →
component); those files are the source of truth when a module is added or removed.

**Transitional scopes** (`dev-tools`, `component-db-backups`) remain in the enum only because unmerged
branches still carry commits with them. Never use them in a new commit: `dev-tools` →
`internal-dependencies` or `internal-workflows`, `component-db-backups` → `components`.

## Types

Allowed: **`chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `test`.**
`build` and `style` are deliberately absent — `style` cut real patch releases here while claiming to
be cosmetic, and `build` has no meaning in a repo with no build system.

`feat`/`fix`/`perf`/`refactor` claim **shipped behaviour changed**. They pair only with scopes that
can carry that claim — module scopes, `components`, `kubernetes-api`, or the empty scope — and
commitlint rejects them on internal surfaces. Internal surfaces take `chore`/`ci`/`test`/`docs`: a
bug fix in a CI workflow is `ci(internal-workflows):` with "fix" in the subject, because `fix` there
would claim a shipped artifact changed, which is false.

What each type does to the release, at 0.x versions:

| Type | Changelog | Alone in a release window |
| --- | --- | --- |
| `feat` | ✨ Features | patch bump (minor with `!`) |
| `fix` / `perf` / `refactor` | 🚀 Enhancements + Bug Fixes | patch bump |
| `docs` | 🛠 Improvements (visible **deliberately** — ride-along docs next to features are worth surfacing; a rare docs-only release is the accepted cost) | patch bump |
| `revert` | ⚙️ Other | patch bump |
| `test`, `ci`, `chore` | hidden | no release |

Two mechanics that make this table honest rather than obvious:

- **`hidden` gates the release, not just the display.** A window containing only hidden types opens no
  release PR at all. There is no "visible but non-bumping" — a visible type alone always proposes a
  patch release. Release PRs queue until the maintainer merges them, so a lone `docs` commit proposes
  a release; the maintainer disposes.
- **`!` overrides `hidden`.** A breaking commit is rendered and bumps regardless of its type's flag,
  so `chore(apps-x)!:` would cut a release while claiming to be inert. commitlint therefore rejects
  `!` on anything but `feat`/`fix`/`perf`/`refactor`.

## The scenarios that resist a single scope

| Situation | Header | Why |
| --- | --- | --- |
| Atomic change spanning ≥2 modules | empty scope — `fix: <subject>` | Prefer splitting into per-module PRs; when genuinely atomic, the empty scope lets each touched module's release pick the commit up honestly. Naming one module would be a false claim about the others |
| Module + component files in one diff | the **module's** scope | The module release is what ships the change; name the component in the subject or body |
| Only `components/**` changed | `components` | Components ship by proxy — they ride each consuming module's next release, and no component has its own version to claim. A module scope here would claim a release that isn't routed; unscoped hides a real, nameable surface |
| `ci/test/` suite covering exactly one module | that module's scope — `test(apps-coder):` | The suite is part of the module's shipped claim's evidence |
| Fan-in `ci/test/` group covering two modules | empty scope, group named in the subject — `test: tighten infra-security suite assertions` | The change is *about both* modules; picking one would be an artifact of the header, not of the change. Whether a group is 1:1 or fan-in is read off `release-please-config.json`: one `ci/test/` directory serving both a `-core` and an `-extra` package is fan-in |
| Urgent component fix needing a release *now* | `fix(<module>): deliver components/<x> fix to <module>`, with a real one-line change in the module directory | Routes a genuine release per consuming module without a dishonest no-op touch; `Release-As:` footer if a specific version is needed |

## Breaking changes

Mark with `!` after the type and scope — `feat(infra-storage-core)!:` — and add a
`BREAKING CHANGE: <what the operator must do>` footer. The colon and description are required; a bare
`BREAKING CHANGE` line parses as nothing. At 0.x, `!` cuts a **minor**, which is the
read-before-merging signal for the clusters that consume these modules — use it deliberately.

Breaking is a claim about the *operator's* obligations (a required values change, a manual migration,
a CRD replacement), not about the size of the diff. Some dependencies are known to break on minors;
the Renovate overrides hand-build `!` headers for those paths — that is the overrides doing their job,
not noise to clean up. The overrides work in both directions: the shared preset attaches `!` to every
major, and `.github/renovate/override-breaking-changes.json` takes it back off the internal surfaces
(`github-actions`, `internal-dependencies`, `renovate`), where a `!` would cut a release for a scope
that ships nothing. A bot `!` is applied structurally — nothing reads the release notes — so it means
"a human should read this before it reaches a cluster", not "this is known to break".

## Version schemes that are not semver

Some dependencies version by calendar (year.month.patch and similar). The principle:

> **Segments that date a release do not grade its risk.** A calver "major" is the year rolling over —
> no more significant than the month. Nothing breaks because the calendar turned.

Consequences, stated generally because the affected set changes:

- A calver year/month rollover is **routine**: no `!`, no `BREAKING CHANGE`, automerge stays on. The
  Renovate calver overrides exist to strip semver-derived breaking treatment from these deps;
  a rule that "loses" the `!` on a calver major is working as designed.
- When classifying a dependency, **audit every inherited default whose rationale assumes semver** —
  breaking markers, automerge policy, release-age soaks, major/minor PR separation. Each is reasoning
  about risk from a number that does not carry that meaning there.
- Classify by the *scheme the vendor actually operates*, never by surface shape: a `YYYY.M.x` tag can
  still be semver-intended (declared so in `version-scheme.json`), and a year-branded product version
  (SQL Server 2022) is a real major, not calver. Getting this wrong in either direction re-creates the
  same defect with the sign flipped.

## Bot commits

Renovate compiles its own headers from `.github/renovate/**`; **leave its titles alone.** Three of its
behaviours are documented properties, not violations to fix:

- A **grouped** update of a shared dependency emits one scope for a diff spanning several modules. For
  bot commits the deciding rule reads: *the scope names one of the released artifacts the diff
  touches, and the diff may touch more* — the paths carry the full truth, and release-please routes
  every touched module correctly regardless.
- A bot branch whose last-resolved package file sits under `ci/test/**` emits the empty scope.
- Renovate also updates **its own configuration**: the `renovate-config` manager treats every pinned
  `github>owner/repo#tag` in `.github/renovate.json` as a dependency, so the shared-preset pin moves
  by bot. That header is `chore(renovate):` — the config reaches no cluster — and it is the one bot
  pull request that changes every other bot pull request's header, which is why the
  `commit-taxonomy` check resolves the preset **at the pin in the diff** rather than at the pin on
  `main`.

What must stay true instead is **closure**: every header the Renovate config *can* emit must be inside
the commitlint enums. The `commit-taxonomy` CI check
([`ci/scripts/commit-taxonomy/`](../../ci/scripts/commit-taxonomy/README.md)) derives that emittable
set from the config and fails on any escape — when it goes red on a config or preset change, the emitter or the enum is wrong,
never the check's place in the pipeline. Because a shared-preset bump changes emission for every
consumer at once, the enum must always move **before** the preset pin, never after.

## Gotchas

- **The scope enum constrains humans and bots through different doors** — commitlint on branch
  commits for humans, the emission-closure check for Renovate config. Editing
  `commitlint.config.js` without re-running the closure check (or vice versa) reopens the gap between
  what can be emitted and what would be accepted.
- **A scope naming a module is a version claim.** `fix(apps-media):` on a diff that never touches
  `apps/subsystems/media/` is the lie this whole rule exists to prevent — check the paths, not your
  memory of where something lives.
- **`chore` is not a euphemism.** A genuine bug fix is `fix` (shipped surface) or `ci`/`chore` with
  "fix" in the subject (internal surface) — chosen by *what the diff touches*, not by how small it is.
- **Adding a module touches three enums**: `release-please-config.json`,
  `.release-please-manifest.json`, and `commitlint.config.js`'s module list. That plumbing commit is
  `ci(internal-workflows):` — the module's own scope starts existing for the *next* commit.
