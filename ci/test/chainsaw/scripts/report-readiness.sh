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
#   RESTART <count>   <kind>/<ns>/<name> [<container>]
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
# shellcheck disable=SC2016  # go-template, not shell
kubectl get pods -A "${KOPTS[@]}" -o go-template='{{range .items}}{{if .status}}{{$p := printf "pod/%s/%s" .metadata.namespace .metadata.name}}{{range .status.containerStatuses}}{{if gt .restartCount 0}}{{printf "RESTART %-6d %s [%s]\n" .restartCount $p .name}}{{end}}{{end}}{{end}}{{end}}' 2>/dev/null | sort -k2 -rn

echo '--- PULL: image pull durations from reason=Pulled events (slowest first) ---'
# Replaces image size, which was used as a pull-time proxy and is measurably wrong the moment a
# component is gated on a dependency rather than on bytes. kubelet already puts the real number
# in the event message; this only reads it back out. Both numbers are reported because they
# differ: the first is the pull itself, the second includes time queued behind containerd's
# concurrent-download limit -- and that gap is the whole multi-node pull-parallelism argument.
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
