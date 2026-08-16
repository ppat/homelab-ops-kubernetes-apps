#!/usr/bin/env bash
#
# Persists the diagnostics lines every chainsaw suite emits, so that reading them costs nothing.
#
# Every suite emits a shared grammar (READY / RESTART / PULL / CONTENTION / UNCENSORED, published
# in TESTING.md) on every run, pass or fail. Until this script existed none of it survived: the
# lines lived only as stdout in a workflow log on 90-day retention, and reading them meant a
# multi-agent log-archaeology exercise per question. That cost is why the data went unread.
#
#   harvest    read the instrument lines out of a run's job logs -> TSV on stdout
#   summarize  turn that TSV into the markdown table the run page shows
#   collect    concatenate the TSVs of past slots -> one TSV on stdout
#
# WHY IT LIVES HERE AND NOT IN THE SUITES. The sixteen test-*.yaml workflows have no steps of
# their own -- they call ppat/github-workflows, so nothing can be added to them from this repo.
# scheduled-baseline.yaml does own plain jobs, so a job added to it can read its siblings' logs
# through the API once they are terminal. Producer and consumer therefore meet at exactly one
# thing: the published line grammar. Nothing else is shared, and no cross-repo change is needed.
#
# WHAT IT MUST NEVER DO. The instrumentation's design rests on probing at the boundaries of a run
# and never inside one -- a mid-run probe would be the contention it claims to measure. This runs
# after the suites, on its own runner, and touches nothing they use. It must also never be able
# to gate anything: see the `harvest` job in scheduled-baseline.yaml.
#
# Two GitHub API traps, both of which have already produced wrong answers in this repo:
#   - `gh run list` returns only the LATEST attempt of a run. Everything here walks attempts.
#   - a `timeout-minutes` kill reports conclusion `cancelled`, not `failure`, and emits no
#     instrument lines at all. That absence is information, so such jobs get a row saying so
#     rather than being dropped.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="${REPO:-ppat/homelab-ops-kubernetes-apps}"
API="${API:-https://api.github.com}"
WORKFLOW="${WORKFLOW:-scheduled-baseline.yaml}"

# THE PARSER CONTRACT. These prefixes are published in TESTING.md ("What every run emits, and how
# to read it") and printed by ci/test/chainsaw/scripts/*. They are the only coupling between the
# suites and this script, which is why the grammar is frozen in a doc rather than agreed here.
#
# Deliberately a prefix allowlist and not a field parser: the TSV keeps each line whole, so a
# suite adding a field to CONTENTION does not break retention -- only the summary, which degrades
# to a dash. MODE is listed ahead of its emitter existing for the same reason: carrying a token
# costs nothing, and dropping data silently costs a slot nobody knows is missing.
#
# report-cnpg.sh is deliberately NOT here. It emits `--- CNPG: ... ---` headers around raw
# operator logs, not grammar lines; the #3678 discriminator is a human judgment the instrument
# informs rather than encodes.
#
# The allowlist matches on the prefix only, never on what follows it, and that is load-bearing:
# UNCENSORED alone has four marks in the emitter (`+`, `~`, `never`, `gone`) where TESTING.md
# lists three, and the `--- UNCENSORED: ... ---` banner has already been reworded once between
# two runs eight minutes apart. Retention must not depend on either.
# ADDING A PREFIX TO TESTING.md's TABLE MEANS ADDING IT HERE, or the line is retained nowhere.
# That obligation is stated beside the table too, because this is the one coupling a prefix
# allowlist cannot detect on its own: an unlisted prefix does not error, it just never arrives.
INSTRUMENT_RE='^(READY|RESTART|PULL[A-Z-]*|CONTENTION|UNCENSORED[A-Z-]*|MODE|ESO[A-Z]*) '

# The baseline job's own name, set by scheduled-baseline.yaml as "<suite> [<topology>]". In-repo,
# so this coupling is ours. It is what separates the sampled suites from the plan/harvest jobs.
BASELINE_JOB_RE='^([a-z0-9-]+) \[([a-z0-9-]+)\]'

