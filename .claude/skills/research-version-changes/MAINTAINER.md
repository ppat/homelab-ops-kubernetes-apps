# Maintaining research-version-changes

For maintainers of this skill, not for a run of it. Nothing here is loaded when the skill
runs. What is worth adding to a skill and what is not is in
[upgrade-chart-version's MAINTAINER.md](../upgrade-chart-version/MAINTAINER.md) and applies
here too.

## Contracts other things depend on

| Contract | Depends on it |
| --- | --- |
| Section titles and item layout in `references/report-format.md` | Callers that post sections of the report on pull requests, and upgrade-chart-version, which reads the report to plan |
| Script flags, exit codes (0 done, 2 bad input or ambiguous, 3 remote failure), and the fact that nothing is written on exit 2 or 3 | Any automation running the scripts unattended. A partial result must never look complete |
| `manifest.json` field names | Anything that judges coverage without reading the notes |
| `chart_diff.sh` output layout, in particular `crds.txt` states and the `crds/{from,to}/` pairs | upgrade-chart-version steps 4 and 5 and its planning checks |
| The report's sections and their order | The PR-comment use, which posts sections selectively |

Change any of these together with every caller.

## Design decisions

- **Scripts fetch, the model judges.** Everything deterministic (resolving tags, paging,
  slicing changelogs, diffing charts) is scripted so that no model tokens go to it.
  Classification against our usage stays with the model.
- **Tags come from `git ls-remote`**, one request with no API quota, which is also the
  denominator for coverage. Release bodies come from the list endpoint, then per-tag
  lookups only when the scan hit its page cap.
- **An ambiguous tag prefix aborts.** A wrong family returns plausible notes for the wrong
  thing, which nothing downstream catches. `--name` is a hard filter for the same reason.
- **Cleaning is narrow and always counted.** It drops contributor lists, compare links, bot
  bumps of CI actions, and other components' bullets in multi-family repos. Bot bullets in
  general stay, because a bot bumping the shipped image or a subchart is signal.
- **References are rewritten** (`#123` to `owner/repo#123`, `@user` into backticks)
  because reports get posted on this repo's pull requests.

## Gotchas found by testing against real repos

- **Monorepo numeric collisions.** In `grafana/helm-charts`, another chart's tags matched
  the requested FROM and TO when the intended chart lacked a FROM tag. In `grafana/loki`,
  old `helm-loki-3.x` chart tags collide with the app's `v3.x`.
- **Mirrored stub releases.** `grafana/helm-charts` publishes `helm-loki-*` releases whose
  body is only the chart description and a link to the source commit in `grafana/loki`,
  where the real notes are `production/helm/loki/CHANGELOG.md`. Twelve stubs in a row read
  as "nothing changed" unless flagged, hence `thin`, `source_hints` and the
  `NO CHANGE CONTENT FOUND` warning.
- **Monorepo release bodies list every chart's changes.** One `prometheus-community`
  release body ran to 125,000 characters, mostly other charts' bullets.
- **CRD churn is mostly prose.** Between Traefik chart releases most CRDs differed only in
  documentation links inside descriptions, hence the `docs-only` state.
- **Release-note generators mark breaking items differently.** release-please and
  semantic-release put them under a BREAKING CHANGES heading, changesets under "Major
  Changes", Keep a Changelog style under "Removed" or "Deprecated". goreleaser and GitHub's
  generated notes have no such heading, so only a conventional-commit `!` or the entry's
  wording carries it. Pull request references vary too: a pull or issue URL, `(#N)`,
  `in #N`, or none at all (semantic-release often links only commits). `flag_bullets` reads
  all of these, ranks them, and fetches descriptions for the most urgent within the cap.
- **A body that only links to the CHANGELOG is a stub.** The Flux controllers publish a
  changelog link plus container image boilerplate, which counted as content until the stub
  check learned to ignore link-only and packaging lines. The link's path then seeds the
  changelog fallback.
- **Release bodies that only list pull request titles.** `kubernetes-mcp-server` v0.0.68
  removed every runtime CLI flag under the title "Config rework". Nothing in the notes
  said so. A trial found it in the repo's `docs/configuration-changes.md` and by diffing
  where flags are registered in the source, which is why step 5 points there and the
  summary counts title-only bodies. The same project shipped two releases with identical
  bodies.
- **Operator charts are used through their CRs.** For external-secrets the usage that
  mattered was the `SecretStore` and `PushSecret` resources in both repos, not the
  HelmRelease values, and its changed CRD rules were only attributable to a provider once
  the CRD diff was keyed by YAML path.
- **Renders need help.** Flux post-build placeholders fail schema validation as literals
  (`--envsubst`), and charts check cluster capabilities (`--api-versions`). The same chart
  also dropped its Gateway API CRDs between majors, which only the CRD inventory showed.

## Testing a change to the scripts

Run against cases that exercise each path, each into its own empty directory:

| Case | Command shape |
| --- | --- |
| Single-family chart repo | `--repo traefik/traefik-helm-chart --from 40.0.0 --to 42.3.1` |
| Monorepo, component filter | `--repo cloudnative-pg/charts --name cloudnative-pg --from 0.26.0 --to 0.29.1` |
| Backports interleaved with mainline | `--repo coder/coder --from 2.37.10 --to 2.38.6` |
| Mirrored stubs and source hints | `--repo grafana/helm-charts --name loki --tag-prefix helm-loki- --from 6.20.0 --to 6.30.0` |
| Chart and app in one repo | `--repo grafana/loki --from 3.4.0 --to 3.5.0` must abort as ambiguous |
| Chart and app in one repo, chart notes are stubs | `--repo external-secrets/external-secrets --name external-secrets --tag-prefix helm-chart- --from 2.13.0 --to 2.14.0` must point at the `v` family |
| Title-only bodies, flagged pull requests, a repeated body | `--repo containers/kubernetes-mcp-server --from v0.0.67 --to v0.1.1` |
| Image source label | `--image ghcr.io/tautulli/tautulli:v2.15.0 --from 2.14.0 --to 2.15.0` without a token |
| Chart diff with our values | `chart_diff.sh` on Traefik with its HelmRelease values, `--envsubst --api-versions monitoring.coreos.com/v1` |
| OCI chart | `chart_diff.sh --repo oci://ghcr.io/dragonflydb/dragonfly-operator/helm/dragonfly-operator` |

`shellcheck` covers `chart_diff.sh` through pre-commit.
