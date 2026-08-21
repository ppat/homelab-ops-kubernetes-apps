# commit-taxonomy

`verify-commit-taxonomy.mjs` is the emission-closure check run by the `commit-taxonomy` job in
[`.github/workflows/lint.yaml`](../../../.github/workflows/lint.yaml). This file is for whoever has
to change that script. It explains the constructs it is built from and what to do when the world
around it moves; it does not restate the taxonomy itself, which lives in
[`.claude/rules/commits.md`](../../../.claude/rules/commits.md).

## Why the check exists

Renovate and release-please **compile** commit headers from configuration. commitlint only ever sees
headers that already exist. Nothing in the pipeline compares the two, so a configuration capable of
emitting a header commitlint would reject stays green until the bot actually opens that pull request
— possibly months later, on someone else's schedule, on `main`.

The invariant is therefore: **nothing this repository can emit automatically may be a header its own
commitlint config rejects.** The script generates the emittable set and lints it.

The failure it is most often going to catch is not a bad edit to `commitlint.config.js`. It is a
module or component added without updating `commitlint.config.js` and `release-please-config.json`,
because the Renovate scopes are **templated** (`apps-{{dir}}`). The emittable set is a function of
**repo state**: a new directory with a manifest in it mints a new scope with no config edit anywhere,
and there is no existing header for commitlint to reject. Renames and moves do the same in reverse.
That is also why the CI job is **not** path-gated — gating it on the config files would skip exactly
this case.

## What it asserts, and what it does not

It asserts that every header in the per-upgrade closure passes commitlint:

`(manager × packageFile × package × update type) → one rendered header`, plus release-please's
rendered pull-request titles. Judgement is delegated to commitlint itself — type, scope *and* `!`,
not a scope set-membership test — so pairing rules and breaking-marker rules are exercised too.

It additionally runs two **falsifiers** that commitlint alone cannot express:

- a calver-classified package must never resolve with breaking treatment (no `!`, no
  `BREAKING CHANGE` body) for **any** update type;
- a non-calver major on a module path must always resolve with breaking treatment.

It does **not**:

- model branch-level aggregation — which upgrade's prefix a grouped multi-upgrade branch ends up
  emitting. That is unbounded repo state. The merge-time commitlint check is the gate there; this
  script's guarantee for a grouped branch is only that every *candidate* prefix on it is in-enum.