# Bounds. Every one of them is loud when it bites -- a truncated harvest that looked complete
# would be worse than none, because it would read as coverage.
SWEEP_MAX_RUNS="${SWEEP_MAX_RUNS:-150}"       # hard cap on swept runs per slot
SWEEP_MAX_HOURS="${SWEEP_MAX_HOURS:-24}"      # widest window, if the previous slot is far back
SWEEP_MIN_RATE="${SWEEP_MIN_RATE:-300}"       # skip the sweep below this much rate-limit headroom
CURL_MAX_TIME="${CURL_MAX_TIME:-120}"
OWN_LOG_RETRIES="${OWN_LOG_RETRIES:-5}"       # own-run logs may lag job completion; see below

TSV_HEADER=$'run_id\tattempt\tjob_id\tevent\tbranch\tworkflow\tsuite\ttopology\tconclusion\tstarted_at\tduration_s\tts\tkind\tline'

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[[ -n "${TOKEN}" ]] || TOKEN="$(gh auth token 2>/dev/null || true)"

WORK="$(mktemp -d)"
# shellcheck disable=SC2064  # expand WORK now: the trap must survive whatever reassigns it later
trap "rm -rf '${WORK}'" EXIT

log() { printf 'harvest: %s\n' "$*" >&2; }

# Emits one TSV row. Every `line` begins with its own `kind`, so a row stays self-describing when
# it is grepped out of the file on its own.
row() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

# --- log retrieval -------------------------------------------------------------------------
#
# curl rather than `gh api`: gh refuses to write a response containing terminal escape sequences
# without a flag whose availability varies by gh version, and the HTTP status is needed as data.
# "log unavailable" has to be a state this script can report, not an empty file indistinguishable
# from a run that emitted nothing.
#
# Retries exist for one specific uncertainty: whether a job's log is downloadable the moment the
# job goes terminal. The `needs:` gate buys only runner-provisioning time. They apply to the
# harvester's own run only -- in a sweep a 404 is permanent (expired or deleted), and retrying it
# would spend the budget on the one thing that cannot succeed.
fetch_job_log() {
  local job_id="$1" out="$2" retries="$3"
  local tries=0 code delay=3
  while :; do
    code="$(curl -sSL -o "${out}" -w '%{http_code}' \
      -H "Authorization: Bearer ${TOKEN}" \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      --max-time "${CURL_MAX_TIME}" \
      "${API}/repos/${REPO}/actions/jobs/${job_id}/logs" 2>/dev/null)" || code=000
    [[ "${code}" == "200" ]] && break
    tries=$((tries + 1))
    [[ ${tries} -gt ${retries} ]] && break
    log "job ${job_id} log http=${code}; retry ${tries}/${retries} in ${delay}s"
    sleep "${delay}"
    delay=$((delay * 2))
  done
  printf '%s' "${code}"
}

# stdin: a raw job log. stdout: "<ts>\t<kind>\t<line>" for every instrument line.
# The API prefixes every log line with an RFC3339 timestamp; it is kept, because it is the only
# absolute clock the lines have -- READY's T0+ offsets are relative to that run's own earliest
# transition, so they compare between runs of a suite and against nothing else.
#
# Three framing facts, all measured against real logs rather than assumed: the API prefixes every
# line with an RFC3339 timestamp carrying seven fractional digits; chainsaw indents its own output
# by eight spaces after that; and the first byte of the file is a UTF-8 BOM, which would otherwise
# make the first line the only one whose timestamp does not parse.
extract_lines() {
  sed -e '1s/^\xef\xbb\xbf//' -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\r//g' \
    | awk -v re="${INSTRUMENT_RE}" '
        {
          ts = ""; rest = $0
          if (match($0, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]+Z /)) {
            ts = substr($0, 1, RLENGTH - 1)
            rest = substr($0, RLENGTH + 1)
          }
          sub(/^[ \t]+/, "", rest)
          sub(/[ \t]+$/, "", rest)
          if (rest !~ re) next
          kind = rest
          sub(/[ \t].*$/, "", kind)
          gsub(/[ \t]+/, " ", rest)
          print ts "\t" kind "\t" rest
        }'
}

