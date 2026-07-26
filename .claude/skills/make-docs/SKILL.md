---
name: make-docs
description: >
  Use this skill whenever you are creating, updating, or auditing one of this
  repo's README docs — a single module's README
  (`apps|infrastructure/subsystems/<m>/README.md`), a component's README
  (`components/<m>/README.md`), a module-type README (`apps/README.md`,
  `infrastructure/README.md`), or the repository-root `README.md`. Trigger it
  for any phrasing that lands there: "document this module", "write/refresh the
  README", "add the new app to the docs", "document the new component", "the
  module catalog is out of date", "regenerate the root README", "check whether
  this module's docs still match its manifests", or after adding/removing/
  changing a module, a component, or an app/service inside a module so its README
  no longer matches the manifests. It enforces the two things that make these
  docs correct: an implementation-first process (review every source file, invent
  nothing) and the fixed per-type structure each doc must follow. Do NOT use it
  for free-form architecture/process docs (`DESIGN.md`, `TESTING.md`,
  `OPERATIONS.md`) — those have no template — or for code comments; those are out
  of scope.
---

# Authoring this repo's README documentation

This repo has four kinds of templated README, each at a defined level of
abstraction, each written from a different set of sources. Getting one right is
two disciplines at once: a **process** (review the real files, invent nothing)
and a **structure** (the fixed sections that doc type must contain). This skill
carries both. The structure lives in per-type reference files; the process below
applies to all four.

## What you're doing — create, update, or audit

Same skill, three entry points:

- **Create** — new documentation is needed. Two shapes of this: a whole **new
  module or component** was added (a README that never existed), or a **new
  app/service was added inside an existing module** (the module README exists but
  is now missing a piece). The first is a net-new doc; the second is really an
  update to the module README — see the cascades below for which upper docs each
  one ripples to.
- **Update** an existing doc after a change — a service was added/removed, a chart
  bumped a values path, a new prerequisite appeared. Re-review the changed sources
  and bring the affected sections back into line; don't rewrite what didn't change.
- **Audit** a doc for drift — no edit requested yet, the question is *does this
  still match the manifests?* Do the full source review a create would do, then
  diff reality against the doc and report what's stale (missing/renamed services,
  changed variables/secrets, removed prerequisites, a diagram that no longer
  reflects the wiring). Auditing is just creating-without-writing followed by a
  comparison.

Both create shapes **cascade up the abstraction levels** — do the docs in this
order, because each upper doc summarizes the ones below it, and summarizing before
the lower doc is correct means summarizing the wrong thing:

- **New module or component:**
  1. Its own README (implementation level).
  2. Its module-type README (`apps/README.md` or `infrastructure/README.md`) — add
     it to the Functional Areas table and the relationships diagram. (Components
     have no module-type README; skip this for a component.)
  3. The repository-root `README.md` — add it to the module catalog table.
- **New app/service inside an existing module:**
  1. The module's README — add it to Service Architecture / Service Details, and to
     Quick Links if it's a distinct app (fetch its icon per **references/module-doc.md**).
  2. The module-type README — only if the new service changes the module's
     advertised capabilities.
  3. The root `README.md` — only if the new app is user-visible and belongs in that
     module's app list in the catalog table.

## First: identify the doc type, then read its reference

Everything downstream — which files you may read, the abstraction level, the
section list — is determined by which of the four you are writing. Pin this down
before reading anything else.

| Doc type | Path(s) | Sources you may use | Structure spec |
| --- | --- | --- | --- |
| **Individual module** | `apps/subsystems/<m>/README.md`, `infrastructure/subsystems/<m>/README.md` | The module's own `kustomization.yaml` and **every** implementation file it references (HelmReleases, patches, PVCs, secrets, ingress, etc.). `DESIGN.md` for concept links only. | **references/module-doc.md** |
| **Component** | `components/<m>/README.md` | The component's `kustomization.yaml` and **every** resource/patch file it references. `DESIGN.md` for the components-pattern concept link. | **references/component-doc.md** |
| **Module type** | `apps/README.md`, `infrastructure/README.md` | Only the module `README.md` files under that tree (`*/subsystems/*/README.md`). `DESIGN.md` for context. **No** implementation files. | **references/module-type-doc.md** |
| **Repository root** | `README.md` | `DESIGN.md` (primary) + the two module-type READMEs (secondary). **No** individual module or implementation detail. | **references/root-doc.md** |

Any doc that contains a Mermaid diagram also follows **references/mermaid.md** — read
it alongside the type spec, don't reinvent the color/flow conventions.

