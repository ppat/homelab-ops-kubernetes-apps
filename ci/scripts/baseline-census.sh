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
# Three traps in the GitHub API, every one of which has already produced a wrong answer here:
#   - `gh run list` returns only the LATEST attempt of a run, so a failure that was later
#     re-run green disappears from a conclusion-filtered census. This walks every attempt.
#   - `updated_at` on the runs API is corrupt in this repo (runs reading hours or days long),
#     so every duration below comes from the jobs API instead.
#   - a `timeout-minutes` kill reports as `cancelled`, NOT as `failure`. Filtering on failure
#     therefore drops the single worst thing a suite can do, and drops it hardest exactly when
#     the fleet is slowest -- which is when a rate is being read. An earlier census in this
#     repo answered "zero ceiling kills in 8508 runs" for that reason and was believed.
#
# So every conclusion the jobs API documents is enumerated here, and anything not on the list
# falls through to `other:<conclusion>` and is printed. An unrecognised category has to be
# visible in the output; the alternative is what the third trap above already cost.
#
#   success          the suite passed                                    counted, pass
#   failure          the suite failed                                    counted, fail
#   timed_out        Actions abandoned the job; no verdict reached       counted, fail
#   cancelled        ambiguous -- resolved per job, see classify_cancelled
#   skipped          the job never ran                                   excluded
#   stale            never dispatched; the run aged out of the queue     excluded
#   action_required  held at a manual gate; the suite did not run        excluded
#   neutral          no suite here emits one                             excluded, printed
#   null             still running                                       excluded (no completed_at)
#
# Only `success`, `failure` and `cancelled` have actually been seen on these jobs; the rest are
# enumerated from the API's documented set so that a first sighting cannot pass unnoticed.
# `startup_failure` is a run-level conclusion only, and such a run has no jobs, so it
# contributes no rows rather than needing a case here.
set -euo pipefail

REPO="${REPO:-ppat/homelab-ops-kubernetes-apps}"
WORKFLOW="${WORKFLOW:-scheduled-baseline.yaml}"

# Splits `cancelled` on the job's check-run annotations, which is the only reliable seam.
#
# A ceiling kill and a concurrency cancel are indistinguishable everywhere else: both leave the
# job `cancelled`, the chainsaw step `cancelled` and every other step `success` -- identical
# field for field. Duration looks like a discriminator and is not one; it needs each job's
# ceiling as it stood when that job ran, which the API does not carry and which is not constant
# in this repo (the reusable workflow defaults to 15m, six suites declare 25m, and both numbers
# appear in history). The annotation states the ceiling itself, so nothing is assumed about it.
#
# What would make this wrong: GitHub rewording either message. That degrades to
# `cancel-unclassified`, which is printed rather than folded into the rate -- the failure mode
# is a visibly unread sample, not a quietly better-looking number.
classify_cancelled() {
  local messages
  messages="$(gh api "repos/${REPO}/check-runs/${1}/annotations" \
    --jq '[.[].message] | join(" ")' 2>/dev/null || true)"
  case "${messages}" in
    # First: a job killed at the ceiling while a cancel was also in flight is still a job that
    # reached the ceiling.
    *"exceeded the maximum execution time"*) echo 'ceiling' ;;
    *"higher priority waiting request"*) echo 'cancel-concurrency' ;;
    *) echo 'cancel-unclassified' ;;
  esac
}

raw=false
[[ "${1:-}" == "--raw" ]] && raw=true

sampled="$(mktemp)"
rows="$(mktemp)"
counted="$(mktemp)"
excluded="$(mktemp)"
trap 'rm -f "${sampled}" "${rows}" "${counted}" "${excluded}"' EXIT

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
          | select(.started_at != null and .completed_at != null)
          | [ .id,
              (.name | capture("^(?<s>[a-z0-9-]+) \\[(?<t>[a-z0-9-]+)\\]") | .s),
              (.name | capture("^(?<s>[a-z0-9-]+) \\[(?<t>[a-z0-9-]+)\\]") | .t),
              .conclusion,
              (.started_at | fromdateiso8601 | strftime("%Y-%m-%d")),
              (.started_at | fromdateiso8601 | strftime("%H")),
              ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))
            ] | @tsv' \
        | sed "s/^/${run_id}\t${n}\t/"
    done
  done > "${sampled}"