# A ceiling kill is a `cancelled` job carrying a check-run annotation naming the ceiling. Recorded
# verbatim, with no interpretation: `cancelled` alone cannot separate a ceiling kill from a human
# pressing cancel, and guessing which is how a census produces a confident wrong number.
job_annotation() {
  local job_id="$1" msg
  msg="$(gh api "repos/${REPO}/check-runs/${job_id}/annotations" \
    --jq '[.[] | .message] | join("; ")' 2>/dev/null || true)"
  printf '%s' "${msg:0:300}" | tr '\t\n' '  '
}

# --- the suite <- workflow map -------------------------------------------------------------
#
# Swept runs are named by their workflow (`test-infrastructure-storage / test`) while baseline
# jobs are named by their suite (`infra-storage [multi-node]`), and the two do not agree. The
# planner already reads every suite's real inputs out of its own workflow, so the mapping comes
# from there rather than being restated here -- restating is the failure baseline-plan.sh exists
# to prevent, and a second, weaker extractor would be exactly that.
declare -A SUITE_OF=() TOPOLOGY_OF=()
load_suite_map() {
  local plan wf suite topology
  plan="$(WORKFLOW_DIR="${ROOT}/.github/workflows" "${ROOT}/ci/scripts/baseline-plan.sh" all 2>/dev/null)" \
    || { log "suite map unavailable; swept rows will carry suite=?"; return 0; }
  while IFS=$'\t' read -r wf suite topology; do
    [[ -n "${wf}" ]] || continue
    SUITE_OF["${wf}"]="${suite}"
    TOPOLOGY_OF["${wf}"]="${topology}"
  done < <(printf '%s' "${plan}" | jq -r '.include[] | [.workflow, .suite, .topology] | @tsv' 2>/dev/null)
}

# --- harvesting one run --------------------------------------------------------------------
#
# $1 run_id  $2 attempt  $3 event  $4 branch  $5 workflow path  $6 own-run (true|false)
harvest_run() {
  local run_id="$1" attempt="$2" event="$3" branch="$4" wf_path="$5" own="$6"
  local retries=0 jobs job_id name conclusion started duration suite topology
  local logf linesf code n status payload parsed

  # An `if`, not `[[ ... ]] && x=y`. The AND-list form is exempt from `set -e` only because the
  # test is not the list's final command, which is a rule worth not depending on in a script
  # whose whole job is to not fail quietly.
  if [[ "${own}" == "true" ]]; then
    retries="${OWN_LOG_RETRIES}"
  fi

  jobs="$(gh api --paginate "repos/${REPO}/actions/runs/${run_id}/attempts/${attempt}/jobs?per_page=100" \
    --jq '.jobs[]
          | select(.conclusion == "success" or .conclusion == "failure" or .conclusion == "cancelled")
          | select(.started_at != null)
          | [ .id, .name, .conclusion, .started_at,
              (if .completed_at then ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)) else "" end)
            ] | @tsv' 2>/dev/null)" \
    || { log "run ${run_id} attempt ${attempt}: jobs API failed"; return 0; }

  while IFS=$'\t' read -r job_id name conclusion started duration; do
    [[ -n "${job_id}" ]] || continue

    if [[ "${name}" =~ ${BASELINE_JOB_RE} ]]; then
      suite="${BASH_REMATCH[1]}"
      topology="${BASH_REMATCH[2]}"
    elif [[ "${own}" == "true" ]]; then
      # This workflow's own `plan` and `harvest` jobs. Giving them rows would put two permanent
      # "no instrument lines" entries in every slot's table and train the reader to skip past
      # exactly the column the table exists to show.
      continue
    else
      suite="${SUITE_OF[$(basename "${wf_path}")]:-?}"
      topology="${TOPOLOGY_OF[$(basename "${wf_path}")]:-?}"
    fi

    logf="${WORK}/${job_id}.log"
    linesf="${WORK}/${job_id}.lines"
    code="$(fetch_job_log "${job_id}" "${logf}" "${retries}")"
    : > "${linesf}"
    n=0
    parsed=true
    if [[ "${code}" == "200" && -s "${logf}" ]]; then
      # Guarded, and the guard is the point: under `set -e` a failing extractor would abort this
      # loop, and every job after it would vanish from the TSV with nothing saying it was ever
      # there. A harvest that is silently short is the one failure this design cannot tolerate.
      if extract_lines < "${logf}" > "${linesf}"; then
        n="$(wc -l < "${linesf}" | tr -d ' ')"
      else
        parsed=false
      fi
    fi

    # The status vocabulary. Anything other than `ok` is a claim about WHY there is less data here
    # than a healthy run leaves behind, and the summary decides from it whether to raise a banner.
    #
    # A suite that reached the chainsaw phase must leave a CONTENTION start (bootstrap-flux), a
    # CONTENTION end (emitted by both the pass step and the shared catch) and at least one READY.
    # Testing for those three by necessary consequence is what makes a broken instrument visible:
    # a parser that only ever reports what it found produces a tidy table with a quietly empty
    # column, which is the exact failure this whole exercise exists to prevent.
    if [[ "${code}" != "200" ]]; then
      status="log-unavailable"
    elif [[ ! -s "${logf}" ]]; then
      status="log-empty"
    elif ! ${parsed}; then
      status="parse-failed"
    elif [[ "${n}" -eq 0 ]]; then
      status="no-lines"
    elif awk -F'\t' '
           $3 ~ /^CONTENTION start/ { s = 1 }
           $3 ~ /^CONTENTION end/   { e = 1 }
           $3 ~ /^READY /           { r = 1 }
           END { exit !(s && e && r) }' "${linesf}"; then
      status="ok"
    else
      status="partial"
    fi

    payload="JOB status=${status} lines=${n} http=${code} name=${name}"
    if [[ "${conclusion}" == "cancelled" ]]; then
      payload="${payload} annotation=$(job_annotation "${job_id}")"
    fi

    row "${run_id}" "${attempt}" "${job_id}" "${event}" "${branch}" "${wf_path}" \
      "${suite}" "${topology}" "${conclusion}" "${started}" "${duration}" \
      "${started}" "JOB" "${payload}"

    while IFS=$'\t' read -r ts kind line; do
      row "${run_id}" "${attempt}" "${job_id}" "${event}" "${branch}" "${wf_path}" \
        "${suite}" "${topology}" "${conclusion}" "${started}" "${duration}" \
        "${ts}" "${kind}" "${line}"
    done < "${linesf}"

    rm -f "${logf}" "${linesf}"
  done <<< "${jobs}"
}

