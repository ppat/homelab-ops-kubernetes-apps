#!/bin/bash
# The suite's readiness record, in one place and ONE format.
#
# Called from two places that previously disagreed:
#   - steps/report-readiness.yaml, the last step of every suite  -> runs when the suite PASSES
#   - the shared `catch` in .chainsaw.yaml                        -> runs when the suite FAILS
#
# Before this script the two emitted different things (passing runs: T0-relative offsets plus
# restart counts; failing runs: absolute timestamps and no restarts), so a census across both
# outcomes needed two parsers -- and, worse, the failing sample silently lacked the restart
# counts that distinguish "late" from "crash-looping", which is the exact distinction a budget
# decision turns on. One script called from both sides is the only way those stay in step.
#
# Line grammar, all prefixes greppable and whitespace-separated:
#
#   READY   T0+<secs> <rfc3339> <True|False> <kind>/<ns>/<name>
#   RESTART <count>   <kind>/<ns>/<name> [<container>] reason=<name|-|none> exit_code=<n|none>
#   PULL    <pull_s>  <incl_wait_s> <ns>/<pod> <image>
#   PULL    ?         ?             <ns>/<pod> :: <unparsed message>
#
# T0 is the EARLIEST timestamp in the READY stream, not the suite start -- nothing in a
# chainsaw script knows when the suite started. In practice T0 is a flux-system pod, which is
# ~40s after the module could first have been applied. Offsets are therefore comparable
# between runs of the same suite and not against wall-clock job duration.
#
# Flux objects are interleaved into the same ascending stream as pods on purpose: the question
# this repo keeps asking is whether a component was slow or was merely waiting on the release
# above it, and that is answerable by eye only when both are on one timeline. `flux get all -A`
# in the catch shows current state, never when a thing became Ready.
#
# READY reads `lastTransitionTime` of the CURRENT Ready condition, so a pod that flapped
# reports its LATEST transition to Ready, not its first. That is what step ordering wants, and
# it mildly overstates readiness for anything that crashes and recovers (infra-storage's
# longhorn-manager, #3643) -- cross-check those against the RESTART block.
#
# Never fails the step it runs in: this is a diagnostic, and on the failing side it runs after
# the suite is already red.
set -u

KOPTS=(--request-timeout=30s)

echo '--- READY: pod and Flux object Ready transitions, ascending (T0 = earliest below) ---'

{
  # shellcheck disable=SC2016  # go-template, not shell -- $p is a template variable
  kubectl get pods -A "${KOPTS[@]}" -o go-template='{{range .items}}{{if .status}}{{$p := printf "pod/%s/%s" .metadata.namespace .metadata.name}}{{range .status.conditions}}{{if eq .type "Ready"}}{{printf "%s %s %s\n" .lastTransitionTime .status $p}}{{end}}{{end}}{{end}}{{end}}' 2>/dev/null

  # Fully qualified so a CRD sharing a short name in another API group cannot be picked up.
  for t in kustomizations.kustomize.toolkit.fluxcd.io helmreleases.helm.toolkit.fluxcd.io; do
    short="${t%%.*}"; short="${short%s}"
    kubectl get "${t}" -A "${KOPTS[@]}" -o go-template="{{range .items}}{{if .status}}{{\$p := printf \"${short}/%s/%s\" .metadata.namespace .metadata.name}}{{range .status.conditions}}{{if eq .type \"Ready\"}}{{printf \"%s %s %s\n\" .lastTransitionTime .status \$p}}{{end}}{{end}}{{end}}{{end}}" 2>/dev/null
  done
} | sort | awk '
  {
    t = ""
    cmd = "date -d " $1 " +%s 2>/dev/null"
    cmd | getline t
    close(cmd)
    if (t == "") next
    if (base == "") base = t
    printf "READY   T0+%-6d %-21s %-6s %s\n", t - base, $1, $2, $3
  }
'

