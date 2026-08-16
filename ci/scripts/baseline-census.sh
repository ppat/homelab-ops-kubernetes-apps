#!/usr/bin/env bash
#
# Reads the scheduled-baseline series: per-suite single-run failure rate with a 95% interval,
# plus the same rate broken out by time of day.
#
# An instrument nobody reads is worse than none, because it looks like coverage. This is the
# reader. Run it with no arguments.
#
#   ci/scripts/baseline-census.sh              per-suite summary, then per-hour
#   ci/scripts/baseline-census.sh --raw        one TSV row per sampled job, for other tools
#
# Two traps in the GitHub API, both of which have already produced wrong answers here:
#   - `gh run list` returns only the LATEST attempt of a run, so a failure that was later
#     re-run green disappears from a conclusion-filtered census. This walks every attempt.
#   - `updated_at` on the runs API is corrupt in this repo (runs reading hours or days long),
#     so every duration below comes from the jobs API instead.
set -euo pipefail

REPO="${REPO:-ppat/homelab-ops-kubernetes-apps}"
WORKFLOW="${WORKFLOW:-scheduled-baseline.yaml}"

raw=false
[[ "${1:-}" == "--raw" ]] && raw=true

rows="$(mktemp)"
trap 'rm -f "${rows}"' EXIT

# A sample is only a sample if it ran unchanging content: main, and not the pull_request run
# that exercises the planner on a branch. Counting those would contaminate the series with
# whatever the PR was changing, which is the exact failure this instrument exists to replace.
gh api --paginate "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?per_page=100" \
  --jq '.workflow_runs[]
        | select(.event != "pull_request" and .head_branch == "main")
        | [.id, .run_attempt] | @tsv' \
| while IFS=$'\t' read -r run_id attempts; do
    for ((n = 1; n <= attempts; n++)); do
      gh api --paginate "repos/${REPO}/actions/runs/${run_id}/attempts/${n}/jobs?per_page=100" \
        --jq '
          .jobs[]
          # "<suite> [<topology>] / test" -- the reusable-workflow job name. Without this the
          # planner job also matches, capture yields nothing, and every field shifts left into
          # a row that still looks plausible.
          | select(.name | test("^[a-z0-9-]+ \\[[a-z0-9-]+\\] / "))
          # cancelled and skipped are not observations of the suite; a timeout reports failure
          # and is one.
          | select(.conclusion == "success" or .conclusion == "failure")
          | select(.started_at != null and .completed_at != null)
          | [ (.name | capture("^(?<s>[a-z0-9-]+) \\[(?<t>[a-z0-9-]+)\\]") | .s),
              (.name | capture("^(?<s>[a-z0-9-]+) \\[(?<t>[a-z0-9-]+)\\]") | .t),
              .conclusion,
              (.started_at | fromdateiso8601 | strftime("%Y-%m-%d")),
              (.started_at | fromdateiso8601 | strftime("%H")),
              ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))
            ] | @tsv' \
        | sed "s/^/${run_id}\t${n}\t/"
    done
  done > "${rows}"

if [[ ! -s "${rows}" ]]; then
  echo "no baseline samples yet (workflow ${WORKFLOW} in ${REPO})" >&2
  exit 0
fi

if ${raw}; then
  printf 'run_id\tattempt\tsuite\ttopology\tconclusion\tdate\thour\tduration_s\n'
  cat "${rows}"
  exit 0
fi

# stdin: key <TAB> conclusion <TAB> duration_s, sorted by key.
# Wilson rather than the normal approximation: at these sample sizes and rates the normal
# interval is wrong, and wrong in the direction that understates the uncertainty.
report() {
  sort | awk -F'\t' '
    function wilson(k, n,   p, z, d, c, h, lo, hi) {
      z = 1.96; p = k / n; d = 1 + z * z / n
      c = (p + z * z / (2 * n)) / d
      h = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
      lo = c - h; hi = c + h
      if (lo < 0) lo = 0
      if (hi > 1) hi = 1
      return sprintf("%4.0f%% - %4.0f%%", 100 * lo, 100 * hi)
    }
    function flush() {
      if (key == "") return
      printf "%-32s %5d %5d %7.1f%%  %-14s %8d\n", key, n, f, 100 * f / n, wilson(f, n), secs / n
      tn += n; tf += f
    }
    $1 != key { flush(); key = $1; n = 0; f = 0; secs = 0 }
    { n++; secs += $3; if ($2 != "success") f++ }
    END {
      flush()
      if (tn > 0) printf "%-32s %5d %5d %7.1f%%  %-14s\n", "ALL", tn, tf, 100 * tf / tn, wilson(tf, tn)
    }'
}

printf '%-32s %5s %5s %8s  %-14s %8s\n' 'suite [topology]' 'n' 'fail' 'rate' '95% interval' 'mean s'
awk -F'\t' '{printf "%s [%s]\t%s\t%s\n", $3, $4, $5, $8}' "${rows}" | report

printf '\nby hour of day (UTC, when the job actually started)\n'
printf '%-32s %5s %5s %8s  %-14s %8s\n' 'hour' 'n' 'fail' 'rate' '95% interval' 'mean s'
awk -F'\t' '{printf "%s:00\t%s\t%s\n", $7, $5, $8}' "${rows}" | report