# --- the wider sweep -------------------------------------------------------------------------
#
# Measured before being built: over 2026-08-15..16 the repo produced ~289 test-* runs in 36h,
# i.e. ~48 suite jobs in a six-hour slot, and a suite job's log is ~180 KB. That is ~100 API
# calls and ~10 MB per slot against a 1000/hour token budget -- affordable, so it exists.
#
# It earns its complexity for one reason: the UNCENSORED lines only exist on failures, failures
# are overwhelmingly on PR-triggered runs, and a slot's own five jobs yield perhaps two of them.
# The failure-path data lives in the sweep or nowhere.
#
# What it is NOT for: rates. A PR run samples whatever that PR changed, which is precisely the
# contaminated measurement scheduled-baseline exists to replace. The `event` and `branch` columns
# exist so that nobody joins the two populations by accident.
sweep() {
  local since="$1" own_run_id="$2"
  local remaining runs run_id attempt event branch wf_path harvested=0

  sweep_row() {
    row "${own_run_id}" "" "" "" "" "" "" "" "" "${since}" "" "${since}" "SWEEP" "SWEEP $1"
  }

  remaining="$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null || echo 0)"
  if [[ "${remaining}" -lt "${SWEEP_MIN_RATE}" ]]; then
    log "sweep skipped: rate-limit remaining=${remaining} < ${SWEEP_MIN_RATE}"
    sweep_row "status=skipped reason=rate-limit remaining=${remaining} since=${since}"
    return 0
  fi

  runs="$(gh api --paginate "repos/${REPO}/actions/runs?per_page=100&created=%3E${since}" \
    --jq '.workflow_runs[]
          | select(.path | test("^\\.github/workflows/test-.*\\.yaml$"))
          | [.id, .run_attempt, .event, .head_branch, .path] | @tsv' 2>/dev/null)" \
    || { log "sweep failed: runs API"; sweep_row "status=failed reason=runs-api since=${since}"; return 0; }

  while IFS=$'\t' read -r run_id attempt event branch wf_path; do
    [[ -n "${run_id}" ]] || continue
    [[ "${run_id}" == "${own_run_id}" ]] && continue
    if [[ ${harvested} -ge ${SWEEP_MAX_RUNS} ]]; then
      log "sweep truncated at ${SWEEP_MAX_RUNS} runs"
      sweep_row "status=truncated cap=${SWEEP_MAX_RUNS} since=${since}"
      return 0
    fi
    # Every attempt, not just the latest: a failure later re-run green is invisible otherwise,
    # and those are the runs carrying the UNCENSORED lines this sweep is for.
    local n
    for ((n = 1; n <= attempt; n++)); do
      harvest_run "${run_id}" "${n}" "${event}" "${branch}" "${wf_path}" false
    done
    harvested=$((harvested + 1))
  done <<< "${runs}"

  sweep_row "status=complete runs=${harvested} since=${since}"
}

