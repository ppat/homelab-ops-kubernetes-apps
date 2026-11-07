# Maintaining research-version-changes

This file is for changing the skill, not for running it. Nothing here is loaded when the
skill runs.

## Dependency direction

Other skills and automation use this skill. This skill never references them or their
files, and knows nothing about the repo that calls it. How a deployable is configured and
used is an input the caller supplies, never something this skill goes looking for.

## Contracts other things depend on

| Contract | Who depends on it |
| --- | --- |
| Section titles, order and item layout in `references/report-format.md` | Callers that read the report to plan, and automation that posts selected sections on pull requests |
| One artifact per run, with Coverage stating the app version range and whether the chart notes cover it | Callers that decide whether to research the app as a second run |
| Script flags, and exit codes 0 done, 2 bad input or ambiguous, 3 remote failure | Anything running the scripts unattended |
| Nothing is written to `--out` on exit 2 or 3 | The same. A partial result must never look complete |
| `manifest.json` field names | Anything that judges coverage without reading the notes |
| `chart_diff.sh` output layout, including `crds.txt` states and `crds/{from,to}/` | Callers that read the chart outputs directly, for example to research CRD specs |

Change any of these together with every caller.

## Design decisions

- **Scripts fetch, the model judges.** Everything deterministic is scripted so that no model
  tokens go to it. Judging relevance against the supplied usage stays with the model.
- **Tags come from `git ls-remote`.** One request, no API quota, and it is the denominator
  for coverage. Release bodies come from the release list, with per-tag lookups only when the
  scan hit its page cap.
- **An ambiguous tag family aborts, and `--name` is a hard filter.** A wrong family returns
  plausible notes for the wrong thing, which nothing downstream can catch.
- **Charts come from `helm pull`, not a clone of their source repo.** It returns exactly what
  the Helm repository serves for that version, with `values.yaml`, `Chart.yaml` and the
  README comments intact, and needs no guess at the source repo's tag scheme. A clone is
  worth it only for what `helm pull` can't give, such as commit history or a version the
  repository no longer serves.
- **Release notes come from the GitHub API, not web pages.** The release body is small,
  structured text, cheaper than any page.
- **Releases are matched to versions, not to tag names.** One version can carry two tag
  spellings, with the release on either.
- **FROM's own release is read as a baseline.** Deprecations announced at FROM can still be
  pending at TO.
