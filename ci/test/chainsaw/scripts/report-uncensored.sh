#!/bin/bash
# Turns a censored timeout failure into a real measurement.
#
# Every timeout failure in this repo is censored at its own budget: an assert that dies at
# 60.0s of 60s says nothing about what it needed. That censoring is why the sizing rule in
# TESTING.md carries a x3 multiplier drawn from cost asymmetry rather than from data -- the
# tail is, by construction, the part that never got recorded. This script keeps watching the
# objects that were not Ready when the suite went red and reports how much longer each
# actually took, so the next budget can be sized from the number instead of the multiplier.
#
# TWO MODES, and the split is not cosmetic:
#
#   --snapshot   record what was not Ready, and when. Sub-second. Runs FIRST in the catch.
#   <bound>      watch that set and report. Runs LAST in the catch.
#
# They are separate because the first CI run of this instrument measured watched=1 where the
# truth was two objects: the dumps ahead of it in the catch took ~30s, and the reloader pod
# went Ready inside that window, so it was never counted. Snapshotting at failure time and
# watching afterwards keeps the accurate census and still leaves the only expensive entry at
# the end, where a job-timeout kill costs least.
#
# The reported number is derived from the object's own Ready `lastTransitionTime`, not from
# when this script noticed -- so it is exact, and unaffected by how long the dumps in front
# took or by the 5s poll interval. A `~` prefix marks the fallback for an object that offers
# no transition time.
#
# Output:
#   UNCENSORED +<secs> Ready    <kind>/<ns>/<name>   became Ready this many seconds late
#   UNCENSORED never   NotReady <kind>/<ns>/<name>   still not Ready at the bound
#   UNCENSORED gone    Deleted  <kind>/<ns>/<name>   disappeared while being watched
#   UNCENSORED-SUMMARY watched=<n> ready=<n> notready=<n> gone=<n> max_extra_s=<n> bound_s=<n>
#
# COST. Only ever runs on a run that has already failed, and only for as long as something is
# still not Ready -- it exits the instant the watch set empties, so a failure whose cause is
# not readiness (a query script, a roundtrip check) pays nothing at all.
#
# Completed Job pods are excluded: they carry Ready=False with reason PodCompleted forever, and
# would otherwise be reported as "never" on every single failure.
set -u

INTERVAL=5
HEARTBEAT_EVERY=6  # 30s
KOPTS=(--request-timeout=30s)
SNAP_FILE="${TMPDIR:-/tmp}/chainsaw-uncensored-snapshot"
T0_FILE="${TMPDIR:-/tmp}/chainsaw-suite-t0"

WATCH_TYPES=(kustomizations.kustomize.toolkit.fluxcd.io helmreleases.helm.toolkit.fluxcd.io)
# #3678 is the largest single failure source in the repo and its signature is a CNPG Cluster
# that never leaves an empty Status, so "never" is exactly the reading wanted here.
if kubectl get crd clusters.postgresql.cnpg.io "${KOPTS[@]}" >/dev/null 2>&1; then
  WATCH_TYPES+=(clusters.postgresql.cnpg.io)
fi

state() {
  # <kind>/<ns>/<name> <Ready-status> <phase-or-dash> <ready-lastTransitionTime-or-dash>
  #
  # An object with no status and an object with Ready=False are both reported here as False,
  # and that is the whole point rather than a shortcut: #3678's signature is a CNPG `Cluster`
  # whose Status is EMPTY, so a template that only emits a line when a Ready condition already
  # exists drops precisely the object worth watching. (It did. Caught by creating a
  # status-less Cluster and watching this report watched=0.)
  # shellcheck disable=SC2016  # go-template, not shell
  kubectl get pods -A "${KOPTS[@]}" -o go-template='{{range .items}}{{$p := printf "pod/%s/%s" .metadata.namespace .metadata.name}}{{$r := "False"}}{{$ph := "-"}}{{$t := "-"}}{{if .status}}{{if .status.phase}}{{$ph = .status.phase}}{{end}}{{range .status.conditions}}{{if eq .type "Ready"}}{{$r = .status}}{{$t = .lastTransitionTime}}{{end}}{{end}}{{end}}{{printf "%s %s %s %s\n" $p $r $ph $t}}{{end}}' 2>/dev/null

  for t in "${WATCH_TYPES[@]}"; do
    short="${t%%.*}"; short="${short%s}"
    kubectl get "${t}" -A "${KOPTS[@]}" -o go-template="{{range .items}}{{\$p := printf \"${short}/%s/%s\" .metadata.namespace .metadata.name}}{{\$r := \"False\"}}{{\$t := \"-\"}}{{if .status}}{{range .status.conditions}}{{if eq .type \"Ready\"}}{{\$r = .status}}{{\$t = .lastTransitionTime}}{{end}}{{end}}{{end}}{{printf \"%s %s - %s\n\" \$p \$r \$t}}{{end}}" 2>/dev/null
  done
}