# The window is the previous slot rather than a fixed six hours, so a slot GitHub skipped or
# delayed leaves no hole; capped at SWEEP_MAX_HOURS so a long outage cannot turn one harvest into
# a week-long crawl.
sweep_since() {
  local own_created="$1" prev floor
  floor="$(date -u -d "${SWEEP_MAX_HOURS} hours ago" '+%Y-%m-%dT%H:%M:%SZ')"
  # Strictly before this run, not merely "not this run": a slot harvested out of order -- a
  # re-run, or a hand invocation against an old run id -- would otherwise take its window from a
  # LATER slot and sweep nothing at all, while reporting status=complete.
  prev="$(gh api "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?per_page=50" \
    --jq "[.workflow_runs[] | select(.event != \"pull_request\") | select(.created_at < \"${own_created}\") | .created_at] | sort | reverse | .[0] // empty" \
    2>/dev/null || true)"
  if [[ -z "${prev}" || "${prev}" < "${floor}" ]]; then
    printf '%s' "${floor}"
  else
    printf '%s' "${prev}"
  fi
}

# --- subcommands -----------------------------------------------------------------------------

cmd_harvest() {
  local run_id="${GITHUB_RUN_ID:-}" attempt="${GITHUB_RUN_ATTEMPT:-1}" do_sweep=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run) run_id="$2"; shift 2 ;;
      --attempt) attempt="$2"; shift 2 ;;
      --sweep) do_sweep=true; shift ;;
      *) log "unknown option $1"; return 2 ;;
    esac
  done
  [[ -n "${run_id}" ]] || { log "no run id: pass --run <id> or set GITHUB_RUN_ID"; return 2; }
  [[ -n "${TOKEN}" ]] || { log "no token: set GH_TOKEN/GITHUB_TOKEN or run gh auth login"; return 2; }

  local meta event branch wf_path created
  meta="$(gh api "repos/${REPO}/actions/runs/${run_id}" --jq '[.event, .head_branch, .path, .created_at] | @tsv' 2>/dev/null)" \
    || { log "run ${run_id}: metadata unavailable"; return 1; }
  IFS=$'\t' read -r event branch wf_path created <<< "${meta}"

  load_suite_map
  printf '%s\n' "${TSV_HEADER}"
  harvest_run "${run_id}" "${attempt}" "${event}" "${branch}" "${wf_path}" true
  if ${do_sweep}; then
    sweep "$(sweep_since "${created}")" "${run_id}"
  fi
}

