# Individual Module Documentation — structure

Purpose: document one module's capabilities and boundaries.
Path: `apps/subsystems/<name>/README.md` or `infrastructure/subsystems/<name>/README.md`. (A `components/<name>/README.md` is a different doc type — see **component-doc.md**.)

Throughout this spec, "**service**" means one of the running pieces a module deploys — an app, a controller, a database, a routing service. It deliberately does **not** mean a Kustomize *component* (the `components/` dir); those are documented by their own type.
Sources: the module's `kustomization.yaml` and **every** implementation file it references — read them completely before writing. `DESIGN.md` for concept links only.

Sections appear in this order. "Optional/when to include" sections are the only ones you may omit.

## 1. Introduction

- **Format:** single sentence, or one short paragraph if the module is complex.
- **Include:** what capabilities the module provides to the system — its role.
- **Exclude:** implementation details, configuration specifics, version numbers. Describe the role, not the mechanism.

## 2. Quick Links

- **Format:** one inline-HTML logo link per application, the whole logo wrapped in the link. Follow this markup exactly:

  ```html
  <a href="https://bitwarden.com/help/password-manager-overview/" target="_blank"><img src="../../../.static/images/logos/bitwarden.svg" width="32" height="32" alt="Bitwarden"></a>
  ```

- **Include:**
  - The `<a href>` points to the application's **official documentation/website** and opens in a new tab (`target="_blank"`).
  - The `<img src>` is the app's logo **asset committed in this repo** under `.static/images/logos/<app>.<svg|png>`, referenced by the relative path from the README's location — a module README three levels deep uses `../../../.static/images/logos/…`. Confirm the file exists; do not invent a filename or point at a remote image URL.
  - Each logo sized 32×32 px.
  - `alt` text is the application's proper display/brand name — `Bitwarden`, `Home Assistant`, `qBittorrent`, `n8n` — matching how the vendor styles it, not a lowercased slug. Required on every image, for accessibility and to pass markdownlint.
  - Applications sorted alphabetically by name.
- **Exclude — and this applies to the `<a href>` link target, not the `<img>`:** links to files inside this repo, links to specific software versions, temporary/unstable URLs. Prefer official sites over GitHub repos when both exist. The `<img>` asset is intentionally repo-local per the markup above — that is not a violation of the no-repo-internal-links rule, which governs the hyperlink.

### Getting an icon for a new app

When you document an app whose logo isn't already in `.static/images/logos/`, fetch it — don't reference a file that doesn't exist, and don't skip the logo. Use the widely-used [homarr-labs/dashboard-icons](https://github.com/homarr-labs/dashboard-icons) collection:

- **Try SVG first** — `https://raw.githubusercontent.com/homarr-labs/dashboard-icons/refs/heads/main/svg/<name>.svg` (e.g. `claude-ai.svg`).
- **Fall back to PNG** if no SVG exists — `https://raw.githubusercontent.com/homarr-labs/dashboard-icons/refs/heads/main/png/<name>.png` (e.g. `backblaze.png`).
- **Guess `<name>`, don't list.** The `svg/` and `png/` directories hold thousands of files, so don't enumerate them — construct the URL from the app's most commonly-used name/slug (lowercase, hyphenated), try it, and if it 404s try a couple of obvious alternate spellings.
- **If dashboard-icons has nothing, find one yourself.** Fall back to the app's own official icon — its site favicon, or the logo/brand assets from its official site or GitHub org — and prefer an SVG, else a reasonably-sized square PNG. Only ask the user as a last resort, when you genuinely can't locate any usable official icon.
- **Commit the asset** into `.static/images/logos/<name>.<svg|png>`, then reference it from the README by the relative path in the markup above. The committed filename doesn't have to match the upstream name — match the repo's existing naming for that app if there is one.

## 3. Overview

- **Format:** one paragraph, then capability groups.
- **Include:** the module's purpose and primary function; 3–4 main capability groups; 4–5 key features under each group.
- **Exclude:** specific configuration values or environment variables, deployment/installation instructions, version/release detail.

## 4. Service Architecture — optional

- **When to include:** the module runs multiple interacting services with non-trivial relationships. Skip it for a single-service module.
- **What counts as a "service":** the distinct running pieces the module deploys — including the common case where a **single HelmRelease fans out into many services** (multiple `Deployment`s/`Service`s from one chart). Identify them from the manifests — service and ingress definitions, chart values, routing paths — not from general knowledge of the app. The repo's usual "one subdirectory per service" layout is a hint, not a rule; a flat module can still run many services.
- **Format:** a Mermaid flowchart following **mermaid.md**.
- **Include:** service relationship diagram, color-scheme definitions, service grouping, data/control-flow arrows.
- **Exclude:** implementation details, configuration specifics, deployment topology.

## 5. Service Details

- **Format:** a table.
- **Columns:** Service name · Primary role/purpose · Key features (bullets) · Integration points (bullets).
- **Exclude:** configuration parameters, command-line examples, internal implementation detail.

## 6. Prerequisites

- **Format:** numbered subsections, each a table. Include only the subsections that actually apply to the module, based on its implementation.
- **Subsections and their columns:**
  - Required Flux post-build variables — `name` · `purpose` · `used by`.
  - Required secrets and configmaps — `name` · `purpose` · `keys`.
  - Storage requirements (if any) — `PVC name` · `purpose` · `access mode`. When the module only references a claim it does **not** itself define (e.g. `existingClaim`), the access mode isn't in the module's files — record that the claim is provisioned externally rather than inventing a mode, and ask if the mode genuinely needs documenting.
  - RBAC requirements (if any) — `resource` · `access` · `purpose`.
- **Include:** only what the implementation actually requires.
- **Exclude:** default values, sensitive information, implementation-specific detail. Every entry must come from a real file — this section is where invented requirements most often creep in.

## 7. Dependencies

- **When to include:** required for infrastructure modules; skip for apps modules.
- **Format:** two bulleted lists.
  - **Required by:** modules that depend on this module.
  - **Depends on:** modules this module requires.
- **Exclude:** indirect dependencies, app-module dependencies, external-system dependencies. Direct declared coupling only.

## 8. Notes — when needed

- **When to include:** the module has important caveats or special considerations.
- **Format:** paragraphs with bullet points.
- **Include:** important caveats/limitations, special configuration considerations, architecture decisions that affect usage.
- **Exclude:** troubleshooting steps, configuration examples, operational procedures.
