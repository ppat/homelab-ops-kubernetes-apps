#!/usr/bin/env bash
#
# Merges the release-please PRs a human click has been shown to add nothing to, and only those.
#
# Why it exists: 23 months of history (931 release PRs) show the manual merge of a
# non-breaking release PR expressed no judgement, ever -- zero refusals, zero edits; every one
# eventually landed byte-identical. The judgement that does exist in that history is
# version-class, not module identity: every deliberate hold was a breaking release. So the
# sweep automates exactly the rubber-stamp class and leaves the judgement class alone. A tag
# is also not a deployment: both downstream clusters pin exact tags and adopt them through
# their own hand-merged deploy PRs, so the blast radius of a wrongly-cut tag is an unused ref.
#
# Cadence (set by the workflow, not here): apps-* modules sweep Wednesdays 00:00 UTC,
# infra-* modules Sundays 12:00 UTC. One weekly run handles every eligible PR of its class:
# batch merging is evidenced, not assumed -- release-please's release phase picks up all
# merged-but-untagged release PRs in one run (observed at batch size 5 automated and up to 16
# in manual sittings; 906/906 historical releases got their tags).
#
# THE RULE -- a release PR is merged when ALL of these hold, and left for the maintainer
# otherwise. Every guard fails toward "skip", never toward "merge"; skipping is normal, not an
# error. In order of evaluation:
#
#   1. NON-BREAKING BUMP, decided per module from release-please-config.json and the
#      manifest -- never hardcoded "patch only":
#        - a PATCH bump (x.y.Z -> x.y.Z+1) is always eligible: no configuration makes a
#          patch breaking;
#        - a MINOR bump (x.Y.0 with Y = current+1) is eligible UNLESS it means breaking for
#          this module right now: below 1.0.0 with `bump-minor-pre-major: true` (today: all
#          21 packages), breaking changes bump minor and feat bumps patch, so a minor is
#          *exclusively* breaking and waits for a human. The moment a module's manifest
#          version reaches 1.0.0 that flag stops applying, minor reverts to meaning feat,
#          and this check makes the module's minors eligible with no edit here;
#        - anything else -- major bumps, version jumps, first releases, unparsable titles --
#          waits for a human.
#   2. NO HOLD: the PR carries no `automerge:off` label (the hold vocabulary Renovate PRs
#      already use in this repo, applied here by a human to park a release indefinitely).
#   3. NOT MANUAL-LISTED: the module is not in $MANUAL_MODULES (a standing per-module
#      opt-out, distinct from the per-PR label; populated in the workflow env).
#   4. ALL CHECKS GREEN: for every distinct check NAME on the PR head, the newest run of
#      that name completed with success/skipped/neutral, and the combined commit status is
#      not failing. Newest-per-name is the same resolution branch protection applies -- a
#      re-run leaves its superseded cancelled/failed attempt visible in the API (measured on
#      #3674: `pr-title` CANCELLED and SUCCESS side by side after a re-run), and a stale
#      attempt must not veto its own green retry. All checks, not just required contexts --
#      deliberately stricter than branch protection, matching the all-green semantics of
#      Renovate's own merge path rather than `allow_auto_merge`'s required-only semantics.
#   5. NOT STALE: no commit has landed on main touching the module's release-please path
#      since release-please last built the PR (checked as: the PR head's parent is an
#      ancestor of main, and `parent..main` touches nothing under the module path). This
#      closes the race where a breaking commit has landed but release-please has not yet
#      escalated the PR title. The false-negative side (a hidden-type commit touches the
#      path, release-please leaves the PR alone, the sweep skips until the next visible
#      commit) is accepted: it fails toward the human.
#
# There is deliberately NO chainsaw-suite gate. Release PRs carry no suite to evaluate --
# their diff (CHANGELOG + manifest) sits outside every test-*.yaml path filter -- so the
# "nothing auto-lands with failing suites" constraint is inapplicable here rather than
# violated, exactly as it is for today's manual merges of the same PRs. The property lives
# upstream: content PRs run their module's suite, the bot has never merged one over a red
# suite (0 of 17 measured), and the human red-merges on record were each the deliberate fix
# for the red. An earlier revision of this script gated on scheduled-baseline samples; it was
# removed as a maintainer decision -- under a weekly cadence, two suites' ~40% single-run
# flake would have blocked their modules for a week at a time.
#
# The merge uses GitHub's REST pull-request merge endpoint -- the same endpoint Renovate used to
# bypass this ruleset as its authorized App. The App's bypass remains the server-side authority;
# the endpoint grants none. `sha` pins the merge to the evaluated head, so a PR that
# release-please force-pushes between evaluation and merge is skipped rather than merged
# sight-unseen.
#
# Requires: GH_TOKEN = the homelab bot APP token, not GITHUB_TOKEN -- pushes made with a
# workflow's own GITHUB_TOKEN do not trigger workflows, so a GITHUB_TOKEN merge would never
# fire release.yaml's push event and no tag would ever be cut. Also requires a full-history
# checkout of main at its current tip (the staleness guard walks `parent..origin/main`).
#
# Usage:
#   DRY_RUN=false MODULE_CLASS=apps|infra ci/scripts/release-sweep.sh   # live (CI only)
#   MODULE_CLASS=apps|infra ci/scripts/release-sweep.sh                 # dry-run
#
# DRY_RUN defaults to TRUE: evaluate and report every decision, merge nothing. Merging
# requires BOTH an explicit DRY_RUN=false AND running inside GitHub Actions -- a local
# invocation can never merge, whatever its environment says. (This is not hypothetical: an
# unguarded local test run of an earlier revision of this script merged five live release
# PRs. The guard exists so that the careless invocation is the safe one.)
# Exit status: 0 unless an attempted merge failed (skips are not failures; an empty queue is
# not a failure).
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-ppat/homelab-ops-kubernetes-apps}"
DRY_RUN="${DRY_RUN:-true}"
if [[ "${DRY_RUN}" != "true" && "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "release-sweep: not running inside GitHub Actions -- forcing DRY_RUN=true" >&2
  DRY_RUN="true"
fi
# Anything other than an explicit "false" means dry-run.
[[ "${DRY_RUN}" == "false" ]] || DRY_RUN="true"

# Which module class this run handles: "apps" or "infra". Required, with no default and no
# wider class: each of the workflow's cron entries maps explicitly to apps or infra, and a
# set-but-empty value is the workflow signalling a schedule its cron->class mapping did not
# recognize -- so unset or empty must fail here rather than silently select a behaviour.
MODULE_CLASS="${MODULE_CLASS:-}"
case "${MODULE_CLASS}" in
  apps|infra) ;;
  '') echo "release-sweep: MODULE_CLASS is unset or empty -- the workflow's cron->class mapping did not recognize the schedule that fired; update the MODULE_CLASS expression to match the edited cron" >&2
      exit 1 ;;
  *) echo "release-sweep: MODULE_CLASS must be apps or infra (got '${MODULE_CLASS}')" >&2
     exit 1 ;;
