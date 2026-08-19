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
#   MODE    <fast|slow|intermediate|none> ctrl_webhook_gap_s=<n|-> ctrl= webhook= certctrl=
#   RESTART <count>   <kind>/<ns>/<name> [<container>]
#   PULL    <pull_s>  <incl_wait_s> <ns>/<pod> <image>
#   PULL    ?         ?             <ns>/<pod> :: <unparsed message>
#   ESOCERT secret <created|absent> ... | ESOCERT pod <name> [<container>] containerStarted=
#   ESOLOG  <pod> <log line, truncated>
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
# MODE / ESOCERT / ESOLOG exist for one question: the prerequisite phase is BIMODAL. The
# external-secrets controller -> webhook readiness gap was either ~20-27s or ~71-97s with
# nothing in between across 143 classified runs, and the mode does not track load (06 §5).
# The fast band has since moved -- see the band edges below -- but the slow one has not.
# A contended resource produces a continuum, not two bands with an empty 40s gulf; that shape
# needs a fixed timer converting a lost race into a discrete penalty. MODE names the mode so
# nobody re-derives the band by hand again, and ESOCERT/ESOLOG carry the four timestamps that
# separate the live candidates -- webhook container start, when the webhook TLS secret was
# actually written, and what each side logged about it. They are emitted on EVERY run, fast
# ones included: an instrument that only speaks during the rare event cannot be trusted when
# the rare event arrives.
#
# Never fails the step it runs in: this is a diagnostic, and on the failing side it runs after
# the suite is already red.
set -u

KOPTS=(--request-timeout=30s)

# Namespace and object names of the external-secrets fixture, in one place: the MODE
# classifier, the secret read and the log dump all key off them. Fixed by the module, not by
# the cluster -- security-core/external-secrets pins `releaseName: external-secrets` and
# `targetNamespace: external-secrets`, and the fixture deploys that component unmodified in
# this respect. If either moves, MODE reports `absent` for every position rather than
# silently reporting `none`, which is the difference this instrument is built to show.
ESO_NS=external-secrets
ESO_WEBHOOK_SECRET=external-secrets-webhook

echo '--- READY: pod and Flux object Ready transitions, ascending (T0 = earliest below) ---'

