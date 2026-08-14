#!/bin/bash
set -euo pipefail

# Asserts the observable output contract of Kubernetes Event collection: the exact set of
# labels that arrive in Loki for an event, which fields deliberately did NOT become
# labels, and that both values of the derived `severity` label are actually produced.
#
# This is the events counterpart of check-log-label-contract.sh, and it is a separate
# file rather than more cases in that one because it asserts a different contract about a
# different pipeline: that script is about pod logs read from disk by the node DaemonSet,
# this one is about `loki.source.kubernetes_events` in the singleton Deployment.
#
# WHY AN EXACT SET, AND WHY /series
# ---------------------------------
# Same reasoning as the pod-log contract: a superset check ("the labels I care about are
# there") passes while the collector leaks extra ones, and label cardinality is the whole
# cost model of this pipeline. `/series` reports INDEXED stream labels only, which is the
# view the cost is actually paid in; query_range would additionally show whatever Loki
# attaches as structured metadata (`detected_level`), whose value depends on Loki's own
# log-level heuristics rather than on anything this module controls.
#
# WHAT IS DELIBERATELY NOT A LABEL
# --------------------------------
# `reason`. It is the single most tempting field to promote - it is what an operator
# filters on - and promoting it would take the stream count to roughly namespaces x
# reasons. `reason` is a free-form string in the Event API that any controller may extend
# without bound, so that product has no ceiling, and it would be paid in thousands of
# near-empty streams by a pipeline that ships a trickle. It stays in the line body, and
# this script asserts BOTH halves of that: absent from the label set, present in the text.
#
# WHAT WOULD MAKE THIS VACUOUS
# ----------------------------
# "Every label on the event streams is correct" is trivially true of a pipeline that
# collected no events. Two things stop that: the fixture (test-resources/event-emitter.yaml)
# guarantees events exist and carry a token nothing else emits, and every query below is
# routed through loki-query.sh, which fails rather than returns empty when Loki has
# nothing to give it.

FIXTURE_NAMESPACE="default"
# The image name in test-resources/event-emitter.yaml, reproduced verbatim by the
# kubelet in the message of the event it emits about it.
MARKER="chainsaw-event-marker"
JOB="kubernetes-events"

# What the collector pushes, as seen through /series:
#   job          the `job_name` argument of loki.source.kubernetes_events.
#   namespace    set natively by the component, from the INVOLVED OBJECT.
#   severity     derived in events.d/events.alloy from the event's `type` field.
#   service_name added by Loki itself at ingestion: discover_service_name takes the first
#                of service_name/service/app/.../job that exists, and `job` is the only
#                one of those these streams carry.
# `instance` is NOT here on purpose: the component sets it to its own component ID, and
# events.d/events.alloy drops it so the label keeps the one meaning it has elsewhere.
PUSHED_LABELS="job namespace service_name severity"

# ...except that an event about a CLUSTER-SCOPED object (a Node, a PersistentVolume, a
# ClusterRole) has an involved object with no namespace. The component sets `namespace`
# unconditionally from the involved object, so it goes on the wire as the empty string,
# and Loki drops empty-valued labels on INGEST - before the stream hash, so no such
# series is ever stored (syntax.ParseLabels -> labels.Builder; grafana/loki#7355, in
# every release since 2.7.0). Those streams therefore carry three labels, not four.
#
# Accepted as upstream behaviour rather than papered over with a synthetic value: an
# event about a Node genuinely has no namespace, and inventing one would put a made-up
# value into a dimension operators filter on. It does mean `{namespace=~".+"}` silently
# excludes cluster-scoped events - which is exactly why it is recorded here rather than
# left to be discovered during an incident.
#
# This is an ALTERNATIVE the label-set assertion accepts, not one it requires: whether a
# cluster-scoped event falls inside the query window depends on when the cluster last
# produced one, and entries carry the event's own timestamp. Assert nothing on its
# presence.
CLUSTER_SCOPED_LABELS="job service_name severity"