not_ready_keys() {
  while read -r key status phase _; do
    [[ -z "${key}" ]] && continue
    [[ "${status}" == "True" ]] && continue
    [[ "${phase}" == "Succeeded" ]] && continue
    echo "${key}"
  done < <(state)
}

if [[ "${1:-}" == "--snapshot" ]]; then
  # Tighter than the watch's 30s, because this entry sits in FRONT of the `flux get`/`kubectl
  # get` dumps: on a cluster whose API server is the thing that broke, the census is worth
  # much less than getting those dumps out, so it gives up quickly rather than holding them up.
  KOPTS=(--request-timeout=10s)
  now=$(date +%s)
  { echo "${now}"; not_ready_keys; } > "${SNAP_FILE}" 2>/dev/null || true
  n=$(( $(wc -l < "${SNAP_FILE}" 2>/dev/null || echo 1) - 1 ))
  echo "UNCENSORED-SNAPSHOT at=${now} not_ready=${n}"
  exit 0
fi

BOUND="${1:-240}"

# Self-limiting, because the safe bound is a property of the SUITE's job timeout and that
# number moves: five suites went 15m -> 25m on 2026-08-15 alone, and a constant sized against
# yesterday's config is exactly the kind of thing nobody revisits. Budget arithmetic, all
# measured (see the failing-job census in this PR's body):
#   - the tightest 15m suite is apps-bitwarden, whose worst failing job ran 504s of 900s
#   - job - chainsaw is a fixed ~80s of checkout/mise/kind create/flux install
#   - 60s reserve for teardown and log upload
# so what is left is 900 - 90 - <chainsaw elapsed> - 60. Clamping to that turns "would this
# push a job over its timeout?" from a claim about today's config into arithmetic the run does
# for itself. Assumes the 15m default even on the six 25m suites: being conservative there
# costs measurement range only on the suites that have the most headroom to spare.
#
# If T0 is unreadable the constant stands alone -- it is already safe against every one of the
# 305 failing jobs sampled over 30 days (first breach at 397s), so the clamp is a safety net
# rather than the thing correctness rests on.
if [[ -r "${T0_FILE}" ]]; then
  t0=$(cat "${T0_FILE}" 2>/dev/null || echo "")
  if [[ "${t0}" =~ ^[0-9]+$ ]]; then
    remaining=$(( 900 - 90 - 60 - ($(date +%s) - t0) ))
    if [[ "${remaining}" -lt "${BOUND}" ]]; then
      echo "UNCENSORED-CLAMP requested=${BOUND} remaining_wall_s=${remaining} (job timeout headroom)"
      BOUND="${remaining}"
    fi
  fi
fi
# Below 30s the watch cannot distinguish "needed a little longer" from "never", so report that
# there was no room rather than emitting a measurement too short to mean anything.
if [[ "${BOUND}" -lt 30 ]]; then
  echo "UNCENSORED-SUMMARY watched=0 ready=0 notready=0 gone=0 max_extra_s=0 bound_s=${BOUND} skipped=no-wall-clock-left"
  exit 0
fi

declare -A pending=()
snap_at=""
if [[ -r "${SNAP_FILE}" ]]; then
  while read -r line; do
    if [[ -z "${snap_at}" ]]; then snap_at="${line}"; continue; fi
    [[ -n "${line}" ]] && pending["${line}"]=1
  done < "${SNAP_FILE}"
