#!/bin/bash
set -euo pipefail

# Asserts the observable output contract of log collection: the exact set of labels
# that arrive in Loki for a pod log line, and the shape of each value.
#
# WHY AN EXACT SET AND NOT A SUPERSET
# -----------------------------------
# A superset check ("all the labels I care about are present") passes while a collector
# leaks extra labels through: an unstripped __meta_*, a duplicated service_name variant,
# a "collector" marker. Those are cardinality and cost regressions that nothing else in
# this repo would notice, and they are precisely the class of mistake a rewritten
# collector config makes. So the assertion is set equality.
#
# WHICH ENDPOINT, AND WHY TWO
# ---------------------------
# Not /loki/api/v1/labels: that reports the union over every stream in the cluster -
# the collector's own logs, kube-system, Loki, Prometheus, MinIO. It can neither gain nor
# lose a label because of what happened to OUR fixture, so equality against it would be
# both meaningless and flaky.
#
# The fixture's own streams are read through two endpoints, because they answer
# different questions and a collector regression can hide in the gap between them:
#
#   query_range  Loki's FLATTENED view: indexed stream labels and structured metadata
#                merged into one map (this is what Grafana shows, and what the
#                production label list was read from). Also the only view that proves
#                log lines actually arrived and carries their content.
#   /series      INDEXED stream labels only.
#
# A collector that demoted a real label to structured metadata - trivially easy to do in
# Alloy's loki.process - is invisible in the first view and caught by the second. The two
# expected sets below therefore differ by exactly the labels Loki itself adds.
#
# IN SCOPE vs OUT OF SCOPE
# ------------------------
# Production Loki carries fifteen pushed labels:
#
#   app component container filename host instance job namespace node_name pod
#   service_name severity stream syslog_identifier systemd_unit
#
# The last three - severity, syslog_identifier, systemd_unit - come ONLY from the
# `loki.source.journal` component in journal.alloy. kind nodes have no systemd journal
# (nothing to read under /run/log/journal or /var/log/journal), so it collects nothing here
# and those labels cannot appear no matter how correct the config is. They are deliberately
# excluded below, and this layer therefore asserts the POD-LOG contract only - the part
# kind can actually prove. Journal behaviour is validated separately against a VM with a
# real journal. Do not "fix" a future failure by widening or narrowing these sets without
# deciding which of the two contracts you are changing.
#
# `method` and `status` are asserted absent for a different reason again. They are real
# production labels: traefik's access-log pipeline attaches them via `stage.json` +
# `stage.labels`. But that pipeline lives in a CLUSTER-INJECTED `.alloy` fragment, and
# Alloy loads the module's own files and those fragments as ONE merged component graph -
# so a mis-wired `forward_to` in a fragment can route ordinary pod-log entries through the
# traefik pipeline. This fixture is a plain stdout workload; these two labels turning up on
# ITS stream is the visible symptom of exactly that cross-contamination, a failure mode
# this composition design newly introduces. The assertion guards that seam - it is NOT a
# claim that `method`/`status` exist nowhere.
#
# NO COLLECTOR SELECTOR
# ---------------------
# `{job="default/logspewer"}` matches the fixture's streams and nothing else, because
# exactly one collector reads these logs. There was briefly a second - a `collector`
# external label isolated Alloy's streams from Promtail's while the two ran in parallel -
# and that label is now asserted ABSENT below rather than matched on. Reintroducing a
# selector for a collector that is not running is the specific way this file goes
# quietly wrong: a matcher that resolves to no streams makes every assertion below true
# for free.
#
# WHAT WOULD MAKE THIS VACUOUS - `--collector-name`
# -------------------------------------------------
# "Every label this collector pushed is correct" is trivially true of a collector that
# pushed nothing. Two things stop that:
#
#   1. loki-query.sh is called with --min-streams=2 and the exact count is asserted
#      afterwards, so an empty or partial result is a failure, not a pass.
#   2. --collector-name=<app.kubernetes.io/name> names the DaemonSet workload behind the
#      label, and its presence ON THE FIXTURE'S NODE is checked before anything is
#      queried. A DaemonSet reports Ready when every pod it SCHEDULED is ready, so a node
#      it never scheduled onto at all is invisible in its status - which is exactly what
#      the alloy chart's empty default `tolerations` did to kind's tainted control-plane
#      node. If the fixture then lands on that node, the collector genuinely never sees
#      it. (1) would still catch that, but 180 seconds later and phrased as "Loki returned
#      nothing", which reads like a slow pipeline rather than a node with no collector on
#      it.