FAILED=0

fail() {
  echo "FAIL: $*" >&2
  FAILED=1
}

# expect <what> <got> <want>
expect() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1 = '$2'"
  else
    fail "$1: got '$2', expected '$3'"
  fi
}

sorted() {
  tr ' ' '\n' <<<"$1" | sed '/^$/d' | sort | paste -sd' ' -
}

# assert_label_set <description> <got, space separated> <want, unsorted> [alternative want]
assert_label_set() {
  local what="$1" got want alt missing extra
  got="$(sorted "$2")"
  want="$(sorted "$3")"
  alt="$(sorted "${4:-}")"
  if [ "$got" = "$want" ] || { [ -n "$alt" ] && [ "$got" = "$alt" ]; }; then
    echo "ok: ${what} label set matches exactly ('${got}')"
    return
  fi
  missing="$(comm -23 <(tr ' ' '\n' <<<"$want" | sort) <(tr ' ' '\n' <<<"$got" | sort) | paste -sd' ' -)"
  extra="$(comm -13 <(tr ' ' '\n' <<<"$want" | sort) <(tr ' ' '\n' <<<"$got" | sort) | paste -sd' ' -)"
  fail "${what} label set mismatch
        got:      ${got}
        expected: ${want}${alt:+ (or, for a cluster-scoped involved object, ${alt})}
        missing:  ${missing:-<none>}
        extra:    ${extra:-<none>}"
}

# ---------------------------------------------------------------------------------
# Establish from the Kubernetes API that the fixture really did produce both event
# types, BEFORE asking Loki anything.
#
# Without this, "Loki has no Warning event" and "the cluster produced no Warning event"
# are the same failure message, and they have completely different causes.
# ---------------------------------------------------------------------------------
#
# Asserted as type/reason pairs, not bare types: the synthetic Warning created just below
# also involves this pod, and a bare-type check would happily accept it as proof that the
# kubelet emitted one.
api_event_pairs() {
  kubectl -n "$FIXTURE_NAMESPACE" get events \
    --field-selector "involvedObject.name=event-emitter" \
    -o jsonpath='{range .items[*]}{.type}/{.reason}{"\n"}{end}' | sort -u | paste -sd' ' -
}

API_PAIRS="$(api_event_pairs)"
echo "fixture: the API holds type/reason pair(s) '${API_PAIRS}' for pod/event-emitter"
for want_pair in Normal/Scheduled Warning/ErrImageNeverPull; do
  case " ${API_PAIRS} " in
    *" ${want_pair} "*) echo "ok: the API has a ${want_pair} event for the fixture" ;;
    *)
      echo "FAIL: the fixture produced no ${want_pair} event; every Loki assertion below" >&2
      echo "      would be testing the fixture rather than the pipeline." >&2
      kubectl -n "$FIXTURE_NAMESPACE" get events --field-selector involvedObject.name=event-emitter >&2 || true
      kubectl -n "$FIXTURE_NAMESPACE" describe pod event-emitter >&2 || true
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------------
# Created here so it has the rest of the run to arrive; asserted at the end.
#
# WHY A DELIBERATELY STALE EVENT EXISTS AT ALL
# --------------------------------------------
# `loki.source.kubernetes_events` stamps each entry with the EVENT's own timestamp
# (LastTimestamp, else EventTime), never the ingest time. Loki accepts an out-of-order
# entry only while it is no older than `ingester.max_chunk_age / 2` behind the newest
# entry already in that stream - 60 minutes at the defaults this module ships. Nothing
# else in this suite ever produces an entry that is not "now", so a change that narrowed
# that window (a smaller max_chunk_age, a tighter reject_old_samples_max_age) would leave
# every assertion above green while silently discarding events in production.
#
# The stale case is not hypothetical: this instance's positions file is on an emptyDir,
# so any restart makes the informer re-List everything the API server still holds and
# re-deliver it at its original timestamp - bounded by the ~1h Event TTL, i.e. arriving
# at the very edge of that 60-minute window. 45 minutes probes inside the window with
# margin; a passing run means a restart's replay lands rather than being dropped.
#
# It goes into the same stream as the fixture's Warning events (same namespace, same
# severity), whose newest entry is "now" - so it is genuinely measured against a current
# watermark rather than seeding a fresh stream, which would bypass the check entirely.
STALE_MINUTES=45
STALE_MARKER="chainsaw-stale-event-marker"
STALE_TS="$(date -u -d "-${STALE_MINUTES} minutes" +%Y-%m-%dT%H:%M:%SZ)"
# The same instant as an epoch, so section 5 can compare what Loki stamped against the
# literal value written into the Event below rather than against "now" - see there.
STALE_TS_EPOCH="$(date -u -d "$STALE_TS" +%s)"
echo "creating a synthetic Event dated ${STALE_TS} (${STALE_MINUTES}m in the past)"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Event
metadata:
  name: chainsaw-stale-event-probe
  namespace: ${FIXTURE_NAMESPACE}
