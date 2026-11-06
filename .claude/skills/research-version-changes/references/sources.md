# Sources and how to read the script outputs

Each source answers a different question. Skipping one misses what only it says.
Breaking changes hide mostly in the release notes, the CRD spec and `values.schema.json`.
A values diff shows what moved, not what now fails.

| Source | What it tells you |
| --- | --- |
| Release notes, CHANGELOG | What the maintainers say changed, including the deprecations and breaking changes they chose to call out |
| `values.yaml` | The chart's configurable surface and defaults. Its comments are often the only documentation of what a value means and which options are valid |
| `values.schema.json` | Which values are now rejected, required or constrained. A schema change breaks a render even when the notes say nothing |
| `Chart.yaml` | Chart version, `appVersion`, `kubeVersion` and subchart `dependencies` |
| CRD spec | The schema live custom resources are validated against. A changed field type or requiredness breaks an existing CR independently of any value |
| Chart README upgrade sections | Where charts without real release notes write their breaking-change instructions |
| A docs-site migration guide | The next-best source when notes are thin, already synthesized by the maintainers for exactly this transition |

## Chart version and app version move independently

This repo pins only the chart version (`spec.chart.spec.version`) and takes the app version
from the chart's `appVersion`. The two are related asymmetrically. A major app change
normally arrives in a major chart release, but a chart can cut many majors for its own
reasons (values restructuring, templating rework, subchart changes) while the app barely
moves. Loki's chart went from 7.0.0 to 18.5.1 while the app went from 3.6.7 to 3.7.3, and
nearly every breaking change in that jump was chart values churn. The chart version alone
says neither how much changed nor on which side, so check both.

## `chart_diff.sh` outputs

| File | Read it for |
| --- | --- |
| `chart-from.json`, `chart-to.json` | `appVersion`, `kubeVersion`, dependencies, `sources` and `home` (the summary prints both on one line), and the TO version's `artifacthub.io/changes` annotation (a structured change list some charts maintain, covering TO only) |
| `values.diff` | Renamed, moved and removed keys, changed defaults, with the comments that explain them |
| `values-schema.diff` | New constraints. Large but decisive when a render fails |
| `upgrade-notes.md` | The TO README's upgrading, migrating and breaking-change sections, plus any `UPGRADE*.md` or `MIGRATION*.md` |
| `render-ours.diff` | What changes in what we actually deploy. Usually short, and the most direct evidence there is |
| `render/ours-<side>.err` | A render that fails with our values. On the TO side that is a finding (a value we set is no longer valid). On the FROM side it usually means FROM is not the version these values were written for |
| `render-defaults.diff` | How the chart's own defaults moved. Read it when `render-ours.diff` is missing or something in it needs explaining |
| `crds/<group>_<Kind>.paths.diff` | For each `schema-changed` CRD, one line per changed schema leaf keyed by its YAML path, so a field our resources set can be looked up directly |
| `crds.txt` | One line per CRD: `schema-changed`, `docs-only` (descriptions or metadata only), `unchanged`, `added`, `removed`, with served versions on each side. Built from the render with our values when it succeeded, else from defaults, so a CRD gated behind a value can show as added or removed purely because of that value |
| `crds/{from,to}/<group>_<Kind>.yml` | The normalized CRDs. Diff a pair only for CRDs we create resources of |

CRDs are kept out of both render diffs because they dominate them.

### Building the values file

`yq '.spec.values' <helm-release>.yaml > values.yaml` gives the inline values. Things it
misses, which you must add or list as not covered:

- `spec.valuesFrom` (a ConfigMap or Secret merged in) and consuming clusters' patches on
  the HelmRelease.
- Flux post-build placeholders such as `${traefik_log_level:=INFO}`. Helm sees them as
  literal strings and schema checks reject them. `--envsubst` resolves them through
  `flux envsubst`. A placeholder without a default resolves to empty unless you export a
  value for it.
- Cluster capabilities the chart checks for (it may refuse to render a `ServiceMonitor`
  without `monitoring.coreos.com/v1`). Declare them with `--api-versions`.

## `fetch_release_notes.py` outputs

| File | Contents |
| --- | --- |
| `notes.md` | Every in-range version, oldest first, so a deprecation is read before its removal |
| `chunks/*.md` | The same, split at version boundaries when large, for fan-out |
| `changelog.md` | In-range sections of a CHANGELOG file |
| `pull-requests.md` | Descriptions of pull requests whose release-note titles carry a breaking marker (`feat!:`, `feat(x)!:`, `feat!(x):`) or mention breaking, deprecating, removing or dropping. A title-only heuristic, so it misses changes whose titles say nothing ("Config rework") |
| `commits.md` | Commit subjects touching a path, bounded by FROM's commit date rather than ancestry, so backport-branch commits can appear |
| `manifest.json` | Per-version coverage (release present, `thin`, `titles_only`, `duplicate_of`, what was dropped), fallbacks used, `other_components` (the names whose bullets the component filter drops), `source_hints`, warnings |

A release whose body repeats the previous one verbatim is shown once, with a pointer, so
that it does not read as a second set of changes.

What cleaning drops, always counted per version in `manifest.json` and in a note under
each version:

- contributor lists and "made their first contribution" lines
- "Full Changelog" compare links
- bot bullets that bump the project's own CI actions
- in a repo with several tag families, bullets whose leading `[component]` or
  `type(component):` tag names only other families

`--raw` drops nothing.

## Templates are for diagnosis, not research

Reading the chart's templates is rarely worth it while scoping what changed, because values,
notes and the render diff already summarize them. They earn their cost later, when a render
or a live failure does not match expectations and you need to see why.