esac
MANUAL_MODULES="${MANUAL_MODULES:-}"

CONFIG="release-please-config.json"
MANIFEST=".release-please-manifest.json"
[[ -f "${CONFIG}" && -f "${MANIFEST}" ]] || {
  echo "release-sweep: run from the repository root of a main checkout" >&2
  exit 1
}

# --- decision helpers ----------------------------------------------------------------------
checks_green() {
  local sha="$1" runs n ok status
  runs="$(gh api "repos/${REPO}/commits/${sha}/check-runs?per_page=100" \
    --jq '[(.total_count | tostring), ([.check_runs | group_by(.name)[] | max_by(.started_at) | .status == "completed" and (.conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral")] | all | tostring)] | @tsv')"
  IFS=$'\t' read -r n ok <<< "${runs}"
  # Zero check runs: not evaluated yet. More than one page: this jq judged only the first
  # 100, so refuse to call it green (release PRs carry ~15 today; this is a tripwire).
  [[ "${n}" -gt 0 && "${n}" -le 100 && "${ok}" == "true" ]] || return 1
  status="$(gh api "repos/${REPO}/commits/${sha}/status" --jq '[.state, (.total_count | tostring)] | @tsv')"
  local state count
  IFS=$'\t' read -r state count <<< "${status}"
  # Release PRs have zero commit statuses (measured: state "pending", total_count 0), so the
  # empty case must pass -- only a real failing status may hold.
  [[ "${state}" == "success" || "${count}" == "0" ]]
}

path_stale() {
  local sha="$1" path="$2" parent
  parent="$(git rev-parse --quiet --verify "${sha}^" 2>/dev/null)" || return 0
  git merge-base --is-ancestor "${parent}" origin/main || return 0
  [[ "$(git rev-list --count "${parent}..origin/main" -- "${path}")" != "0" ]]
}

# --- the sweep -----------------------------------------------------------------------------
summary_row() {
  printf '| #%s | %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" "$5" >> "${SUMMARY_FILE}"
  echo "release-sweep: PR #$1 ${2} v${3}: ${4} ${5:+(${5})}"
}

SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
  echo "## release-sweep $(date -u '+%Y-%m-%dT%H:%M:%SZ') (class: ${MODULE_CLASS}, dry-run: ${DRY_RUN})"
  echo ""
  echo "| PR | module | version | decision | reason |"
  echo "| --- | --- | --- | --- | --- |"
} >> "${SUMMARY_FILE}"

prs="$(gh pr list --repo "${REPO}" --label 'pr-type:release' --state open \
  --json number,title,labels,headRefOid,headRefName --limit 100 \
  --jq '.[] | [.number, .title, ([.labels[].name] | join(",")), .headRefOid, .headRefName] | @tsv')"

