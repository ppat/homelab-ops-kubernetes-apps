#!/bin/bash
# Per-run contention proxy. Emits one grep-able line:
#
#   CONTENTION <phase> nproc=<n> loadavg=<1m>,<5m>,<15m> calib_ms=<n> net_mbps=<n>
#              fsync_us=<n> uptime_s=<n> elapsed_s=<n>
#
# Why this exists: a chainsaw run cannot currently say whether it was contended, so any
# comparison between two runs has to be made by dispatching both arms at the same instant
# and pairing them -- a strictly serial experiment. One 12-pair measurement cost ~90 minutes
# of wall clock for that reason alone, and a stray fleet dispatch confounded two of its pairs
# anyway. With this line in the log, any historical run can be conditioned on contention
# after the fact and the serial dispatch stops being necessary.
#
# `script` operations run on the GitHub runner itself, not inside kind, so every reading here
# is the runner's own -- which is the quantity wanted. A kind node shares the host kernel and
# the host disk, so these are also what the cluster experiences.
#
# FOUR axes, not one, and the reason is a measured result: **CPU is not the contended
# resource here.** Halving cluster CPU on the rig left every timing unchanged, while shaping
# bandwidth to 150mbit reproduced the failures 6/6. A CPU-only proxy would have conditioned
# every future analysis on the axis that was already ruled out.
#
#   loadavg   free, and the only reading that covers the whole runner rather than this process
#   calib_ms  fixed pure-CPU work. The cheap control: it is the axis known NOT to matter, so it
#             is what tells you a slow run was slow for some other reason. Comparable only
#             across runs on the same runner image -- a relative index, not a benchmark.
#   net_mbps  the axis the rig showed does matter. Image pulls are the runs' dominant network
#             cost and they are what a shaped link starves.
#   fsync_us  never tested by anything, and the leading untested candidate for the unexplained
#             BIMODALITY of the prerequisite phase (fast 20-26s vs slow 75-97s, zero
#             intermediates across 78 runs). etcd commits are fsync-bound and runner disks have
#             noisy neighbours, so a disk that stalls quantises cluster progress into exactly
#             that kind of clean two-mode split. If a week of runs shows fsync_us bimodal on
#             the same boundary, that question closes.
#
# STRICTLY AT THE BOUNDARIES. This runs as the first operation of the first step and again
# after the last, never in between. A bandwidth probe fired mid-run would *be* the contention
# it claims to measure.
#
# Never fails the step it runs in: this is a diagnostic, and a suite going red because a
# probe could not read /proc would be worse than no probe.
#
# It also carries the suite's own clock. The `start` phase stamps T0 into a file and every
# later reader reports elapsed_s against it, which gives two things nothing else in the repo
# provides: a machine-readable chainsaw-phase duration on EVERY run without pairing TRY
# BEGIN/TRY END out of a raw log, and a way for report-uncensored.sh to know how much of the
# job's wall clock it has already spent before deciding how long to keep watching.
set -u

phase="${1:-unknown}"
T0_FILE="${TMPDIR:-/tmp}/chainsaw-suite-t0"

now=$(date +%s 2>/dev/null || echo 0)
if [[ "${phase}" == "start" ]]; then
  echo "${now}" > "${T0_FILE}" 2>/dev/null || true
fi
elapsed="?"
if [[ -r "${T0_FILE}" && "${now}" != "0" ]]; then
  t0=$(cat "${T0_FILE}" 2>/dev/null || echo "")
  [[ "${t0}" =~ ^[0-9]+$ ]] && elapsed=$(( now - t0 ))
fi

nproc_n=$(nproc 2>/dev/null || echo "?")
uptime_s=$(cut -d' ' -f1 /proc/uptime 2>/dev/null || echo "?")
if [[ -r /proc/loadavg ]]; then
  read -r l1 l5 l15 _ < /proc/loadavg
  load="${l1},${l5},${l15}"