type: Warning
reason: ChainsawStaleProbe
message: "${STALE_MARKER} dated ${STALE_TS}"
firstTimestamp: "${STALE_TS}"
lastTimestamp: "${STALE_TS}"
count: 1
involvedObject:
  apiVersion: v1
  kind: Pod
  name: event-emitter
  namespace: ${FIXTURE_NAMESPACE}
source:
  component: chainsaw
EOF

# ---------------------------------------------------------------------------------
# 1. The fixture's Warning events are retrievable, and their body is intact.
# ---------------------------------------------------------------------------------
WARNING_SELECTOR="{job=\"${JOB}\", namespace=\"${FIXTURE_NAMESPACE}\", severity=\"warning\"}"
WARNING_RESULT="$(../chainsaw/scripts/loki-query.sh \
  --query="${WARNING_SELECTOR} |= \"${MARKER}\"" \
  --min-streams=1 \
  --limit=200 \
  --deadline=180 \
  --diagnostic-match="{job=\"${JOB}\"}")"

echo "--- warning stream label maps under assertion (query_range: indexed + metadata) ---"
echo "$WARNING_RESULT" | jq -S '[.[].stream]'

# Deliberately NO stream-count assertion on this result. query_range's `.stream` map is
# Loki's flattened view - indexed labels AND structured metadata merged, including the
# `detected_level` Loki derives per line from the line's own text (see
# check-log-label-contract.sh's header). One event whose message trips a different branch
# of that heuristic splits this result in two with nothing having leaked, and an "== 1"
# here would then fail while blaming the collector. Stream counts are asserted in section
# 3 instead, against /series, which reports indexed labels only.

WARNING_LINES="$(echo "$WARNING_RESULT" | jq -r '[.[].values[][1]] | join("\n")')"
if [ -z "$WARNING_LINES" ]; then
  fail "the warning stream returned no log lines"
fi

# The line body is logfmt. These two prove the deliberate half of the label decision:
# `reason` and `type` were kept OUT of the label set but are still queryable in the text,
# which is the entire justification for not indexing them.
for body_field in "reason=" "type=Warning"; do
  if grep -qF -- "$body_field" <<<"$WARNING_LINES"; then
    echo "ok: '${body_field}' is present in the line body"
  else
    fail "'${body_field}' is missing from the line body; the logfmt payload is not what events.d/events.alloy expects"
    echo "$WARNING_LINES" | head -5 >&2
  fi
done