- model every Renovate manager (see [Known modelling gaps](#known-modelling-gaps)).
- check subjects. They are synthesized (`update <dep> (1.0.0 -> 2.0.0)`), because
  `commitMessageAction`/`Topic`/`Extra` render *after* the prefix and cannot place a type or scope.

## Running it

```bash
bun install --frozen-lockfile                                # commitlint, from the repo's package.json
node ci/scripts/commit-taxonomy/verify-commit-taxonomy.mjs --self-test
node ci/scripts/commit-taxonomy/verify-commit-taxonomy.mjs
node ci/scripts/commit-taxonomy/verify-commit-taxonomy.mjs --dump-headers   # every header + provenance
```

commitlint is **not** installed ad hoc: it comes from the repo-root `package.json` + `bun.lock`,
which are also what the `commit-messages` gate resolves, so this check and the gate it predicts run
the same commitlint. Those bumps are Renovate-managed as `chore(internal-dependencies)` — repo
tooling, reaching no cluster and sitting in no release-please package.

Remote presets are fetched from `raw.githubusercontent.com` at their pinned ref. Without network,
pre-download them and pass `--offline-presets DIR`, where `DIR` holds one `<preset-name>.json` per
remote preset file (`default.json`, `dev-tools.json`, …). That flag is also the cheapest way to ask
"what would happen if the preset pin moved" — see [When the shared preset pin
moves](#when-the-shared-preset-pin-moves).

The repo root is resolved with `git rev-parse --show-toplevel`, not from this file's depth, so the
script may be moved again without silently reading the wrong tree.

## The model, in five constructs

Change any of these and re-read this section first; they compose, and each one has a failure mode
that is silent rather than loud.

### 1. The config closure

`loadClosure()` walks `.github/renovate.json` → `extends` → local sub-configs and remote presets,
breadth-first, then re-orders so an extended preset sits **before** the config that named it — which
is Renovate's precedence rule (later wins, and the extender wins over what it extends).

Three kinds of ref are handled differently on purpose:

- `local://` and `github>ppat/homelab-ops-kubernetes-apps//…` are read **from the working tree**, so
  in-flight edits are what gets checked rather than what is on `main`.
- other `github>owner/repo…#tag` refs are fetched at the pinned tag. An unpinned remote ref is a hard
  error: an unpinned preset makes the emittable set unreproducible.
- Renovate **built-in** presets (`:ignoreModulesAndTests`, `config:recommended`, …) are not fetched.
  They carry no `ppat` scopes. The only built-in semantics that matter here are the ones that set
  `ignorePaths`, and those are encoded in `IGNORE_PATHS_BY_BUILTIN` with their upstream source cited.

### 2. Mechanical site enumeration

`flatten()` collects every field that can place a type, scope or `!` into a header —
`semanticCommitScope`, `semanticCommitType`, `semanticCommits`, `commitMessagePrefix`, plus
`commitBody` and `enabled` — from every config in the closure.

There is deliberately **no hand-maintained list of files or rules**. A hand list is a second thing to
update, and the whole defect class here is "someone updated one place and not the other". Adding a
preset or a rule extends the closure automatically; the run prints every site it found, so a site
that stops being seen is visible in the log.

The corollary is that the resolver must refuse to proceed on anything it cannot read. It fails —
never guesses — on:

- an unsupported `match*` key on a rule that carries one of those fields (`SUPPORTED_MATCHERS`);
- a handlebars construct `evalTemplate` does not implement;
- a `matchPackageNames`/`matchFileNames` glob using brace expansion outside the one modelled idiom,
  `<name>{/,}**`. minimatch expands braces; reading one literally would resolve the cell differently
  here than in production, silently — the same class of mismatch the check exists to close.

### 3. Package occupancy

`detectOccupancy()` derives which packages exist from **`git ls-files`**, never a filesystem walk
(`.claude/worktrees/` can hold full checkouts, which would forge occupancy). For each modelled
manager it applies that manager's `managerFilePatterns` and its **effective** `ignorePaths`.

`ignorePaths` is **non-mergeable** in Renovate: every assignment *replaces* the previous list. So the
effective list is computed as built-in default → each built-in preset named in an `extends` list →
any config in the closure setting a top-level `ignorePaths`, each replacing wholesale. Which built-in
applies is read off the resolved `extends` lists rather than assumed, so dropping or re-adding
`:ignoreModulesAndTests` moves occupancy here exactly as it moves it in Renovate.

This is the part that makes the check **repo-state-triggered**. A new manifest, a moved package, a
new image reference, a new `# renovate:` annotation, a new `uses:` — any of these can mint a cell and
therefore a header, with no configuration change at all.

### 4. Per-cell resolution

`resolveCell()` folds the flattened rules in closure order, last match wins **per field**, then
renders. `ruleMatches()` implements only the matcher semantics these configs actually use; a cell
carries `depType` only for managers that have one (npm/bun read it off the `package.json` section),
which is why a `matchDepTypes` rule cannot match a cell without one — as in Renovate.

One precedence detail is easy to get wrong and worth stating: Renovate builds the semantic prefix
**only when no `commitMessagePrefix` is in effect** (`semanticCommits === 'enabled' &&
!commitMessagePrefix`, `lib/workers/repository/updates/generate.ts`). An explicit prefix wins whether
or not `semanticCommits` is disabled alongside it. Every rule in the current closure that sets a
prefix also disables semantic commits, so the distinction is inert today — and stops being inert the
moment a shared preset sets a prefix without disabling them.

### 5. Judgement

Rendered headers go through commitlint's own `load`/`lint` against `commitlint.config.js` at the repo
root. Nothing here reimplements the enums. If the config is wrong, this check reports whatever the
config says — it verifies **agreement between emitter and linter**, not that either one is correct.

## The self-test, and why a green run without it means nothing

`--self-test` injects known-bad inputs and exits non-zero unless every one is caught. CI runs it
**first**, so the zero-defect verdict that follows comes from a checker that has just demonstrated it
can see defects. A checker that silently stopped enumerating sites, stopped resolving cells, or
stopped calling commitlint would otherwise report a clean run — the most dangerous possible output.

The injections cover each stage independently:

| Stage | Injection | What its absence would hide |
| --- | --- | --- |
| Lint | literal headers with an off-enum scope, a degenerate empty scope segment, `!` on a type that cannot claim shipped behaviour, and a type removed from the enum | commitlint not actually being consulted, or the config not loading |
| Resolution → lint | a calver-class package planted on a `ci/test/` path, which must render an off-enum doubled scope | the resolver rendering headers nobody lints |
| Falsifier (calver) | the calver rules mutated to enumerate `matchUpdateTypes` excluding major | the breaking-treatment predicate going blind to the exact mutation it exists to detect |
| Falsifier (non-calver) | a module-path major with neither `!` nor a `BREAKING CHANGE` body | the predicate only ever firing in one direction |
| Occupancy | an assertion that the node toolchain manifest yields npm/bun cells at all | a whole manager silently dropping out, making every verdict about it vacuous |
| Occupancy → lint | the scope assigned to that manifest rewritten off-enum | those cells being enumerated but never resolved or linted |
| Templates | an unimplemented handlebars construct | the resolver rendering a guess instead of failing |

**When you add modelling, add an injection for it.** The occupancy pair above is the pattern to copy:
one assertion that the new cells exist, and one mutation proving they reach commitlint. Coverage that
is not falsified is not coverage.

## Known modelling gaps

These are deliberate and worth knowing before trusting a green run:

- **Unmodelled managers are a silent coverage gap.** `detectOccupancy` enumerates only the managers
  that have packages here. The `kustomize` manager is notably not modelled. An unmodelled manager
  produces no cells, no headers and no failures — it does not announce itself.
- **Grouped branches** are covered only at candidate level (see above).
- **Occupancy detection is line-based**, not a YAML parse. It recognises the shapes these manifests
  actually use (`image:`, `chart:`, `url: oci://`, `# renovate:` annotations, `uses:`, `repo:`). A
  manifest that expresses a dependency some other way is invisible to it.
- **`matchDepTypes` matching is exact-list membership.** Renovate's dep-type vocabulary is
  manager-specific; only npm/bun cells carry one here.
- **`commitBody` is inspected only for the string `BREAKING CHANGE`**, which is all the
  breaking-treatment predicate needs.

## Maintenance playbook

### A Renovate rule gains a matcher or a template the resolver does not know

The run fails with `unsupported matcher` / `template uses handlebars this resolver does not
implement` / `brace expansion this resolver does not model`. This is working as designed. Implement
the construct in `SUPPORTED_MATCHERS` + `ruleMatches`, `evalTemplate`, or
`matchesPackageName`/`globToRegex` respectively — matching Renovate's semantics, not the shape that
makes the current configs pass — and add a self-test injection.

### When the shared preset pin moves

Bumping `github>ppat/renovate-presets#<tag>` in `.github/renovate.json` changes emission for every
consumer at once. Rehearse it before landing it:

```bash
mkdir -p /tmp/presets && cd /tmp/presets
for f in default dev-tools github-actions kubernetes; do
  curl -sfL "https://raw.githubusercontent.com/ppat/renovate-presets/<new-tag>/$f.json" -o "$f.json"
done
cd -
node ci/scripts/commit-taxonomy/verify-commit-taxonomy.mjs --offline-presets /tmp/presets
```

A worked example of why this matters: `ppat/renovate-presets` v1.0.0 adds
`commitMessagePrefix: "{{semanticCommitType}}{{#if semanticCommitScope}}({{semanticCommitScope}}){{/if}}!:"`
to its major rule *without* disabling semantic commits. Rehearsed against the pinned v0.2.1 the
closure is clean; rehearsed against v1.0.0 the resolver stops on that unimplemented template, which
is the correct answer — `!` would then attach to **every** major, including ones whose type cannot
carry it. Implementing the template turns the stop into a list of the headers the enum must accept
first. `.claude/rules/commits.md` states the ordering this enforces: the enum moves **before** the
preset pin, never after.

### A new manager gains occupancy

Adding a manifest kind Renovate manages (a `Chart.yaml`, a Terraform module, another `package.json`)
mints cells that are invisible until `detectOccupancy` enumerates them. Add a block there — read
files via `readLines`/`git ls-files`, honour `managerFiles()` so `ignorePaths` applies — decide
whether the cells carry a `depType`, and add the occupancy + off-enum injection pair to the
self-test. Then check what scope the new cells resolve to: if the answer comes from a shared preset
rather than from this repo's `.github/renovate/`, it can change under you when the pin moves.

### commitlint or release-please config changes

Nothing to do in the script — the enums are read from `commitlint.config.js` and the components from
`release-please-config.json` at run time. If a check fails after such a change, the disagreement is
real: either the enum is missing something the config can emit, or the emitter is emitting something
it should not.

### The commitlint dependency bumps

Renovate opens `chore(internal-dependencies): update npm packages …` against the repo-root
`package.json`. That bump moves the `commit-messages` gate and this check together, by construction.
Re-run `--self-test` after a major: the script uses `@commitlint/load` and `@commitlint/lint`
directly, which are internal-ish APIs and have changed shape across majors.

### Reading a failure

Every failure carries provenance: `manager:dep@dir [updateType] via <rule sources>`. The rule sources
are `<config-file>#<index>` into that file's `packageRules`, which is where to look first. `--dump-headers`
prints the same provenance for every candidate header, which is the fastest way to see what a config
edit actually changed — diff the dumps across the edit.