COLLECTOR_NAME=""
COLLECTOR_NAMESPACE="logging"

for param in "$@"
do
  case $param in
    --collector-name=*)
      COLLECTOR_NAME="${param#*=}"
      shift
      ;;
    *)
      echo "Unknown parameter: $param" >&2
      exit 1
      ;;
  esac
done

if [ -z "$COLLECTOR_NAME" ]; then
  echo "--collector-name=<app.kubernetes.io/name> is required" >&2
  exit 1
fi

FIXTURE_NAMESPACE="default"
FIXTURE_APP="logspewer"
FIXTURE_INSTANCE="logspewer-ci"
FIXTURE_COMPONENT="spewer"
FIXTURE_CONTAINER="logspewer"
MARKER="chainsaw-logspewer-marker"

# What the collector pushes, as seen through /series. This is the list the production
# contract is actually about.
PUSHED_LABELS="app component container filename host instance job namespace node_name pod service_name stream"

# What a query returns: the pushed set plus what Loki adds on its own.
#   service_name  - already in the pushed set above because Loki writes it as a real
#                   indexed stream label at ingestion (discover_service_name takes the
#                   first of service_name/service/app/... that exists, hence `app`).
#   detected_level - Loki's discover_log_levels, attached as STRUCTURED METADATA, which
#                   Loki flattens into the response's label map. It is therefore present
#                   here and absent from the pushed set - not an inconsistency, the whole
#                   reason both sets exist.
QUERY_LABELS="${PUSHED_LABELS} detected_level"

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

# assert_label_set <description> <got, space separated and sorted> <want, unsorted>
assert_label_set() {
  local what="$1" got want missing extra
  got="$(sorted "$2")"
  want="$(sorted "$3")"
  if [ "$got" = "$want" ]; then
    echo "ok: ${what} label set matches exactly"
    return
  fi
  missing="$(comm -23 <(tr ' ' '\n' <<<"$want" | sort) <(tr ' ' '\n' <<<"$got" | sort) | paste -sd' ' -)"
  extra="$(comm -13 <(tr ' ' '\n' <<<"$want" | sort) <(tr ' ' '\n' <<<"$got" | sort) | paste -sd' ' -)"
  fail "${what} label set mismatch
        got:      ${got}
        expected: ${want}
        missing:  ${missing:-<none>}
        extra:    ${extra:-<none>}"
}

# ---------------------------------------------------------------------------------
# Establish the fixture's identity from the Kubernetes API, NOT from Loki.
#
# This matters more than it looks. Deriving the expected node name from the same push
# that is being validated would make the host assertion self-fulfilling: whatever the
# collector claimed would be "correct". kubectl is the independent source.
# ---------------------------------------------------------------------------------
mapfile -t FIXTURE_PODS < <(
  kubectl -n "$FIXTURE_NAMESPACE" get pods \
    -l "app.kubernetes.io/name=${FIXTURE_APP}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)
if [ "${#FIXTURE_PODS[@]}" -ne 1 ]; then
  echo "FAIL: expected exactly 1 ${FIXTURE_APP} pod, found ${#FIXTURE_PODS[@]}: ${FIXTURE_PODS[*]:-<none>}" >&2
  exit 1
fi
FIXTURE_POD="${FIXTURE_PODS[0]}"
FIXTURE_NODE="$(kubectl -n "$FIXTURE_NAMESPACE" get pod "$FIXTURE_POD" -o jsonpath='{.spec.nodeName}')"
if [ -z "$FIXTURE_NODE" ]; then
  echo "FAIL: could not read .spec.nodeName for pod/${FIXTURE_POD}" >&2
  exit 1
fi
echo "fixture: pod=${FIXTURE_POD} node=${FIXTURE_NODE} namespace=${FIXTURE_NAMESPACE}"

# Guard the host assertion against being satisfiable by the wrong value: if the node and
# pod names were ever the same string, "host == node name" would also be satisfied by a
# collector reading the wrong downward-API field, which is a real failure mode.
if [ "$FIXTURE_NODE" = "$FIXTURE_POD" ]; then
  echo "FAIL: node name and pod name are identical; the host assertion would prove nothing" >&2
  exit 1
fi

# ---------------------------------------------------------------------------------
# The collector under test must be running on the node the fixture landed on.
#
# Everything below asserts properties of the streams this collector pushed for this
# fixture. If it has no pod on the fixture's node it pushed none, and "no bad labels" is
# then true for free. See the --collector-name note in the header for why a Ready
# DaemonSet does not rule this out. Checked here rather than left to the empty-result
# failure so the message names the cause.
# ---------------------------------------------------------------------------------
COLLECTOR_PODS_ON_NODE="$(
  kubectl -n "$COLLECTOR_NAMESPACE" get pods \
    -l "app.kubernetes.io/name=${COLLECTOR_NAME}" \
    --field-selector "spec.nodeName=${FIXTURE_NODE},status.phase=Running" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}'
)"
if [ -z "$COLLECTOR_PODS_ON_NODE" ]; then
  echo "FAIL: no Running ${COLLECTOR_NAME} pod on node ${FIXTURE_NODE}, which is where the fixture is." >&2
  echo "      Nothing collected the fixture, so every label assertion below would pass vacuously." >&2
  kubectl -n "$COLLECTOR_NAMESPACE" get pods -l "app.kubernetes.io/name=${COLLECTOR_NAME}" -o wide >&2 || true
  kubectl get nodes -o wide >&2 || true
  exit 1