else
  load="?,?,?"
fi

# 2,000,000 iterations of integer work: measured 109-148 ms across four readings on
# ubuntu-24.04 4-vCPU runners, which is long enough for contention to show and short enough
# that the probe is not itself a cost -- it runs twice per suite against a 10-25 minute job.
# Do not "tidy" the iteration count: changing it silently rebases every historical calib_ms and
# the series stops being comparable, which is the only thing it is for.
calib_start=$(date +%s%N 2>/dev/null || echo 0)
awk 'BEGIN { s = 0; for (i = 0; i < 2000000; i++) { s += i % 7 } exit 0 }' </dev/null
calib_end=$(date +%s%N 2>/dev/null || echo 0)
if [[ "${calib_start}" != "0" && "${calib_end}" != "0" ]]; then
  calib_ms=$(( (calib_end - calib_start) / 1000000 ))
else
  calib_ms="?"
fi

# 100 x 4KiB writes each followed by fdatasync -- the classic etcd disk-latency shape, and the
# reason for that shape rather than a throughput test: what stalls a cluster is commit latency,
# not sequential bandwidth. `timeout` caps it so a genuinely stuck disk (the finding this is
# hunting) delays the boundary by 15s rather than by however long the disk feels like.
fsync_us="?"
fsync_file="${TMPDIR:-/tmp}/chainsaw-fsync-probe.$$"
fsync_start=$(date +%s%N 2>/dev/null || echo 0)
if timeout 15 dd if=/dev/zero of="${fsync_file}" bs=4096 count=100 oflag=dsync >/dev/null 2>&1; then
  fsync_end=$(date +%s%N 2>/dev/null || echo 0)
  [[ "${fsync_start}" != "0" && "${fsync_end}" != "0" ]] && fsync_us=$(( (fsync_end - fsync_start) / 1000 / 100 ))
fi
rm -f "${fsync_file}" 2>/dev/null || true

# 10 MB, capped at 12s, so a total outage of the endpoint costs 24s per run rather than
# stalling it. Reported as UNAVAILABLE rather than omitted: a missing field and a failed probe
# have to be distinguishable, or the series quietly develops holes that look like fast runs.
#
# This measures runner egress to an anycast edge, NOT throughput from a container registry --
# it is an index for comparing runs, not a statement about pull bandwidth. The PULL lines in
# report-readiness.sh are the registry-side measurement.
net_mbps="?"
NET_BYTES=10000000
NET_URL="${CHAINSAW_NET_PROBE_URL:-https://speed.cloudflare.com/__down?bytes=${NET_BYTES}}"
if command -v curl >/dev/null 2>&1; then
  net_raw=$(curl -sS -o /dev/null --max-time 12 -w '%{size_download} %{time_total}' "${NET_URL}" 2>/dev/null || echo "")
  if [[ -n "${net_raw}" ]]; then
    net_mbps=$(echo "${net_raw}" | awk '{ if ($2 > 0 && $1 > 0) printf "%.1f", ($1 * 8) / $2 / 1000000; else print "UNAVAILABLE" }')
  else
    net_mbps="UNAVAILABLE"
  fi
fi

line=$(printf 'CONTENTION %-5s nproc=%s loadavg=%s calib_ms=%s net_mbps=%s fsync_us=%s uptime_s=%s elapsed_s=%s' \
  "${phase}" "${nproc_n}" "${load}" "${calib_ms}" "${net_mbps}" "${fsync_us}" "${uptime_s}" "${elapsed}")
echo "${line}"

# Also to the job summary when running under Actions, so a run's conditions are readable from
# the run page without downloading a 20 MB log. Verified that chainsaw's `script` children
# inherit the runner's environment, so this needs no change in ppat/github-workflows.
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "\`${line}\`" >> "${GITHUB_STEP_SUMMARY}" 2>/dev/null || true
fi

exit 0