echo '--- RESTART: container restarts (empty = none) ---'
# A container that crashes and recovers inside its assertion's budget is otherwise invisible:
# the assertion reports only the end state. That is exactly the blind spot created by sizing a
# budget to ride out a known crash-restart cycle (infra-storage's longhorn-manager, #3643).
# Tolerating something is defensible; tolerating it silently is not.
#
# `reason=` and `exit_code=` are kubelet's own classification of the previous instance's death,
# read from the SAME response the count is read from -- `lastState.terminated` is already in it,
# so the wider projection costs no extra API call. They are what makes the count actionable:
# `Error` is the modal reason and says only "exited non-zero", so the exit code is what
# separates a config crash from a signal, and the pair is what separates the two cases neither
# field settles alone -- `OOMKilled` arrives with exit 0 as readily as 137, and a 137 under
# `Error` is a kill that was not an OOM (probe failure, grace-period expiry). Different repair
# in each case. No CI run has ever reported an OOM kill, and until now that was a property of
# the instrument rather than a finding, because nothing was reading the field. On the live
# cluster kube-state-metrics sees OOMKilled routinely -- longhorn-manager included, which is
# the very container #3643 taught this block to ride out. Whether CI's restarts are the same
# thing is not assumable in either direction; this is what makes it answerable.
#
# Fields on the existing line, NOT a prefix of their own, and that is a consumer decision.
# Both readers of this grammar match a line-leading prefix and then keep the line whole, so a
# field arrives at both with no edit in either,
# whereas a new prefix must be added to ci/scripts/baseline-harvest.sh here AND to the
# ci-diagnostics ingester in the clusters repo or the line is silently retained nowhere. What
# a field costs instead is announcement: nothing flags its arrival, and it is only as queryable
# as the reader that names it. Both fields now arrive as structured metadata: the ingester's
# RESTART parser lifts its key=value tail the way the CONTENTION parser does, so
# `{job="ci-diagnostics", instrument="restart"} | reason != ""` returns them and a further field
# added here needs no clusters-repo change. Confirmed against a live entry carrying
# reason=Error exit_code=137, not inferred from the parser. Every pre-existing token keeps its
# position and width.
#
# Three outcomes, deliberately distinct, because "kubelet recorded no previous termination" and
# "it recorded one but named no reason" are different findings and one glyph for both is how an
# instrument stops being able to surprise you:
#   reason=<name> exit_code=<n>     a previous termination, classified
#   reason=- exit_code=<n>          a termination record carrying no reason (the dash convention)
#   reason=none exit_code=none      no previous termination recorded -- also what a `lastState`
#                                   holding only `waiting` looks like
#
# The `with` nesting is the guard, and the shorter `{{if .lastState.terminated}}` is NOT an
# equivalent of it: that form walks `.terminated` on a `lastState` which may not be there, and
# text/template makes exactly that a hard error under `missingkey=zero` -- whereupon the template
# aborts the whole call part-way through, taking every RESTART line after the first offender with
# it, which is strictly worse than the blind spot this block exists to close. kubectl's printer
# does not set that option today, so today the same walk degrades to a `%!s(<nil>)` token
# instead: not fatal, but a token both readers would ingest as though it were a reason. Measured
# both ways rather than assumed.
# shellcheck disable=SC2016  # go-template, not shell
restarts=$(kubectl get pods -A "${KOPTS[@]}" -o go-template='{{range .items}}{{if .status}}{{$p := printf "pod/%s/%s" .metadata.namespace .metadata.name}}{{range .status.containerStatuses}}{{if gt .restartCount 0}}{{$why := "reason=none exit_code=none"}}{{with .lastState}}{{with .terminated}}{{$why = printf "reason=%s exit_code=%v" (or .reason "-") .exitCode}}{{end}}{{end}}{{printf "RESTART %-6d %s [%s] %s\n" .restartCount $p .name $why}}{{end}}{{end}}{{end}}{{end}}' 2>/dev/null | sort -k2 -rn)
echo "${restarts}"