fi
[[ "${snap_at}" =~ ^[0-9]+$ ]] || snap_at=""
if [[ -z "${snap_at}" ]]; then
  # No snapshot (older layout, or the entry failed). Fall back to a live census, which is what
  # the first version did -- less accurate, never absent.
  snap_at=$(date +%s)
  while read -r key; do [[ -n "${key}" ]] && pending["${key}"]=1; done < <(not_ready_keys)
fi

watched=${#pending[@]}
echo "--- UNCENSORED: watching ${watched} object(s) not Ready at failure, for up to ${BOUND}s ---"
if [[ "${watched}" -eq 0 ]]; then
  echo "UNCENSORED-SUMMARY watched=0 ready=0 notready=0 gone=0 max_extra_s=0 bound_s=${BOUND}"
  exit 0
fi

start=$(date +%s)
n_ready=0
max_extra=0
polls=0
first=1
while [[ ${#pending[@]} -gt 0 ]]; do
  now=$(date +%s)
  elapsed=$(( now - start ))
  if [[ "${first}" -eq 1 ]]; then
    # Poll immediately: anything that resolved while the dumps ahead of this ran is measured
    # from its own transition time, so it is not lost and not misdated.
    first=0
  else
    [[ "${elapsed}" -ge "${BOUND}" ]] && break
    sleep "${INTERVAL}"
    polls=$(( polls + 1 ))
  fi

  declare -A seen=()
  while read -r key status _ ts; do
    [[ -z "${key}" ]] && continue
    seen["${key}"]=1
    if [[ -n "${pending[${key}]:-}" && "${status}" == "True" ]]; then
      mark="+"
      extra=""
      if [[ "${ts}" != "-" ]]; then
        tsec=$(date -d "${ts}" +%s 2>/dev/null || echo "")
        [[ -n "${tsec}" ]] && extra=$(( tsec - snap_at ))
      fi
      if [[ -z "${extra}" ]]; then
        extra=$(( $(date +%s) - snap_at ))
        mark="~"
      fi
      [[ "${extra}" -lt 0 ]] && extra=0
      printf 'UNCENSORED %s%-6s %-8s %s\n' "${mark}" "${extra}" "Ready" "${key}"
      unset "pending[${key}]"
      n_ready=$(( n_ready + 1 ))
      [[ "${extra}" -gt "${max_extra}" ]] && max_extra="${extra}"
    fi
  done < <(state)

  # An object that vanished is not an object that became Ready, and conflating the two would
  # invent a measurement out of a deletion.
  for key in "${!pending[@]}"; do
    if [[ -z "${seen[${key}]:-}" ]]; then
      printf 'UNCENSORED %-7s %-8s %s\n' "gone" "Deleted" "${key}"
      unset "pending[${key}]"
    fi
  done

  # Progressive, every 30s. Its value is narrower than it looks and the boundary is worth
  # knowing: chainsaw BUFFERS a script's stdout and logs it in one block when the script ends
  # (verified on v0.2.15 -- a line printed at t=0 appears in the log at t=8 alongside the one
  # printed then). So this survives the script's OWN timeout firing, which does flush what was
  # captured, and does NOT survive the job's timeout-minutes killing the process tree, which
  # emits nothing at all. Only the clamp above protects against the second.
  if [[ ${#pending[@]} -gt 0 && "${polls}" -gt 0 && $(( polls % HEARTBEAT_EVERY )) -eq 0 ]]; then
    printf 'UNCENSORED-PENDING t+%-6s %s\n' "$(( $(date +%s) - start ))" "${!pending[*]}"
  fi
  unset seen
done

n_gone=$(( watched - n_ready - ${#pending[@]} ))
for key in "${!pending[@]}"; do
  printf 'UNCENSORED %-7s %-8s %s\n' "never" "NotReady" "${key}"
done
echo "UNCENSORED-SUMMARY watched=${watched} ready=${n_ready} notready=${#pending[@]} gone=${n_gone} max_extra_s=${max_extra} bound_s=${BOUND}"

exit 0
