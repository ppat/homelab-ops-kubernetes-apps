# What each source tells you, and how to read the script outputs

Several sources answer different questions. Don't conflate them. Each tells you something
the others don't.

| Source | What it tells you |
| --- | --- |
| Release notes, CHANGELOG | What the maintainers say changed, in their own words, including the deprecations and breaking changes they thought worth calling out |
| `values.yaml` | The chart's configurable surface and its defaults. Its *comments* are often the only place a value's intent or valid options are documented at all |
| `values.schema.json` | Which values are now rejected, required or constrained. A schema change breaks a render even when the notes say nothing |
| `Chart.yaml` | The chart's own metadata (its version, `appVersion`, `dependencies:` and `kubeVersion`) |
| The CRD spec, if the chart installs one | The schema a live CR is validated against. This is what actually breaks if a field's type or requiredness changed, independent of anything the chart's values do |
| The chart README's upgrade sections, `UPGRADE`/`MIGRATION` files | Where charts without real release notes write their breaking-change instructions |
| A docs-site migration guide | The next-best source when release notes are thin, when the project publishes one for exactly this transition. It is already synthesized by the maintainers rather than something you have to infer yourself |

Skipping straight to "diff the values.yaml" without also checking the release notes and the
CRD spec misses the two sources most likely to contain an actual breaking change. A values
diff shows what moved, not what now fails.

## Chart version vs. app version: don't expect both to be set

In this repo's HelmReleases, `spec.chart.spec.version` (the **chart** version) is almost
always the only version pinned. We rely on the chart to state which app version a given
chart version ships.

**The relationship between the two is asymmetric, not proportional.** A major app version
bump can be expected to be reflected in a major chart version bump, because chart
maintainers cut a new major chart release to carry a major app change. But the reverse
doesn't hold. A chart can bump its own major version many times over for reasons entirely
internal to the chart (values restructuring, a templating rework, a subchart dependency
change) with no corresponding app version change at all, sometimes not even a minor one.
Loki's chart went `7.0.0 → 18.5.1` (11 chart majors) while its app version moved only
`3.6.7 → 3.7.3` (one app minor), and nearly every breaking change in that jump was pure
chart-schema/values churn, not app behavior.

So the chart version number alone doesn't tell you *how much* changed, or on which side, and
regardless of which side moved more, both need checking. Confirm the app version range
explicitly (`chart_diff.sh` prints it) and do the chart-side
research either way. The chart's own notes, or its README's upgrade section, usually
capture the deployment-relevant implications of an app-level change, since that's
precisely the audience chart maintainers write for. Sometimes an app behavior change
doesn't show up as any chart-level values or schema difference at all, or the chart's docs
lag behind the app's. Then read the app's own release notes directly rather than assuming
the chart's notes are a complete proxy.

## Release notes cover every version, and a project's conventions don't change that

A deprecation introduced two versions back and only *removed* in the target is easy to miss
if you read just the final delta. Some projects ship breaking changes inside what looks like
a minor bump (Kubernetes itself, Flux, Longhorn and others use minor version numbers for
changes that would conventionally be "major" elsewhere), and some version by calendar, where
a year rolling over grades nothing. Rather than judging per project how fine-grained the
reading needs to be, the fetch script returns every version in range, oldest first, with
FROM's own release as a baseline. Read all of it.

## Rendered diffs: what the chart does with our values

The most direct way to see what changes for *this specific upgrade* is to render the chart
both ways and diff the output. `chart_diff.sh` compares them in three ways.

1. Both versions with no values, which shows what changed in the chart's own *defaults*.
   Useful for understanding the chart's evolution in general.
2. Both versions with this module's effective values, which shows what changes **for the
   config this repo actually ships**, the one that matters. If this render fails outright on
   the new version, that failure *is* the diagnostic signal. It is telling you a value this
   repo sets is no longer valid, before anyone has touched a manifest.
3. The diff between them, normalized (documents sorted, keys sorted, checksum annotations
   and version labels removed) so that ordering and label noise doesn't drown the change.
   CRDs are split out into their own inventory because they would dominate the diff.

### Building the effective values file

`yq '.spec.values' <helm-release>.yaml` gives the inline values. What it misses, which you
add or list as not covered:

- `spec.valuesFrom` (a ConfigMap or Secret merged in) and any cluster patches on the
  HelmRelease
- Flux post-build placeholders such as `${var:=default}`. Helm sees them as literal strings,
  and schema checks reject them. `--envsubst` resolves them through `flux envsubst`, in an
  emptied environment, and names every placeholder that had no default and so rendered
  empty. Supply a value for any that matter with `--var NAME=VALUE`, as a cluster's
  `postBuild.substitute` would. `flux envsubst` also parses comments. A valid
  `${var}` in a comment is silently replaced, and an invalid expression such as
  `${{ github.ref }}` fails the run, which the script reports with the file name
- cluster capabilities the chart checks for (a chart may refuse to render a
  `ServiceMonitor` without `monitoring.coreos.com/v1`), declared with `--api-versions`
- `spec.postRenderers` patches, which the script does not apply
- values that come from several layers (for example a provider component layered over base
  values). Pass each layer as its own `--values`, in order, and Helm merges them

A render with our values that fails on FROM usually means FROM is not the version these
values were written for, which is worth stating in Coverage.

## Templates are for diagnosis, not research

Reading the chart's template files is rarely useful while scoping what changed. Values,
release notes, the schema and the render diff already summarize them. Templates become
valuable later, when a rendered output or a live failure doesn't match what you expected
and you need to see *why* a template produced what it did.

## `chart_diff.sh` outputs

| File | Read it for |
| --- | --- |
| `chart-from.json`, `chart-to.json` | `appVersion`, `kubeVersion`, dependencies, `sources` and `home`, and the TO version's `artifacthub.io/changes` annotation (a structured change list some charts keep, covering TO only) |
| `chart-yaml.diff` | The full `Chart.yaml` diff, when the facts above are not enough |
| `values.diff` | Renamed, moved and removed keys and changed defaults, with the comments that explain them |
| `values-schema.diff` | New constraints. Large, but decisive when a render fails |
| `upgrade-notes.md` | The TO README's upgrading, migrating and breaking-change sections, plus any `UPGRADE*.md` or `MIGRATION*.md` |
| `render-ours.diff` | What changes in what we actually deploy. Usually short, and the most direct evidence there is |
| `render/<name>-<side>.err` | Why a render failed. A chart's `kubeVersion` constraint or a capability check is a common cause, which `--kube-version` and `--api-versions` address |
| `render-defaults.diff` | How the chart's own defaults moved. Read it when `render-ours.diff` is missing or something in it needs explaining |
| `crds.txt` | One line per CRD, marked `schema-changed`, `docs-only` (only descriptions or metadata differ), `unchanged`, `added` or `removed`, with served versions on both sides. Built from the render with our values when it succeeded, else from defaults, so a CRD gated behind a value can show as added or removed purely because of that value |
| `crds/<group>_<Kind>.paths.diff` | For a schema-changed CRD, one line per changed schema field keyed by its YAML path. Look up the fields our resources set |
| `crds/{from,to}/<group>_<Kind>.yml` | The normalized CRDs, for a full read of one we use |

## `fetch_release_notes.py` outputs

| File | Contents |
| --- | --- |
| `notes.md` | The baseline and every in-range version, oldest first, so a deprecation is read before its removal |
| `chunks/*.md` | The same, split at version boundaries when large, for reading in parallel |
| `pull-requests.md` | Descriptions of the pull requests behind flagged entries, most urgent first |
| `changelog.md` | In-range sections of a CHANGELOG file |
| `commits.md` | Commit subjects touching a path, bounded by FROM's commit date rather than ancestry, so backport-branch commits can appear |
| `manifest.json` | Per-version coverage (`release`, `thin`, `titles_only`, `duplicate_of`, `dropped`), fallbacks used, other components filtered against, source hints, warnings |

What cleaning drops is always counted, per version, in `manifest.json` and in a note under
the version. It drops contributor lists, "Full Changelog" compare links, bot entries that bump the
project's own CI actions, and, in a repo with several tag families, entries tagged only for
other components. That last drop applies only to large bodies (20,000 characters or more),
where a monorepo lists every component's changes, because in small bodies a scope that
happens to match another family's name (a chart's own `feat(CRDs):` entry beside a `crds`
tag family) would be dropped wrongly. `--raw` drops nothing, and still rewrites references.