# WHY a container restarted, not just that it did. The count above says a crash happened; the
# log of the instance that crashed says what happened, and it is gone the moment the next
# instance replaces it. It found a real one on its first run: infra-networking carries a
# three-deep startup crash-wait chain -- unbound/cloudflare-doh not up yet, so pihole exits
# ("Cannot proceed without an upstream DNS server"), so external-dns-pihole goes `level=fatal`
# on pihole -- burning 2-4 restart backoffs on EVERY run of that suite, green ones included.
# That is 04 C4: tolerating a defect is fine, tolerating it silently is not.
#
# Gated on restarts existing, which is NOT the same as "only on failing runs" -- ~16% of green
# runs open this gate and six suites open it routinely (apps-downloaders sits at 8 restarted
# containers on every pass). The bounds below are sized for that, not for the rare failure.
#
# Bounded four ways: 40 lines
# per container, each line cut to 200 chars (external-dns logs a 4309-char config dump on the
# line this would otherwise print untruncated), at most MAX_RESTART_LOGS containers, and a
# tighter request timeout than the rest of the script.
MAX_RESTART_LOGS=12
if [[ -n "${restarts}" ]]; then
  echo '--- RESTART-LOG: last lines from the PREVIOUS instance of each restarted container ---'
  shown=0
  skipped=0
  # The trailing `_` is what keeps the classification fields off `container`: without it `read`
  # packs every remaining field into the last variable, `[name] reason=... exit_code=...` would
  # survive the bracket strip below, and `kubectl logs -c` would be handed a container name that
  # cannot exist -- silently costing this block every log it is here to capture.
  while read -r _ _ ref container _; do
    [[ -n "${ref}" ]] || continue
    if [[ ${shown} -ge ${MAX_RESTART_LOGS} ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    shown=$((shown + 1))
    ns="${ref#pod/}"; ns="${ns%%/*}"
    pod="${ref##*/}"
    container="${container#[}"; container="${container%]}"
    echo "=== ${ns}/${pod} [${container}] ==="
    # --previous is the point: the current instance may be healthy or still starting, and it is
    # the one that died that carries the reason. Failure here is expected and non-fatal.
    #
    # `2>&1` rather than `||`, because the exit code does not separate the cases: a pod or
    # container that no longer exists exits 1 (measured), while a previous instance whose log
    # has already been reaped prints "unable to retrieve container logs" and exits 0. Capturing
    # both streams reports all of them identically, which is what a reader wants -- the message
    # is the useful part in every case. Captured and echoed rather than streamed because kubectl
    # omits the trailing newline on at least one of those paths and the next section runs into it.
    #
    # --timestamps is load-bearing and not cosmetic. It is what stops a container's own log text
    # being read as this script's grammar: baseline-harvest.sh and the ci-diagnostics ingester
    # both match a line-leading prefix allowlist after stripping the Actions timestamp, so a log
    # line beginning `READY ` or `PULL ` would be retained as an instrument reading. A leading
    # RFC3339 puts a digit in that position.
    prev=$(kubectl logs -n "${ns}" "${pod}" -c "${container}" --previous --tail=40 --timestamps \
      --request-timeout=10s 2>&1 | cut -c1-200)
    [[ -n "${prev}" ]] && echo "${prev}"
  done <<< "${restarts}"
  # Said out loud rather than dropped: a silent cap turns "we bounded this" into "there was
  # nothing else", which is the failure this whole script exists to stop. The list is sorted by
  # restart count descending, so the ones shown are the worst offenders.
  if [[ ${skipped} -gt 0 ]]; then
    echo "=== ${skipped} further restarted container(s) not shown (bounded at ${MAX_RESTART_LOGS}) ==="
  fi
fi

echo '--- PULL: image pull durations from reason=Pulled events (slowest first) ---'
# Replaces image size, which was used as a pull-time proxy and is measurably wrong the moment a
# component is gated on a dependency rather than on bytes. kubelet already puts the real number
# in the event message; this only reads it back out. Both numbers are reported because they
# differ: the first is the pull itself, the second includes time queued behind KUBELET's serial
# pull queue -- and that gap is the whole multi-node pull-parallelism argument.
#
# The serializing layer is kubelet, not containerd, and the distinction is load-bearing because
# the parallel-pull experiment will be judged by watching exactly this gap shrink. Read from a
# live cluster's kubelet `/configz` on the CI node image: `serializeImagePulls: true` (the
# upstream default). At that setting a single-node suite pulls one image at a time whatever
# containerd's own `max_concurrent_downloads` says -- so tuning containerd would move nothing,
# and a gap that does not shrink is evidence about kubelet's queue, not containerd's.
#
# Events expire (1h default apiserver TTL); every suite finishes well inside that.
kubectl get events -A "${KOPTS[@]}" --field-selector reason=Pulled \
  -o go-template='{{range .items}}{{printf "%s/%s\t%s\n" .involvedObject.namespace .involvedObject.name .message}}{{end}}' 2>/dev/null \
  | awk -F'\t' '
    # Go duration strings: 823.4ms / 12.345s / 1m2.345s / 1h2m3s.
    function to_s(d,   s, v) {
      s = 0
      if (match(d, /[0-9]+h/))       { v = substr(d, RSTART, RLENGTH - 1); s += v * 3600 }
      if (match(d, /[0-9]+m[^s]/))   { v = substr(d, RSTART, RLENGTH - 2); s += v * 60 }
      else if (match(d, /[0-9]+m$/)) { v = substr(d, RSTART, RLENGTH - 1); s += v * 60 }
      if (match(d, /[0-9.]+ms/))     { v = substr(d, RSTART, RLENGTH - 2); return s + v / 1000 }
      if (match(d, /[0-9.]+s/))      { v = substr(d, RSTART, RLENGTH - 1); return s + v }
      return s
    }
    {
      pod = $1; msg = $2
      if (msg ~ /already present on machine/) { cached++; next }
      img = "?"
      if (match(msg, /image "[^"]+"/)) { img = substr(msg, RSTART + 7, RLENGTH - 8) }
      d1 = ""; d2 = ""
      if (match(msg, / in [^ ]+ \([^)]+ including waiting\)/)) {
        split(substr(msg, RSTART, RLENGTH), a, " ")
        d1 = a[2]; d2 = a[3]; sub(/^\(/, "", d2)
      }
      # An unparsed message sorts to the top rather than vanishing: a silently dropped line
      # would make this instrument look like it worked when the message format had changed.
      if (d1 == "" || img == "?") {
        printf "999999.999\tPULL    %-8s %-8s %s :: %s\n", "?", "?", pod, msg
        next
      }
      printf "%010.3f\tPULL    %-8.3f %-8.3f %s %s\n", to_s(d2), to_s(d1), to_s(d2), pod, img
    }
    END { if (cached > 0) printf "%010.3f\tPULL-CACHED %d image(s) already present on machine\n", 0, cached }
  ' | sort -rn | cut -f2-

exit 0