- **Cleaning is narrow and always counted.** It drops only what never carries a change
  (contributor lists, compare links, bot bumps of the project's own CI actions, and other
  components' entries in large monorepo bodies). Bot entries in general stay, because a bot
  bumping the shipped image or a subchart is signal.
- **References are rewritten** (`#123` to `owner/repo#123`, `@user` into backticks) so that
  reports are safe to post in another repo. Pull request descriptions come from the issues
  endpoint, which serves both, because some generators link pull requests as issues.
- **Flagging ranks rather than filters.** Every entry with a breaking marker, an attention
  heading or attention wording is flagged. The cap then keeps the most urgent, and the summary
  says how many it left out.

## Gotchas found against real repos

These are why the scripts behave as they do. Each is a mechanism likely to recur under
another project's name.

- **A tag number can belong to more than one thing.** A repo that ships a chart and an app
  can have old chart tags that collide with the app's current versions, and in a chart
  monorepo another chart's tags can match FROM and TO when the intended chart lacks a FROM
  tag.
- **Stub releases read as "nothing changed".** Chart-releaser style bodies hold only the
  chart's description and a source-commit link, often to another repo where the real notes
  live. Other projects publish only a link to their CHANGELOG plus container image
  boilerplate. Hence the `thin` flag, source hints, the CHANGELOG fallback seeded from the
  link, and the `NO CHANGE CONTENT FOUND` warning.
- **Bodies that only list pull request titles hide breaking changes.** A release that
  removed every runtime flag of a server said only "Config rework". Hence the title-only
  count, the pull request fetch, and the instruction to compare option definitions in source.
- **Release-note generators mark breaking items differently.** release-please and
  semantic-release use a BREAKING CHANGES heading, changesets "Major Changes", Keep a
  Changelog "Removed" and "Deprecated". goreleaser and GitHub's generated notes have no such
  heading, so only a conventional-commit `!` or the entry's wording carries it. Pull request
  references come as a pull or issue URL, `(#N)`, `in #N`, or not at all (semantic-release
  often links only commits). An entry's reference can sit on its continuation line.
- **Monorepo release bodies list every component's changes.** One body ran to 125,000
  characters, nearly all of it for other charts.
- **Most CRD churn between chart releases is prose.** Descriptions and doc links change in
  almost every CRD, so the inventory separates `docs-only` from `schema-changed` and keys
  schema changes by YAML path.
- **Renders need help.** Flux post-build placeholders fail schema validation as literal
  strings, and charts check for cluster capabilities before rendering some resources.

## Testing a change to the scripts

Run each case into its own new, empty directory. All of these behaved as stated when the
scripts were written.

| Case | Command shape | Expected |
| --- | --- | --- |
| Single-family chart repo | `--repo traefik/traefik-helm-chart --from 40.0.0 --to 42.3.1` | 25 versions, family `v` |
| Monorepo family by name | `--repo cloudnative-pg/charts --name cloudnative-pg --from 0.26.0 --to 0.29.1` | family `cloudnative-pg-v` |
| `--name` is a hard filter | `--repo grafana/helm-charts --name pyroscope --from 2.2.0 --to 2.4.3` | family `pyroscope-`, never another chart |
| Backports interleaved with mainline | `--repo coder/coder --from 2.37.10 --to 2.38.6` | 7 versions |
| Mirrored stubs | `--repo grafana/helm-charts --name loki --tag-prefix helm-loki- --from 6.20.0 --to 6.30.0` | all `thin`, source hint `grafana/loki`, `NO CHANGE CONTENT FOUND` |
| Their real source | `--repo grafana/loki --name loki --tag-prefix helm-loki- --path production/helm/loki --from 6.20.0 --to 6.30.0` | `changelog.md` and `commits.md` |
| Chart and app collide | `--repo grafana/loki --from 3.4.0 --to 3.5.0` | exit 2, nothing written |
| Chart stubs, app notes in the same repo | `--repo external-secrets/external-secrets --name external-secrets --tag-prefix helm-chart- --from 2.13.0 --to 2.14.0` | `thin`, warning naming the `v` family |
| Body that only links to a CHANGELOG | `--repo fluxcd/kustomize-controller --tag-prefix v --from 1.9.6 --to 1.10.1` | `thin`, `changelog.md` sliced from the linked file |
| goreleaser `!` marker | `--repo github/github-mcp-server --from v1.14.0 --to v2.1.0` | `pull-requests.md` holds `github/github-mcp-server#3445` |
| `in #N` under a Breaking heading | `--repo kubernetes-sigs/external-dns --tag-prefix v --from 0.21.0 --to 0.23.0` | `pull-requests.md` holds `kubernetes-sigs/external-dns#6424` |
| Release tag spelled `v2.1` for `v2.1.0` | `--repo dragonflydb/dragonfly --tag-prefix v --from 1.40.2 --to 2.1.0` | 3 versions, `release_tag` `v2.1` |
| release-please | `--repo googleapis/release-please --tag-prefix v --from 16.18.0 --to 17.0.0` | breaking entry at rank 0, `googleapis/release-please#2490` fetched |
| Title-only and repeated bodies | `--repo containers/kubernetes-mcp-server --from v0.0.67 --to v0.1.1` | 4 title-only, 1 duplicate |
| Image source label, no token | `--image ghcr.io/tautulli/tautulli:v2.15.0 --from 2.14.0 --to 2.15.0` with tokens unset | resolves `Tautulli/Tautulli` |
| Image without a source label | `--image ghcr.io/containers/kubernetes-mcp-server:v0.1.1 ...` | exit 2 suggesting `--repo` |
| Empty range | `--repo coder/coder --from 2.38.0 --to 2.38.0` | exit 2, nothing written |
| Render with supplied values | `chart_diff.sh` on traefik 41.0.0 to 42.2.0 with a values file holding Flux placeholders, `--envsubst --api-versions monitoring.coreos.com/v1` | both renders succeed, short `render-supplied.diff` |
| Invalid placeholder in a comment | `chart_diff.sh --envsubst` with `${{ github.ref }}` in a values comment | exit 2 naming the file, nothing written |
| OCI chart | `chart_diff.sh --repo oci://ghcr.io/dragonflydb/dragonfly-operator/helm/dragonfly-operator --from v1.1.11 --to v1.3.0` | succeeds |
| CRD schema changes keyed by path | `chart_diff.sh --repo https://charts.external-secrets.io --chart external-secrets --from 2.13.0 --to 2.14.0` | 4 `schema-changed`, `paths.diff` naming provider fields |

## Known limitations

- Any rate limit or non-404 API error aborts the run with exit 3, including while fetching
  pull request descriptions.
- Pull request descriptions are cut at 20,000 characters, with a marker.
- The stub and boilerplate checks are heuristics. A short real note that mentions only an
  image ref can read as a stub.
- Changelog slicing reads markdown `#` headings that contain a version. Setext headings,
  bold-line version headings and changelogs that interleave several components are not
  sliced.
- Commit subjects are bounded by date, not ancestry.
- The CRD inventory comes from renders. When neither the supplied values nor the defaults render on
  both sides, it is reported unavailable, without falling back to the chart's `crds/`
  directory.

## What's worth adding, and what isn't

The same discipline as any skill that has to stay general:

- A transferable mechanism, not a one-off fact. "Stub releases read as nothing changed"
  belongs. Which project published which stub belongs in the test table at most.
- A method, not a conclusion. "Compare where options are defined between FROM and TO" is a
  method. What one release changed belongs in the report that found it.
- An approach, not an answer, and no symptom lookup table.
- A situation is not a section. A run will meet projects the text never names. Add text only
  when a run exposed a wrong statement, a contradiction, a silent miss in a script, or a
  transferable mechanism.
- Validate a change by running the skill fresh, in a new session, on a real range. The
  session that wrote the change fills its gaps from its own context and cannot see them.