# ---------------------------------------------------------------------------------
# 2. Normal events map to severity=info.
#
# The retrieval itself is the assertion: loki-query.sh fails rather than returns empty
# below --min-streams, so reaching the next line means events with severity="info"
# exist. Queried without a line filter because the fixture's Normal event is `Scheduled`,
# whose message carries the node name rather than the image name; the API check above is
# what keeps that non-vacuous.
# ---------------------------------------------------------------------------------
INFO_SELECTOR="{job=\"${JOB}\", namespace=\"${FIXTURE_NAMESPACE}\", severity=\"info\"}"
INFO_RESULT="$(../chainsaw/scripts/loki-query.sh \
  --query="$INFO_SELECTOR" \
  --min-streams=1 \
  --limit=200 \
  --deadline=120 \
  --diagnostic-match="{job=\"${JOB}\"}")"
echo "--- info stream label maps (query_range: indexed + metadata) ---"
echo "$INFO_RESULT" | jq -S '[.[].stream]'

# ---------------------------------------------------------------------------------
# 3. Exact indexed label-set equality, over every event stream in the cluster.
#
# Deliberately not scoped to the fixture's namespace: the contract is about what this
# pipeline pushes, and a leaked label would most likely appear on every stream. Gated on
# the queries above having returned data, so an empty result cannot pass for a clean one.
# ---------------------------------------------------------------------------------
SERIES="$(../chainsaw/scripts/loki-query.sh \
  --query="{job=\"${JOB}\"}" \
  --emit=series \
  --series-match="{job=\"${JOB}\"}" \
  --min-streams=1 \
  --deadline=60 \
  --diagnostic-match="{job=\"${JOB}\"}")"

echo "--- indexed label maps under assertion (/series) ---"
echo "$SERIES" | jq -S '.'

SERIES_COUNT="$(echo "$SERIES" | jq 'length')"
if [ "$SERIES_COUNT" -lt 1 ]; then
  echo "FAIL: no event streams to assert against; everything below would pass vacuously" >&2
  exit 1
fi
for idx in $(seq 0 $((SERIES_COUNT - 1))); do
  assert_label_set "indexed event stream[${idx}]" \
    "$(echo "$SERIES" | jq -r ".[${idx}] | keys | join(\" \")")" \
    "$PUSHED_LABELS" "$CLUSTER_SCOPED_LABELS"
done

expect "service_name" \
  "$(echo "$SERIES" | jq -r '[.[].service_name] | unique | join(",")')" "$JOB"