fi
echo "collector: ${COLLECTOR_NAME} running on the fixture's node as ${COLLECTOR_PODS_ON_NODE% }"

# Deliberately unqualified by collector - see the header. One collector reads this
# fixture, so this selects everything it pushed and the exact-count assertion below turns
# "the collector stopped shipping" into a failure instead of a vacuous pass.
SELECTOR="{job=\"${FIXTURE_NAMESPACE}/${FIXTURE_APP}\"}"
QUERY="${SELECTOR} |= \"${MARKER}\""

# ---------------------------------------------------------------------------------
# Fetch the fixture's streams, both views.
# ---------------------------------------------------------------------------------
RESULT="$(../chainsaw/scripts/loki-query.sh \
  --query="$QUERY" \
  --min-streams=2 \
  --limit=200 \
  --deadline=180 \
  --diagnostic-match="{namespace=\"${FIXTURE_NAMESPACE}\"}")"

SERIES="$(../chainsaw/scripts/loki-query.sh \
  --query="$QUERY" \
  --emit=series \
  --series-match="$SELECTOR" \
  --min-streams=2 \
  --deadline=60 \
  --diagnostic-match="{namespace=\"${FIXTURE_NAMESPACE}\"}")"

# loki-query.sh already fails below --min-streams, but assert the exact count here too:
# two streams (one per direction) is the expectation, and MORE than two means the
# fixture's identity fragmented (a restart rotating <n>.log, a second replica), which
# would otherwise let the per-stream checks below run against a subset.
STREAM_COUNT="$(echo "$RESULT" | jq 'length')"
expect "stream count" "$STREAM_COUNT" "2"
if [ "$STREAM_COUNT" -lt 1 ]; then
  echo "FAIL: no streams to assert against; everything below would pass vacuously" >&2
  exit 1
fi
expect "indexed stream count" "$(echo "$SERIES" | jq 'length')" "2"

echo "--- label maps under assertion (query_range: indexed + structured metadata) ---"
echo "$RESULT" | jq -S '[.[].stream]'
echo "--- label maps under assertion (/series: indexed only) ---"
echo "$SERIES" | jq -S '.'

# ---------------------------------------------------------------------------------
# 1. Exact label-set equality, per stream, in both views.
# ---------------------------------------------------------------------------------
for idx in $(seq 0 $((STREAM_COUNT - 1))); do
  # jq's `keys` is sorted, and so is `sorted()`, so this is like-for-like.
  assert_label_set "query_range stream[${idx}]" \
    "$(echo "$RESULT" | jq -r ".[${idx}].stream | keys | join(\" \")")" "$QUERY_LABELS"
done
for idx in $(seq 0 $(( $(echo "$SERIES" | jq 'length') - 1 ))); do
  assert_label_set "indexed stream[${idx}]" \
    "$(echo "$SERIES" | jq -r ".[${idx}] | keys | join(\" \")")" "$PUSHED_LABELS"
done

# ---------------------------------------------------------------------------------
# 2. Value shapes, each asserted individually so a failure names the label that broke.
#
# Checked on stream[0]; every label except `stream` is identical across both streams,
# and the label-set equality above already ran against each of them.
# ---------------------------------------------------------------------------------
label() {
  echo "$RESULT" | jq -r ".[0].stream[\"$1\"] // \"<absent>\""
}