if [[ ! -s "${sampled}" ]]; then
  echo "no baseline samples yet (workflow ${WORKFLOW} in ${REPO})" >&2
  exit 0
fi

# Conclusion -> outcome. `cancelled` costs one extra API call per cancelled job and nothing
# otherwise, which is why it is resolved here rather than in the jq above.
while IFS=$'\t' read -r run_id attempt job_id suite topology conclusion date hour duration; do
  case "${conclusion}" in
    success) outcome='pass' ;;
    failure | timed_out) outcome='fail' ;;
    cancelled) outcome="$(classify_cancelled "${job_id}")" ;;
    skipped | stale | action_required) outcome='not-run' ;;
    *) outcome="other:${conclusion}" ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${run_id}" "${attempt}" "${job_id}" "${suite}" "${topology}" \
    "${conclusion}" "${outcome}" "${date}" "${hour}" "${duration}"
done < "${sampled}" > "${rows}"

if ${raw}; then
  printf 'run_id\tattempt\tjob_id\tsuite\ttopology\tconclusion\toutcome\tdate\thour\tduration_s\n'
  cat "${rows}"
  exit 0
fi

# stdin: key <TAB> outcome <TAB> duration_s, sorted by key, counted outcomes only.
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
      if (key == "" || n == 0) return
      printf "%-32s %5d %5d %5d %7.1f%%  %-14s %8d\n", key, n, f, c, 100 * f / n, wilson(f, n), secs / n
      tn += n; tf += f; tc += c
    }
    $1 != key { flush(); key = $1; n = 0; f = 0; c = 0; secs = 0 }
    { n++; secs += $3; if ($2 != "pass") f++; if ($2 == "ceiling") c++ }
    END {
      flush()
      if (tn > 0) printf "%-32s %5d %5d %5d %7.1f%%  %-14s\n", "ALL", tn, tf, tc, 100 * tf / tn, wilson(tf, tn)
    }'
}

awk -F'\t' -v keep="${counted}" -v drop="${excluded}" \
  '{print > ($7 == "pass" || $7 == "fail" || $7 == "ceiling" ? keep : drop)}' "${rows}"

n_sampled="$(wc -l < "${rows}")"
n_counted="$(wc -l < "${counted}")"

if [[ "${n_counted}" -eq 0 ]]; then
  echo "none of the ${n_sampled} sampled jobs reached a verdict; see the exclusions below" >&2
else
  # `ceil` is broken out rather than merged into `fail` because it is a different defect with a
  # different fix -- an assertion that failed, against a suite that never got to assert.
  printf '%-32s %5s %5s %5s %8s  %-14s %8s\n' 'suite [topology]' 'n' 'fail' 'ceil' 'rate' '95% interval' 'mean s'
  awk -F'\t' '{printf "%s [%s]\t%s\t%s\n", $4, $5, $7, $10}' "${counted}" | report

  printf '\nby hour of day (UTC, when the job actually started)\n'
  printf '%-32s %5s %5s %5s %8s  %-14s %8s\n' 'hour' 'n' 'fail' 'ceil' 'rate' '95% interval' 'mean s'
  awk -F'\t' '{printf "%s:00\t%s\t%s\n", $9, $7, $10}' "${counted}" | report
fi

# The denominator, stated. A rate whose excluded set is invisible is the rate this script was
# rewritten to stop producing.
printf '\n%d of %d sampled jobs are counted above.\n' "${n_counted}" "${n_sampled}"
if [[ -s "${excluded}" ]]; then
  echo 'excluded -- these jobs never reached a verdict, so they are neither pass nor fail:'
  awk -F'\t' '{printf "%s [%s]\t%s\n", $4, $5, $7}' "${excluded}" | sort | uniq -c \
    | awk '{printf "  %5d  %-24s %s\n", $1, $2 " " $3, $4}'
fi
if awk -F'\t' '$7 ~ /^(cancel-unclassified|other:)/ {found = 1} END {exit !found}' "${rows}"; then
  cat >&2 <<'EOF'

WARNING: some jobs above are `cancel-unclassified` or `other:*`. Every rate printed is
conditional on them. A ceiling kill whose annotation GitHub reworded would land there, so
read a nonzero count as data not yet read -- not as noise.
EOF
fi