{
  # shellcheck disable=SC2016  # go-template, not shell -- $p is a template variable
  kubectl get pods -A "${KOPTS[@]}" -o go-template='{{range .items}}{{if .status}}{{$p := printf "pod/%s/%s" .metadata.namespace .metadata.name}}{{range .status.conditions}}{{if eq .type "Ready"}}{{printf "%s %s %s\n" .lastTransitionTime .status $p}}{{end}}{{end}}{{end}}{{end}}' 2>/dev/null

  # Fully qualified so a CRD sharing a short name in another API group cannot be picked up.
  for t in kustomizations.kustomize.toolkit.fluxcd.io helmreleases.helm.toolkit.fluxcd.io; do
    short="${t%%.*}"; short="${short%s}"
    kubectl get "${t}" -A "${KOPTS[@]}" -o go-template="{{range .items}}{{if .status}}{{\$p := printf \"${short}/%s/%s\" .metadata.namespace .metadata.name}}{{range .status.conditions}}{{if eq .type \"Ready\"}}{{printf \"%s %s %s\n\" .lastTransitionTime .status \$p}}{{end}}{{end}}{{end}}{{end}}" 2>/dev/null
  done
} | sort | awk -v eso_ns="${ESO_NS}" '
  # Renders one MODE position: a pod that does not exist, one that exists but never reached
  # Ready=True, or the T0-relative second it did. Those three are deliberately distinct --
  # "no external-secrets in this suite" and "the webhook never came up" are opposite findings
  # and collapsing them to one token is how an instrument stops being able to surprise you.
  function pos(role) {
    if (!(role in seen)) return "absent"
    if (!(role in rt))   return "notready"
    return sprintf("T0+%d", rt[role] - base)
  }
  {
    t = ""
    cmd = "date -d " $1 " +%s 2>/dev/null"
    cmd | getline t
    close(cmd)
    if (t == "") next
    if (base == "") base = t
    printf "READY   T0+%-6d %-21s %-6s %s\n", t - base, $1, $2, $3

    # Longest prefix first: the controller pod is `external-secrets-<rs>-<pod>`, so a plain
    # prefix test would swallow both siblings.
    role = ""
    if      (index($3, "pod/" eso_ns "/external-secrets-webhook-")         == 1) role = "webhook"
    else if (index($3, "pod/" eso_ns "/external-secrets-cert-controller-") == 1) role = "certctrl"
    else if (index($3, "pod/" eso_ns "/external-secrets-")                 == 1) role = "ctrl"
    if (role != "") {
      seen[role] = 1
      # Earliest Ready=True wins, so a later rollout of the same Deployment cannot inflate
      # the gap. Input is already time-sorted, so the first hit is the earliest.
      if ($2 == "True" && !(role in rt)) rt[role] = t
    }
  }
  END {
    gap = "-"; mode = "none"
    if (("ctrl" in rt) && ("webhook" in rt)) {
      gap = rt["webhook"] - rt["ctrl"]
      # Band edges from the published distribution (06 §5, outside-review-2 §3.3): 78 runs on
      # the old instrument and 65 on the new one split 20-27s vs 71-97s with NOTHING between.
      # Both edges still hold after the fixture dropped the webhook probe delay: that delay
      # only ever gated OBSERVING a webhook that was already serving, so it moved the fast band
      # down (well clear of 35) and left the slow band -- gated on the certificate itself, not
      # on the probe grid -- where it was.
      # `intermediate` therefore prints for 36-59s not as a hedge but as the falsifier: the
      # zero-intermediates claim is the sharpest fact in the dataset, and an instrument that
      # cannot contradict its own headline is not measuring anything.
      mode = (gap <= 35) ? "fast" : ((gap >= 60) ? "slow" : "intermediate")
    }
    printf "MODE    %-12s ctrl_webhook_gap_s=%-5s ctrl=%-10s webhook=%-10s certctrl=%s\n", \
      mode, gap, pos("ctrl"), pos("webhook"), pos("certctrl")
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

echo '--- ESOCERT: webhook TLS secret vs webhook pod start (the MODE mechanism) ---'
# The four timestamps that separate the surviving explanations for the slow mode. All five
# slow runs in the instrumented sample carried their entire 50-70s delta at ONE transition,
# eso-controller Ready -> eso-webhook Ready, and were at or ahead of their fast siblings on
# every earlier one. Both readiness gates sit below Flux (`flux reconcile helmrelease` was
# observed as one continuous wait that returned the second the HR flipped), so the quantum is
# inside the chart's own webhook-certificate bootstrap.
#
# The webhook mounts secret/external-secrets-webhook as a plain secret volume at /tmp/certs.
# The chart's readinessProbe carries initialDelaySeconds: 20, which WAS the fast mode's uniform
# floor; the shared external-secrets fixture now overrides it to 1, so a fast gap from a suite
# composing that fixture reads single digits. infra-security deploys the whole security-core
# module instead of the fixture and still pays the chart default -- it is the one suite whose
# fast band stays ~20s, and that difference is expected, not a fault.
#
# Three outcomes this can return, and it must be able to return all three:
#   secret written well before containerStarted, webhook Ready a probe later-> fast, no puzzle
#   secret written EARLY, webhook Ready ~60s after that                    -> ESO-internal
#                                                                             timer, not kubelet
#   secret written AFTER containerStarted, webhook Ready at the next tick  -> the mount-refresh
#                                                                             candidate
# and a webhook container that itself started ~60s late sends it back to pod-lifecycle causes.
#
# Only metadata is read. The Secret's DATA is never printed -- this log is public.
kubectl get secret "${ESO_WEBHOOK_SECRET}" -n "${ESO_NS}" "${KOPTS[@]}" \
  -o go-template='{{printf "ESOCERT secret  %s created=%s" .metadata.name .metadata.creationTimestamp}}{{range .metadata.managedFields}}{{printf " update[%s:%s]=%s" .manager .operation .time}}{{end}}{{"\n"}}' 2>/dev/null \
  || echo "ESOCERT secret  ${ESO_WEBHOOK_SECRET} absent (no secret/${ESO_WEBHOOK_SECRET} in ns/${ESO_NS})"

# Captured once and reused: the pod lines below and the log dump after them both need it, and
# a second `kubectl get` could see a different generation of pods than the one just reported.
# shellcheck disable=SC2016  # go-template, not shell -- $p/$c are template variables
eso_pods=$(kubectl get pods -n "${ESO_NS}" "${KOPTS[@]}" -o go-template='{{range .items}}{{$p := .metadata.name}}{{$c := .metadata.creationTimestamp}}{{if .status}}{{range .status.containerStatuses}}{{if .state.running}}{{printf "ESOCERT pod     %s [%s] podCreated=%s containerStarted=%s restarts=%d\n" $p .name $c .state.running.startedAt .restartCount}}{{else}}{{printf "ESOCERT pod     %s [%s] podCreated=%s containerStarted=- restarts=%d\n" $p .name $c .restartCount}}{{end}}{{end}}{{end}}{{end}}' 2>/dev/null)

if [[ -n "${eso_pods}" ]]; then
  echo "${eso_pods}"
else
  # Not a failure: apps-coder deploys no external-secrets fixture and can never exhibit the
  # mode. It is also what a renamed release would look like, which is why MODE prints the
  # positions separately rather than only the verdict.
  echo "ESOCERT pod     absent (no pods in ns/${ESO_NS})"
fi

# Earliest lines, not the last: the certificate bootstrap happens at startup, so `head` is the
# correct end of the log. Bounded three ways because this runs on every suite -- byte cap on
# the fetch, 80 lines printed, and each line cut to 200 chars. That last one is not cosmetic:
# cert-controller logs `injecting ca certificate and service names` with the whole base64 CA
# on the line (~1.5 KB, repeated per webhook config per check interval), and untruncated it
# would bury the timestamps this section exists for. 200 chars keeps ts/logger/msg, which is
# all of it that carries information.
while read -r p; do
  [[ -n "${p}" ]] || continue
  kubectl logs "${p}" -n "${ESO_NS}" --all-containers=true --timestamps --limit-bytes=200000 \
    "${KOPTS[@]}" 2>&1 | awk -v p="${p}" 'NR<=80 { printf "ESOLOG  %s %.200s\n", p, $0 }'
done < <(printf '%s\n' "${eso_pods}" | awk '$3 ~ /-(webhook|cert-controller)-/ { print $3 }' | sort -u)

exit 0