merge_failures=0
if [[ -z "${prs}" ]]; then
  echo "release-sweep: no open release PRs"
fi

while IFS=$'\t' read -r number title labels head_sha head_ref; do
  [[ -n "${number}" ]] || continue

  if [[ ! "${title}" =~ ^chore\(release\):\ release\ ([a-z0-9-]+)\ v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    summary_row "${number}" "?" "?" "skip" "title does not parse: ${title}"
    continue
  fi
  module="${BASH_REMATCH[1]}"
  new_major="${BASH_REMATCH[2]}"; new_minor="${BASH_REMATCH[3]}"; new_patch="${BASH_REMATCH[4]}"
  version="${new_major}.${new_minor}.${new_patch}"

  case "${MODULE_CLASS}" in
    apps)  [[ "${module}" == apps-* ]] || continue ;;
    infra) [[ "${module}" == infra-* ]] || continue ;;
  esac

  path="$(jq -r --arg m "${module}" \
    '.packages | to_entries[] | select(.value.component == $m) | .key' "${CONFIG}")"
  if [[ -z "${path}" ]]; then
    summary_row "${number}" "${module}" "${version}" "skip" "module not in ${CONFIG}"
    continue
  fi

  current="$(jq -r --arg p "${path}" '.[$p] // empty' "${MANIFEST}")"
  if [[ -z "${current}" ]]; then
    summary_row "${number}" "${module}" "${version}" "skip" "first release -- human's"
    continue
  fi
  IFS=. read -r cur_major cur_minor cur_patch <<< "${current}"

  # Guard 1: version class, resolved per module (header, rule 1).
  if [[ "${new_major}" == "${cur_major}" && "${new_minor}" == "${cur_minor}" \
        && "${new_patch}" == "$((cur_patch + 1))" ]]; then
    bump="patch"
  elif [[ "${new_major}" == "${cur_major}" && "${new_minor}" == "$((cur_minor + 1))" \
        && "${new_patch}" == "0" ]]; then
    bump="minor"
  else
    bump="other"
  fi
  if [[ "${bump}" == "minor" ]]; then
    minor_pre_major="$(jq -r --arg p "${path}" \
      '.packages[$p]["bump-minor-pre-major"] // false' "${CONFIG}")"
    if [[ "${cur_major}" == "0" && "${minor_pre_major}" == "true" ]]; then
      summary_row "${number}" "${module}" "${version}" "skip" "minor over ${current} is breaking for this module -- human's"
      continue
    fi
  elif [[ "${bump}" != "patch" ]]; then
    summary_row "${number}" "${module}" "${version}" "skip" "not a patch/minor bump over ${current} -- human's"
    continue
  fi

  if [[ ",${labels}," == *",automerge:off,"* ]]; then
    summary_row "${number}" "${module}" "${version}" "skip" "automerge:off hold"
    continue
  fi

  if [[ " ${MANUAL_MODULES} " == *" ${module} "* ]]; then
    summary_row "${number}" "${module}" "${version}" "skip" "MANUAL_MODULES"
    continue
  fi

  if ! checks_green "${head_sha}"; then
    summary_row "${number}" "${module}" "${version}" "skip" "checks not all green on ${head_sha:0:8}"
    continue
  fi

  git fetch --quiet origin "${head_ref}" < /dev/null || true
  if path_stale "${head_sha}" "${path}"; then
    summary_row "${number}" "${module}" "${version}" "skip" "main moved under ${path} since PR was built"
    continue
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    summary_row "${number}" "${module}" "${version}" "would merge" "${bump} bump over ${current}"
    continue
  fi

  if gh api --method PUT "repos/${REPO}/pulls/${number}/merge" \
      -f sha="${head_sha}" -f merge_method=squash < /dev/null; then
    summary_row "${number}" "${module}" "${version}" "merged" "${bump} bump over ${current}"
  else
    # A refused merge because the head moved (release-please force-pushed mid-sweep) is the
    # designed outcome of the REST API's sha guard, not a malfunction: report it as a skip and
    # let the next sweep re-evaluate. Anything else is a real failure and reddens the run.
    now_head="$(gh pr view "${number}" --repo "${REPO}" --json headRefOid --jq .headRefOid 2>/dev/null || echo unknown)"
    if [[ "${now_head}" != "${head_sha}" ]]; then
      summary_row "${number}" "${module}" "${version}" "skip" "head moved during sweep (now ${now_head:0:8})"
    else
      summary_row "${number}" "${module}" "${version}" "MERGE FAILED" "see log"
      merge_failures=$((merge_failures + 1))
    fi
  fi
done <<< "${prs}"

if [[ "${merge_failures}" -gt 0 ]]; then
  echo "release-sweep: ${merge_failures} merge(s) failed" >&2
  exit 1
fi