# `job` is the dimension that collapsed from 118 distinct values to 4 in one of the
# reviewed collector rewrites. Its shape is <namespace>/<app>, not the scrape job's name.
expect "job" "$(label job)" "${FIXTURE_NAMESPACE}/${FIXTURE_APP}"

# `filename` proves the regex pipeline stage that strips the /var/log/pods/<...>/ prefix
# is present and working. Unstripped, this would be the full host path.
expect "filename" "$(label filename)" "${FIXTURE_CONTAINER}/0.log"

# `host` is the NODE name - write.alloy sets it from the K8S_NODE_NAME env var, which the
# chart wires to fieldRef spec.nodeName - not the pod name and not the collector pod's
# name.
expect "host" "$(label host)" "$FIXTURE_NODE"
if [ "$(label host)" = "$FIXTURE_POD" ]; then
  fail "host is the POD name, not the node name - the exact downward-API mix-up this check exists for"
fi

# `node_name` comes from a relabel rule rather than from the client external label; it
# must agree with `host`, and both must agree with the API.
expect "node_name" "$(label node_name)" "$FIXTURE_NODE"

expect "namespace" "$(label namespace)" "$FIXTURE_NAMESPACE"
expect "pod" "$(label pod)" "$FIXTURE_POD"
expect "container" "$(label container)" "$FIXTURE_CONTAINER"

# The three pod-label-derived dimensions. The fixture gives them deliberately different
# values so a crossed or collapsed relabel rule cannot pass.
expect "app" "$(label app)" "$FIXTURE_APP"
expect "instance" "$(label instance)" "$FIXTURE_INSTANCE"
expect "component" "$(label component)" "$FIXTURE_COMPONENT"

# Loki-derived, not collector-pushed - asserted because Loki's own retention_stream
# selectors and the dashboards key off it, and it silently changes if `app` stops being
# pushed.
expect "service_name" "$(label service_name)" "$FIXTURE_APP"

# `stream` is produced by the CRI parsing stage, not by any relabel rule, so it is only
# proven by observing BOTH of its values.
expect "stream values" "$(echo "$RESULT" | jq -r '[.[].stream.stream] | sort | join(",")')" "stderr,stdout"

# ...and that the value is not merely present but correct: the fixture writes which file
# descriptor it used into the line text, so a swapped stdout/stderr classification shows
# up as a mismatch between the label and the payload.
for idx in $(seq 0 $((STREAM_COUNT - 1))); do
  direction="$(echo "$RESULT" | jq -r ".[${idx}].stream.stream")"
  mismatches="$(echo "$RESULT" | jq -r "[.[${idx}].values[][1] | select(contains(\"stream=${direction}\") | not)] | length")"
  lines="$(echo "$RESULT" | jq -r ".[${idx}].values | length")"
  if [ "$lines" -lt 1 ]; then
    fail "stream '${direction}' returned no log lines"
  elif [ "$mismatches" -ne 0 ]; then
    fail "stream '${direction}': ${mismatches}/${lines} lines were written to the other file descriptor"
  else
    echo "ok: all ${lines} lines on stream '${direction}' were written to that descriptor"
  fi
done

# ---------------------------------------------------------------------------------
# 3. Absence. Implied by the set equality above, asserted separately so the intent
#    survives a future edit to the expected sets.
# ---------------------------------------------------------------------------------
for absent in method status; do
  if [ "$(label "$absent")" = "<absent>" ]; then
    echo "ok: '${absent}' is absent, as it must be on a plain stdout stream"
  else
    fail "'${absent}' is present with value '$(label "$absent")'; this label is produced by traefik's access-log pipeline, which lives in a cluster-injected .alloy fragment - a plain stdout fixture carrying it means a fragment's forward_to is routing pod logs through that pipeline"
  fi
done

# `collector` was a temporary external label that distinguished Alloy's streams from
# Promtail's during the migration. It is gone, and it has to stay gone: while it is set,
# every stream Alloy pushes carries it, and Alloy's series never rejoin the historical
# ones it is supposed to be continuing. Asserted here rather than left to set equality
# above so that the reason survives an edit to the expected sets.
if [ "$(label collector)" = "<absent>" ]; then
  echo "ok: 'collector' is absent - the migration marker is not being pushed"
else
  fail "'collector' is present with value '$(label collector)'; this was a temporary migration label and must not be reintroduced - it permanently forks every stream away from its historical series"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "log-label contract violated (see FAIL lines above)" >&2
  exit 1
fi
echo "log-label contract holds"