# Reads a harvest TSV and writes the markdown the run page shows. This is the only grammar-aware
# part -- it reads fields out of lines -- and it is deliberately tolerant: an unreadable field
# becomes a dash while the TSV still holds the line verbatim, so a grammar change costs a column
# rather than a slot.
#
# MODE is retained but deliberately not given a column. It is already emitted on an unlanded
# branch and this harvester captured it on its first sweep, which is exactly the point of a prefix
# allowlist -- but its field layout is not in TESTING.md yet, and the contract this reads is the
# published one. Add the column when the line is published, not before.
cmd_summarize() {
  local tsv="${1:-}" own="${GITHUB_RUN_ID:-}"
  if [[ -z "${tsv}" || ! -s "${tsv}" ]]; then
    printf '### Harvest\n\n> [!WARNING]\n'
    printf '> **No harvest TSV was produced.** The harvester ran and wrote nothing, so this\n'
    printf "> slot's instrument lines exist only in the sibling job logs, for 90 days.\n"
    return 0
  fi
  awk -F'\t' -v own="${own}" '
    # value of key=<token> in a payload; "" when absent
    function field(s, key,   v) {
      if (!match(s, key "=[^ ]*")) return ""
      v = substr(s, RSTART, RLENGTH)
      sub(/^[^=]*=/, "", v)
      return v
    }
    # value of key=<rest of line>, for free text that must come last in the payload
    function field_rest(s, key,   v) {
      if (!match(s, key "=.*$")) return ""
      v = substr(s, RSTART, RLENGTH)
      sub(/^[^=]*=/, "", v)
      return v
    }
    function d(v) { return (v == "" ? "-" : v) }
    function pair(a, b) {
      if (a == "" && b == "") return "-"
      if (b == "") return a
      return a " -> " b
    }

    NR == 1 && $1 == "run_id" { next }
    $13 == "SWEEP" { sweep_note = field_rest($14, "status"); next }

    {
      key = $1 "/" $2 "/" $3
      if (!(key in seen)) {
        seen[key] = 1; order[++nk] = key
        rid[key] = $1; suite[key] = $7; topo[key] = $8
        concl[key] = $9; dur[key] = $11
      }
    }
    $13 == "JOB" {
      status[key] = field($14, "status")
      annot[key] = field_rest($14, "annotation")
      next
    }
    $13 == "READY" {
      ready_n[key]++
      if (match($14, /T0\+[0-9]+/)) {
        v = substr($14, RSTART + 3, RLENGTH - 3) + 0
        if (v > ready_last[key]) ready_last[key] = v
      }
      next
    }
    $13 == "RESTART"  { split($14, a, " "); restarts[key] += a[2] + 0; next }
    $13 == "PULL"     { split($14, a, " "); pull_n[key]++; if (a[3] + 0 > pull_max[key]) pull_max[key] = a[3] + 0; next }
    $13 == "CONTENTION" {
      split($14, a, " ")
      w = (a[2] == "start") ? "s" : "e"
      net[key, w] = field($14, "net_mbps")
      fsy[key, w] = field($14, "fsync_us")
      split(field($14, "loadavg"), b, ",")
      lav[key, w] = b[1]
      if (w == "e") elapsed[key] = field($14, "elapsed_s")
      next
    }
    $13 == "UNCENSORED-SUMMARY" {
      unc[key] = "notready=" field($14, "notready") " max=" field($14, "max_extra_s") "s"
      next
    }

    function line_for(key,   ready, pulls, st) {
      ready = (ready_n[key] > 0) ? ready_last[key] "s" : ""
      pulls = (pull_n[key] > 0) ? sprintf("%d / %.0fs", pull_n[key], pull_max[key]) : ""
      st = (status[key] == "ok") ? "ok" : "**" status[key] "**"
      return sprintf("| %s [%s] | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
        suite[key], topo[key], concl[key], d(dur[key]), d(elapsed[key]), d(ready),
        d(restarts[key] ? restarts[key] : ""), d(pulls),
        pair(net[key, "s"], net[key, "e"]), pair(fsy[key, "s"], fsy[key, "e"]),
        d(lav[key, "e"]), d(unc[key]), st)
    }

    END {
      hdr = "| suite [topology] | outcome | job s | chainsaw s | last ready | restarts | pulls / slowest | net mbps | fsync us | load end | uncensored | status |"
      sep = "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"

      print "### Harvest"
      print ""
      print "This slot:"
      print ""
      print hdr
      print sep
      for (i = 1; i <= nk; i++) { k = order[i]; if (rid[k] == own) { print line_for(k); nslot++ } }
      if (nslot == 0) print "| _none_ | | | | | | | | | | | |"

      for (i = 1; i <= nk; i++) {
        k = order[i]
        if (rid[k] == own) continue
        nsw++
        if (concl[k] != "success" || status[k] != "ok") bad[++nswbad] = k
      }
      print ""
      if (sweep_note != "") {
        print "Sweep of other workflow runs since the previous slot: `" sweep_note "`, " nsw " suite job(s) harvested."
        if (nswbad > 0) {
          print ""
          print hdr
          print sep
          for (i = 1; i <= nswbad; i++) print line_for(bad[i])
          print ""
          print "_Only non-success or non-`ok` swept jobs are shown; every swept job is in the TSV._"
          print ""
          print "**These are not rate samples.** A PR run measures whatever that PR changed -- the"
          print "contaminated measurement scheduled-baseline exists to replace. Read them for the"
          print "lines (`UNCENSORED`, `PULL`, `CONTENTION`), never for a failure rate."
        }
      } else {
        print "Sweep: not run."
      }

      # The loud part. A status other than `ok` on a job that SUCCEEDED means the instrument
      # failed rather than the run, and that is the one state a tidy-looking table would hide.
      for (i = 1; i <= nk; i++) {
        k = order[i]
        if (status[k] == "log-unavailable" || status[k] == "log-empty" || status[k] == "parse-failed")
          alarm[++nb] = suite[k] " [" topo[k] "] `" status[k] "` -- the harvester itself failed on this job, so its lines are lost even though the job produced them"
        else if (concl[k] == "success" && status[k] != "ok")
          alarm[++nb] = suite[k] " [" topo[k] "] `" status[k] "` on a SUCCESSFUL job -- obligatory lines are missing, so the instrument is broken, not the run"
        else if (status[k] == "no-lines")
          alarm[++nb] = suite[k] " [" topo[k] "] no instrument lines, conclusion `" concl[k] "`" (annot[k] != "" ? " (" annot[k] ")" : "") " -- the job ended before or during the chainsaw phase"
      }
      if (nk == 0) alarm[++nb] = "the TSV contained no job rows at all"
      if (nb > 0) {
        print ""
        print "> [!WARNING]"
        print "> Harvest anomalies:"
        for (i = 1; i <= nb; i++) print "> - " alarm[i]
      }
      print ""
      print "Full TSV: the `harvest-*` artifact on this run (90 days)."
      print "Accumulate past slots with `ci/scripts/baseline-harvest.sh collect`."
    }' "${tsv}"
}

