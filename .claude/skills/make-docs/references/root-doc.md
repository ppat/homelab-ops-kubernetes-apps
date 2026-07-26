# Repository Root Documentation — structure

Purpose: provide the entry point and a high-level understanding of the entire project.
Path: `README.md` (repo root).
Sources: `DESIGN.md` (primary) and the two module-type READMEs — `apps/README.md`, `infrastructure/README.md` (secondary). Do **not** pull in individual-module or implementation detail; the root doc summarizes types and project-wide concepts, nothing lower. Which means both module-type READMEs must be correct first (see the bottom-up rule in SKILL.md).

Sections appear in this order.

## 1. What This Project Provides

- **Format:** two bullet groups, then a comprehensive module table.
- **Include:**
  - Infrastructure capabilities (5–6 bullets) and end-user applications (5–6 bullets), written with action verbs (Deploy, Manage, Configure) that complete the phrase "This platform enables you to…".
  - A module table with three columns:
    1. Module name, linked to its README.
    2. The apps within that module — for each, a **logo image followed by a text link** to its official site (image then link, not the img wrapped in the link — this differs from a module README's Quick Links). Follow this markup:

       ```html
       <img src="./.static/images/logos/cert-manager.svg" width="16" height="16" alt="cert-manager"> <a href="https://cert-manager.io/" target="_blank">cert-manager</a>
       ```

       The `<img src>` is the repo-local asset `.static/images/logos/<app>.<svg|png>` — from the root README the relative path is `./.static/images/logos/…` — sized **16×16 px**; `alt` is the app's proper display name (required on every image); the adjacent `<a href target="_blank">` points to the official upstream site. If an app's icon isn't in `.static/images/logos/` yet, fetch it first per the "Getting an icon for a new app" procedure in **module-doc.md** (the root table reuses the same committed asset a module README references).
    3. A short bullet-point description of the module's capabilities.
  - Applications within each module sorted alphabetically by name.
- **Exclude:** version numbers, implementation details, configuration specifics. Focus on end-user value.

## 2. Project Structure & Concepts

- **Format:** a class diagram plus a comparison table.
- **Include:** a class diagram showing the module hierarchy; a table comparing the module types with 3–4 key characteristics each; links to the module-type directories.
- **Exclude:** implementation details and configuration specifics. Keep characteristics high-level and focused on the differences between types.

## 3. Finding Your Way

- **Format:** a five-column table.
- **Columns:** Category · Need · Location · Content · Examples.
- **Groups (the Category values):** Understanding, Usage, Configuration.
- **Include:** links to the actual content, and concrete examples.
- **Constraints:** maximum 3–4 rows per category; keep examples specific; focus on common tasks; keep the structure consistent across rows.