Individual modules and components are both **implementation-level** docs (written
from manifests); module-type docs are **capability-level** (written from module
docs); the root is **project-level** (written from `DESIGN.md` + module-type
docs). The level is strict and non-negotiable, because mixing levels is the most
common way these docs go wrong: a configuration value in the root README, or a
marketing sentence in a module README, is a level violation even if every word is
true.

## The process — implementation-first, assume nothing

These rules exist because an LLM's default failure mode on documentation is to
start writing from general knowledge before it has read the actual files, then
fill the gaps with plausible-but-wrong detail. Every rule below is a guardrail
against that one tendency.

1. **Review all applicable sources before writing a word.** Use the sources
   column above for your doc type — and for a module or component doc that means
   reading every file `kustomization.yaml` pulls in, completely, not skimming the
   first screen. Missed integration points and half-read HelmReleases are where
   wrong dependency chains come from. List the files you will read first, then
   read each one to the end.

2. **Document only what exists in the sources.** Every capability, relationship,
   prerequisite, and dependency you write must trace back to a specific line in a
   file you read. If you cannot point to where it comes from, it does not go in
   the doc. General knowledge about how an app "usually" works is exactly the
   thing to leave out — it produces features and config that don't match this
   repo's implementation.

3. **Ask instead of guessing.** When a config is ambiguous, a relationship is
   unclear, a requirement seems missing, or the implementation has a gap you'd
   have to fill to proceed — stop and ask. Filling it with an assumption is the
   failure this whole process exists to prevent; a one-line question is cheap by
   comparison.

4. **Work bottom-up when a change spans levels.** The abstraction levels build on
   each other, so documentation follows dependency order: implementation-level
   docs first (individual **modules** and **components** — infrastructure modules
   before apps/components, following the dependency graph in `DESIGN.md`), then
   **module types** once every module under a tree is done, then the **root**
   last. This is the cascade in "What you're doing" above. For a single-doc edit
   it's moot; for a repo-wide pass it's the order that keeps levels consistent.

For anything larger than a single doc, track progress with the task tools
(`TaskCreate`/`TaskUpdate`) — one task per doc, carrying which sources it depends
on — so that "which docs are done, which sources are still unread" is a fact you
can check against tool state rather than reconstruct from scrollback. Losing that
thread mid-pass is how docs end up inconsistent with each other.

## What every doc must and must not contain

These apply on top of the per-type structure, and most map directly onto the
abstraction-level rule above.

- **Must include:** verified implementation requirements, actual relationships,
  real integration points, required configuration, system boundaries — the things
  that are true of *this* deployment and that a reader can't get from upstream
  docs.
- **Must not include:** generic/optional configuration, non-required settings,
  marketing language, and — critically — detail from the wrong level
  (implementation specifics in a type/root doc; operational procedures anywhere in
  these docs — those live in `OPERATIONS.md`/`TESTING.md`). Version numbers do not
  belong in any of these docs — they churn and are captured elsewhere.

## Before you finish — verify

- Every section required by the type's structure spec is present, in order.
- Every claim traces to a source file you actually read; nothing was assumed.
- The abstraction level is consistent throughout — no detail from another level
  leaked in.
- Tables have the exact columns the spec calls for; every image has alt text and
  every Mermaid diagram follows **references/mermaid.md** (markdownlint and
  accessibility both depend on this).
- Links resolve — to real files/anchors in this repo, and (for logo links) to
  official upstream sites, not repo-internal or version-pinned URLs. Any new app
  icon has actually been fetched into `.static/images/logos/` (see
  **references/module-doc.md**), not merely referenced.

Then run the repo's doc linters on what you changed (see
[`CLAUDE.md`](../../../CLAUDE.md#commands) — `markdownlint-cli2`, `yamllint`), since
these docs are held to the same pre-commit gate as everything else.

## Reference files

| File | Read it when |
| --- | --- |
| `references/module-doc.md` | Writing an individual module README — the 8-section structure (Intro, Quick Links, Overview, Service Architecture, Service Details, Prerequisites, Dependencies, Notes), the app-icon lookup for new apps, and what each section may/may not contain |
| `references/component-doc.md` | Writing a `components/<m>/README.md` — Intro, Overview, How It Works, Resources, Prerequisites, Notes, for a Kustomize component that patches/adds resources on top of a module |
| `references/module-type-doc.md` | Writing `apps/README.md` or `infrastructure/README.md` — Intro, Functional Areas table, Module Relationships diagram, Configuration link |
| `references/root-doc.md` | Writing the repository-root `README.md` — What This Project Provides, Project Structure & Concepts, Finding Your Way |
| `references/mermaid.md` | Any doc containing a Mermaid diagram — flow/color conventions and the infra vs. application `classDef` styles that must stay consistent across the repo |