# The 90-day answer. Artifacts expire; aggregates do not, and every question this project has
# actually asked fit inside 30 days. Beyond that the intended path is a monthly owner-landed
# snapshot PR into research/ -- CI committing to the repo needs contents: write and inverts the
# repo's review posture, so it stays a human action.
cmd_collect() {
  local days="${1:-30}" since dir run_id f first=true
  since="$(date -u -d "${days} days ago" '+%Y-%m-%d')"
  dir="${WORK}/collect"
  mkdir -p "${dir}"
  while read -r run_id; do
    [[ -n "${run_id}" ]] || continue
    rm -rf "${dir:?}/${run_id}"
    gh run download "${run_id}" --repo "${REPO}" --pattern 'harvest-*' --dir "${dir}/${run_id}" >/dev/null 2>&1 || continue
    while IFS= read -r f; do
      if ${first}; then cat "${f}"; first=false; else tail -n +2 "${f}"; fi
    done < <(find "${dir}/${run_id}" -name 'harvest.tsv' -type f | sort)
  done < <(gh api --paginate "repos/${REPO}/actions/workflows/${WORKFLOW}/runs?per_page=100&created=%3E${since}" \
    --jq '.workflow_runs[] | select(.event != "pull_request") | .id' 2>/dev/null)
  if ${first}; then
    log "no harvest artifacts in the last ${days} days (they expire at 90)"
  fi
  return 0
}

case "${1:-}" in
  harvest)   shift; cmd_harvest "$@" ;;
  summarize) shift; cmd_summarize "$@" ;;
  collect)   shift; cmd_collect "$@" ;;
  *)
    cat >&2 <<'USAGE'
usage: baseline-harvest.sh <command>

  harvest [--run <id>] [--attempt <n>] [--sweep]   instrument lines -> TSV on stdout
  summarize <tsv>                                  that TSV -> markdown on stdout
  collect [days]                                   past slots' TSVs -> one TSV on stdout

Run id defaults to $GITHUB_RUN_ID. TESTING.md publishes the line grammar this parses.
USAGE
    exit 2
    ;;
esac