# Exactly one indexed stream per (namespace, severity) pair. job, namespace, severity and
# service_name are the whole label set, so a fixture namespace that produced two streams
# at one severity means a label leaked into the index. Counted here, over /series, rather
# than over the query_range results in sections 1 and 2 - those carry structured metadata
# and would split for reasons that have nothing to do with the pushed label set.
for severity in warning info; do
  expect "indexed stream count for namespace=${FIXTURE_NAMESPACE} severity=${severity}" \
    "$(echo "$SERIES" | jq "[.[] | select(.namespace == \"${FIXTURE_NAMESPACE}\" and .severity == \"${severity}\")] | length")" \
    "1"
done

# Both values of the mapping and no third one, observed across every event stream in the
# cluster - not just the two the selectors above pin. `severity` is derived by a
# stage.template over the event's `type`, and a template that passed its input through
# ("Normal"/"Warning"), ignored it (one value everywhere), or emitted nothing for an
# absent type all show up here.
expect "severity values observed" \
  "$(echo "$SERIES" | jq -r '[.[].severity] | unique | join(",")')" \
  "info,warning"

# The fixture's namespace must be among the namespaces that produced streams. `namespace`
# is set natively by the component from the involved object, so a component that had
# fallen back to its own namespace, or to none, is caught here.
NAMESPACES="$(echo "$SERIES" | jq -r '[.[].namespace] | unique | join(",")')"
if grep -qw "$FIXTURE_NAMESPACE" <<<"${NAMESPACES//,/ }"; then
  echo "ok: '${FIXTURE_NAMESPACE}' is among the namespaces with event streams (${NAMESPACES})"
else
  fail "no event stream for namespace '${FIXTURE_NAMESPACE}'; namespaces seen: ${NAMESPACES}"
fi

# ---------------------------------------------------------------------------------
# 4. Absence. Implied by the set equality above, asserted separately so the intent
#    survives a future edit to the expected set.
# ---------------------------------------------------------------------------------
for absent in reason type instance name kind count; do
  if [ "$(echo "$SERIES" | jq -r "[.[] | has(\"${absent}\")] | any")" = "false" ]; then
    echo "ok: '${absent}' is not an indexed label"
  else
    fail "'${absent}' has become an indexed stream label. Every field of an Event other than its namespace belongs in the line body: promoting one multiplies the stream count by that field's cardinality, and 'reason' in particular is unbounded (see events.d/events.alloy)"
  fi
done

# ---------------------------------------------------------------------------------
# 5. The stale event created at the top arrived, AT ITS OWN TIMESTAMP.
#
# Two distinct things are proven here, by two different mechanisms:
#   - Loki ACCEPTED an entry STALE_MINUTES behind the newest entry in a live stream.
#     Proven by the query below returning at all: it runs with --min-streams=1,
#     so a narrowed out-of-order window (a smaller ingester.max_chunk_age, a tighter
#     reject_old_samples_max_age) drops the entry and fails the query. This is why
#     STALE_MINUTES is a deliberate choice and not an arbitrary one - far enough in the
#     past to actually exercise the acceptance window, and inside the
#     max_chunk_age / 2 = 60-minute boundary with margin to spare.
#   - the entry was STAMPED with the event's own time, not with ingest time. Proven by
#     comparing it to the Event's lastTimestamp below.
# The lookback has to exceed the staleness or the query cannot see its own fixture.
# ---------------------------------------------------------------------------------
STALE_RESULT="$(../chainsaw/scripts/loki-query.sh \
  --query="${WARNING_SELECTOR} |= \"${STALE_MARKER}\"" \
  --min-streams=1 \
  --lookback=90m \
  --limit=10 \
  --deadline=120 \
  --diagnostic-match="{job=\"${JOB}\"}")"
echo "ok: loki accepted an entry ${STALE_MINUTES}m behind the newest entry in a live stream"

STALE_ENTRY_EPOCH="$(echo "$STALE_RESULT" | jq -r '[.[].values[][0] | tonumber] | min / 1000000000 | floor')"
STALE_SKEW=$(( STALE_ENTRY_EPOCH - STALE_TS_EPOCH ))
echo "stale probe: loki stamped the entry $(date -u -d "@${STALE_ENTRY_EPOCH}" +%Y-%m-%dT%H:%M:%SZ); the Event's lastTimestamp is ${STALE_TS} (skew ${STALE_SKEW}s)"

# Compared against the Event's OWN lastTimestamp, never against "now". An elapsed-time
# measurement would drift by however long this suite takes to get here - the step budget
# is 15m and the queries above alone are allowed ~8m - and on a loaded runner would fail
# reporting ingest-time stamping, which is the opposite of what a slow run shows. Both
# sides of this comparison are instead the literal value written into the Event above, so
# it is fixed no matter how long the run takes. The tolerance covers that field's
# second-resolution and nothing more; an entry carrying ingest time is STALE_MINUTES out
# and cannot pass it.
STALE_TOLERANCE=5
if [ "${STALE_SKEW#-}" -gt "$STALE_TOLERANCE" ]; then
  fail "the stale probe entry is stamped ${STALE_SKEW}s from the Event's lastTimestamp (${STALE_TS}), expected within ${STALE_TOLERANCE}s. loki.source.kubernetes_events has stopped stamping entries with the event's own timestamp; with ingest-time stamping nothing in this suite would ever exercise loki's out-of-order acceptance window again"
else
  echo "ok: the stale probe entry kept the event's own timestamp (within ${STALE_TOLERANCE}s)"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "kubernetes event stream contract violated (see FAIL lines above)" >&2
  exit 1
fi
echo "kubernetes event stream contract holds"
