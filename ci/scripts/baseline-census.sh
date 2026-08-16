#!/usr/bin/env bash
#
# Reads the scheduled-baseline series: per-suite single-run failure rate with a 95% interval,
# plus the same rate broken out by time of day.
#
# An instrument nobody reads is worse than none, because it looks like coverage. This is the
# reader. Run it with no arguments.
#
#   ci/scripts/baseline-census.sh                     per-suite summary, then per-hour
#   ci/scripts/baseline-census.sh --raw               one TSV row per sampled job, for other tools
#   ci/scripts/baseline-census.sh --since 2026-09-01  only jobs that started on or after a date
#   ci/scripts/baseline-census.sh --until 2026-09-30  only jobs that started on or before one
#
# --since and --until exist as a pair because the question this series is asked is comparative
# -- "did the change we landed lower the rate" -- and that needs a before window as well as an
# after one. A single pooled number can neither confirm nor refute it (see "what counts as a
# sample" below).
#
# Three traps in the GitHub API, every one of which has already produced a wrong answer here:
#   - `gh run list` returns only the LATEST attempt of a run, so a failure that was later
#     re-run green disappears from a conclusion-filtered census. This walks every attempt --
#     see "what counts as a sample" below for which of them the rate is computed from.
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
#
# What counts as a sample
#
# A designed sample is the FIRST attempt of a `schedule` run. Two things fail that test and
# both are somebody choosing when to sample:
#
#   - a manual dispatch. The workflow accepts one deliberately, so a debugging session that
#     dispatches a flaky suite ten times inside a bad hour would pour ten correlated samples
#     into a series whose entire claim is that nobody chose when to take them -- the
#     opportunistic sampling this instrument exists to replace, arriving through the
#     instrument itself.
#   - a re-run. `run_attempt > 1` keeps `event == schedule`, so the event alone is not the
#     discriminator. Nobody re-runs a green suite: an attempt 2 exists because attempt 1 was
#     red, so counting it adds a sample conditioned on the outcome of the sample beside it,
#     and it lands green often enough to pull the rate down. A spot check of this repo's run
#     history found six re-runs, five of them red-then-green; none on this workflow yet,
#     which is the cheapest moment to apply the rule. Attempts are still walked, because a
#     re-run that is invisible is worse than one that is excluded.
#
# Both are still printed by `--raw` -- with `event` and `attempt` columns -- and both are
# counted in the denominator note, so nothing is hidden; they are only kept out of the rate.
#
# The content is NOT constant across the series. Renovate merges into main most days, so a
# month of samples spans dozens of different fleets and content drift is confounded with time.
# What the series actually offers is content pinned at each sample, a published cadence, and n
# that grows -- not immutability. Hence --since/--until, and hence the revision count printed
# beside the denominator: a pooled rate is an average over every revision it pooled, and saying
# so is the difference between a number a reader can act on and one they can misread.
#
# Grouping the rate by revision was considered and rejected: a slot samples four to six suites,
# so a per-revision per-suite rate has an n near one and an interval compatible with anything.
# The revision is recorded per row instead, so a reader can bisect or aggregate as they choose.
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
since_date=''
until_date=''

# An unrecognised flag exits rather than being ignored: a mistyped `--sinse` that silently
# reported the whole series would answer a question nobody asked, in the format of the one
# they did.
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --raw) raw=true; shift ;;
    --since | --until)
      if [[ $# -lt 2 || ! "${2}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "baseline-census: ${1} needs a date as YYYY-MM-DD, got '${2:-}'" >&2
        exit 2
      fi
      if [[ "${1}" == '--since' ]]; then since_date="${2}"; else until_date="${2}"; fi
      shift 2
      ;;
    *)
      echo "baseline-census: unknown argument '${1}'; see the header for usage" >&2
      exit 2
      ;;
  esac
done

sampled="$(mktemp)"
rows="$(mktemp)"
window="$(mktemp)"
counted="$(mktemp)"
excluded="$(mktemp)"
undesigned="$(mktemp)"
trap 'rm -f "${sampled}" "${rows}" "${window}" "${counted}" "${excluded}" "${undesigned}"' EXIT

# Runs of this workflow against main. A `pull_request` run sits on the PR's branch, so the
# branch filter drops it -- its content is whatever the PR was changing, which is the exact
# contamination this instrument exists to replace. Should one ever arrive on a branch that is
# itself called main (a fork's), the event rule at report time still keeps it out of the rate.
# That rule lives there, not here, because a dispatched or re-run job is a real job that ran
# and belongs in `--raw`; it is only not a designed sample.
gh api --paginate "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?per_page=100" \
  --jq '.workflow_runs[]
        | select(.head_branch == "main")
        | [.id, .run_attempt, .event, .head_sha] | @tsv' \
| while IFS=$'\t' read -r run_id attempts event sha; do
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
        | sed "s/^/${run_id}\t${n}\t${event}\t${sha}\t/"
    done
  done > "${sampled}"

if [[ ! -s "${sampled}" ]]; then
  echo "no baseline samples yet (workflow ${WORKFLOW} in ${REPO})" >&2
  exit 0
fi

# Conclusion -> outcome. `cancelled` costs one extra API call per cancelled job and nothing
# otherwise, which is why it is resolved here rather than in the jq above.
while IFS=$'\t' read -r run_id attempt event sha job_id suite topology conclusion date hour duration; do
  case "${conclusion}" in
    success) outcome='pass' ;;
    failure | timed_out) outcome='fail' ;;
    cancelled) outcome="$(classify_cancelled "${job_id}")" ;;
    skipped | stale | action_required) outcome='not-run' ;;
    *) outcome="other:${conclusion}" ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${run_id}" "${attempt}" "${event}" "${sha}" "${job_id}" "${suite}" "${topology}" \
    "${conclusion}" "${outcome}" "${date}" "${hour}" "${duration}"
done < "${sampled}" > "${rows}"

# The window is applied to the job's own start date, not the run's creation date: a slot that
# GitHub delays across midnight would otherwise be filed under a day on which nothing ran.
awk -F'\t' -v since="${since_date}" -v until="${until_date}" \
  '(since == "" || $10 >= since) && (until == "" || $10 <= until)' "${rows}" > "${window}"

if ${raw}; then
  printf 'run_id\tattempt\tevent\thead_sha\tjob_id\tsuite\ttopology\tconclusion\toutcome\tdate\thour\tduration_s\n'
  cat "${window}"
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

# Three piles: counted, no-verdict, and not-designed. The last two are reported separately
# because they mean different things -- a job with no verdict is a sample the fleet failed to
# produce, a dispatched or re-run job is a verdict this series did not ask for -- and merging
# them would hide whichever is currently the larger.
awk -F'\t' -v keep="${counted}" -v drop="${excluded}" -v off="${undesigned}" \
  '{
     if ($3 != "schedule" || $2 != "1") { print > off }
     else if ($9 == "pass" || $9 == "fail" || $9 == "ceiling") { print > keep }
     else { print > drop }
   }' "${window}"

n_sampled="$(wc -l < "${window}")"
n_counted="$(wc -l < "${counted}")"
n_outside="$(( $(wc -l < "${rows}") - n_sampled ))"
n_revs="$(cut -f4 "${counted}" | sort -u | wc -l)"

if [[ "${n_counted}" -eq 0 ]]; then
  echo "no counted samples; see the denominator and exclusions below" >&2
else
  # `ceil` is broken out rather than merged into `fail` because it is a different defect with a
  # different fix -- an assertion that failed, against a suite that never got to assert.
  printf '%-32s %5s %5s %5s %8s  %-14s %8s\n' 'suite [topology]' 'n' 'fail' 'ceil' 'rate' '95% interval' 'mean s'
  awk -F'\t' '{printf "%s [%s]\t%s\t%s\n", $6, $7, $9, $12}' "${counted}" | report

  printf '\nby hour of day (UTC, when the job actually started)\n'
  printf '%-32s %5s %5s %5s %8s  %-14s %8s\n' 'hour' 'n' 'fail' 'ceil' 'rate' '95% interval' 'mean s'
  awk -F'\t' '{printf "%s:00\t%s\t%s\n", $11, $9, $12}' "${counted}" | report
fi

# The denominator, stated. A rate whose excluded set is invisible is the rate this script was
# rewritten to stop producing -- and the revision count is part of that denominator, because a
# rate pooled over many revisions of main is an average over that many different fleets. The
# dates printed are the first and last sample actually counted, not the requested window: an
# empty fortnight at either end of --since/--until would otherwise be reported as coverage.
windowed=''
if [[ -n "${since_date}" && -n "${until_date}" ]]; then
  windowed=" (windowed ${since_date}..${until_date})"
elif [[ -n "${since_date}" ]]; then
  windowed=" (windowed from ${since_date})"
elif [[ -n "${until_date}" ]]; then
  windowed=" (windowed to ${until_date})"
fi
if [[ "${n_counted}" -eq 0 ]]; then
  # "0 of 0" alone cannot tell an empty series from a window aimed at the wrong dates, so the
  # jobs the window rejected are stated rather than left to be inferred from silence.
  printf '\n0 of %d sampled jobs are counted%s' "${n_sampled}" "${windowed}"
  if [[ "${n_outside}" -gt 0 ]]; then
    printf '; %d sampled jobs lie outside it' "${n_outside}"
  fi
  printf '.\n'
else
  printf '\n%d of %d sampled jobs are counted above: first attempt of a schedule run only, %s to %s%s.\n' \
    "${n_counted}" "${n_sampled}" \
    "$(cut -f10 "${counted}" | sort | head -1)" \
    "$(cut -f10 "${counted}" | sort | tail -1)" "${windowed}"
fi
if [[ "${n_revs}" -gt 1 ]]; then
  printf 'They pool %d revisions of main -- content moved under the series, so this is an average\n' "${n_revs}"
  printf 'over %d fleets, not a measurement of one. Narrow it with --since/--until.\n' "${n_revs}"
fi
if [[ -s "${undesigned}" ]]; then
  echo 'excluded -- ran on main, but somebody chose to take the sample, so it is not in the rate:'
  awk -F'\t' '{printf "%s [%s]\t%s\n", $6, $7, ($3 != "schedule" ? $3 : "re-run attempt " $2)}' \
    "${undesigned}" | sort | uniq -c \
    | awk '{printf "  %5d  %-24s %s\n", $1, $2 " " $3, substr($0, index($0, $4))}'
fi
if [[ -s "${excluded}" ]]; then
  echo 'excluded -- these jobs never reached a verdict, so they are neither pass nor fail:'
  awk -F'\t' '{printf "%s [%s]\t%s\n", $6, $7, $9}' "${excluded}" | sort | uniq -c \
    | awk '{printf "  %5d  %-24s %s\n", $1, $2 " " $3, $4}'
fi
if awk -F'\t' '$3 == "schedule" && $9 ~ /^(cancel-unclassified|other:)/ {found = 1} END {exit !found}' "${window}"; then
  cat >&2 <<'EOF'

WARNING: some jobs above are `cancel-unclassified` or `other:*`. Every rate printed is
conditional on them. A ceiling kill whose annotation GitHub reworded would land there, so
read a nonzero count as data not yet read -- not as noise.
EOF
fi
