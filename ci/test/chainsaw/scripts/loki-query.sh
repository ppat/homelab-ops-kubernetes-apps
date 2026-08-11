#!/bin/bash
set -euo pipefail

# Runs a LogQL query against an in-cluster Loki and fails if it does not return at
# least --min-streams streams before --deadline expires.
#
# This exists because every other assertion in ci/test/ is structural: it reads a
# resource's own status and believes it. A log pipeline is the one place where that is
# not enough - the collector's DaemonSet stays Ready, Loki's StatefulSet stays Ready, and
# Grafana keeps rendering, while a dropped relabel rule or an unexpanded glob quietly
# collects nothing. The only thing that can distinguish "healthy" from "healthy and
# actually working" is querying the output side.
#
# Contract with callers:
#   stdout - on success only, one JSON array, chosen by --emit:
#              result (default) the query's `data.result` - stream label maps plus the
#                               matching log lines.
#              series           `/loki/api/v1/series` for --series-match, gated on the
#                               same query first returning data.
#            The two are NOT interchangeable, and the difference is load-bearing:
#            query_range's `stream` map is Loki's flattened view - indexed stream labels
#            AND structured metadata merged together - whereas /series reports indexed
#            stream labels only. A collector that demoted a real label to structured
#            metadata (an easy thing to do in Alloy's loki.process) looks identical in
#            the first view and is caught by the second.
#   stderr - all progress and diagnostics. Never parse it.
#   exit 1 - fewer than --min-streams streams were returned before the deadline, or
#            Loki never became reachable. Before exiting it dumps what Loki DID have
#            (label names, and the full label set of every stream matching
#            --diagnostic-match), because "assertion failed" on its own tells the next
#            maintainer nothing about whether the labels changed, the collection
#            stopped, or the query was simply wrong.
#
# Reachability is via `kubectl port-forward`, matching how ci/test/apps-ai's
# check-mcp-kubernetes-rbac.sh already talks to an in-cluster service from a chainsaw
# script step. That keeps the query on the runner's own curl/jq (both preinstalled on
# the ubuntu-24.04 runner this suite runs on) instead of introducing a pod, an image to
# pin, and a second thing that can fail to schedule.

QUERY=""
MIN_STREAMS=1
NAMESPACE="logging"
SERVICE="loki"
SERVICE_PORT=3100
LOCAL_PORT=13100
LOOKBACK="30m"
DEADLINE=180
LIMIT=100
DIAGNOSTIC_MATCH=""
EMIT="result"
SERIES_MATCH=""

for param in "$@"
do
  case $param in
    --emit=*)
      EMIT="${param#*=}"
      shift
      ;;
    --series-match=*)
      SERIES_MATCH="${param#*=}"
      shift
      ;;
    --query=*)
      QUERY="${param#*=}"
      shift
      ;;
    --min-streams=*)
      MIN_STREAMS="${param#*=}"
      shift
      ;;
    --namespace=*)
      NAMESPACE="${param#*=}"
      shift
      ;;
    --service=*)
      SERVICE="${param#*=}"
      shift
      ;;
    --service-port=*)
      SERVICE_PORT="${param#*=}"
      shift
      ;;
    --local-port=*)
      LOCAL_PORT="${param#*=}"
      shift
      ;;
    --lookback=*)
      LOOKBACK="${param#*=}"
      shift
      ;;
    --deadline=*)
      DEADLINE="${param#*=}"
      shift
      ;;
    --limit=*)
      LIMIT="${param#*=}"
      shift
      ;;
    --diagnostic-match=*)
      DIAGNOSTIC_MATCH="${param#*=}"
      shift
      ;;
    *)
      echo "Unknown parameter: $param" >&2
      exit 1
      ;;
  esac
done

if [ -z "$QUERY" ]; then
  echo "--query=<logql> is required" >&2
  exit 1
fi

case "$EMIT" in
  result) ;;
  series)
    if [ -z "$SERIES_MATCH" ]; then
      echo "--emit=series requires --series-match=<stream selector>" >&2
      exit 1
    fi
    ;;
  *)
    echo "--emit must be 'result' or 'series' (got '$EMIT')" >&2
    exit 1
    ;;
esac

case "$LOOKBACK" in
  *m) LOOKBACK_SECONDS=$(( ${LOOKBACK%m} * 60 )) ;;
  *h) LOOKBACK_SECONDS=$(( ${LOOKBACK%h} * 3600 )) ;;
  *s) LOOKBACK_SECONDS="${LOOKBACK%s}" ;;
  *)
    echo "--lookback must end in s, m or h (got '$LOOKBACK')" >&2
    exit 1
    ;;
esac

BASE="http://127.0.0.1:${LOCAL_PORT}"

kubectl port-forward -n "$NAMESPACE" "svc/${SERVICE}" "${LOCAL_PORT}:${SERVICE_PORT}" \
  >"/tmp/loki-query-port-forward.log" 2>&1 &
PF_PID=$!
# shellcheck disable=SC2064  # PF_PID must be expanded now, not when the trap fires.
trap "kill ${PF_PID} >/dev/null 2>&1 || true" EXIT

# Wait for the port-forward itself, separately from waiting for data: conflating the
# two turns "Loki was never reachable" into an indistinguishable timeout.
ready=0
for _ in $(seq 1 60); do
  if curl -fsS "${BASE}/ready" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "FAIL: loki (svc/${SERVICE} in ${NAMESPACE}) never answered /ready through the port-forward" >&2
  cat "/tmp/loki-query-port-forward.log" >&2 || true
  exit 1
fi

run_query() {
  local now start
  now="$(date +%s)"
  start=$(( now - LOOKBACK_SECONDS ))
  curl -fsS -G "${BASE}/loki/api/v1/query_range" \
    --data-urlencode "query=${QUERY}" \
    --data-urlencode "start=${start}" \
    --data-urlencode "end=${now}" \
    --data-urlencode "limit=${LIMIT}" \
    --data-urlencode "direction=forward" 2>/dev/null
}

dump_diagnostics() {
  local now start
  now="$(date +%s)"
  start=$(( now - LOOKBACK_SECONDS ))
  echo "--- diagnostics: label names Loki currently knows about ---" >&2
  curl -fsS -G "${BASE}/loki/api/v1/labels" \
    --data-urlencode "start=${start}" --data-urlencode "end=${now}" 2>/dev/null \
    | jq -c '.data' >&2 || echo "(labels endpoint unavailable)" >&2
  echo "--- diagnostics: values of the 'job' label ---" >&2
  curl -fsS -G "${BASE}/loki/api/v1/label/job/values" \
    --data-urlencode "start=${start}" --data-urlencode "end=${now}" 2>/dev/null \
    | jq -c '.data' >&2 || echo "(job label values unavailable)" >&2
  if [ -n "$DIAGNOSTIC_MATCH" ]; then
    echo "--- diagnostics: full label set of every stream matching ${DIAGNOSTIC_MATCH} ---" >&2
    curl -fsS -G "${BASE}/loki/api/v1/series" \
      --data-urlencode "match[]=${DIAGNOSTIC_MATCH}" \
      --data-urlencode "start=${start}" --data-urlencode "end=${now}" 2>/dev/null \
      | jq -S '.data' >&2 || echo "(series endpoint unavailable)" >&2
  fi
  echo "--- diagnostics: last response body for the failing query ---" >&2
  echo "${response:-<none>}" | head -c 4000 >&2
  echo >&2
}

# Log ingestion is asynchronous - the collector batches, and Loki's ingesters are queryable
# only once the write lands. Poll to a deadline rather than sleeping a fixed amount:
# a fixed sleep is a race that passes on a fast runner and flakes on a slow one, and
# tuning it upward costs every run the worst case.
echo "querying loki: ${QUERY} (want >= ${MIN_STREAMS} stream(s), deadline ${DEADLINE}s)" >&2
deadline_at=$(( $(date +%s) + DEADLINE ))
response=""
streams=0
while :; do
  response="$(run_query || true)"
  if [ -n "$response" ]; then
    streams="$(echo "$response" | jq '(.data.result // []) | length' 2>/dev/null || echo 0)"
  else
    streams=0
  fi
  if [ "$streams" -ge "$MIN_STREAMS" ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline_at" ]; then
    echo "FAIL: query returned ${streams} stream(s), expected at least ${MIN_STREAMS}" >&2
    echo "      query: ${QUERY}" >&2
    dump_diagnostics
    exit 1
  fi
  sleep 5
done

echo "ok: query returned ${streams} stream(s); label sets:" >&2
echo "$response" | jq -S '[.data.result[].stream]' >&2

if [ "$EMIT" = "result" ]; then
  echo "$response" | jq -c '.data.result'
  exit 0
fi

# --emit=series. Gated on the query above having returned data, so an empty series
# response means "these streams carry no indexed labels", never "nothing was collected".
now="$(date +%s)"
series="$(curl -fsS -G "${BASE}/loki/api/v1/series" \
  --data-urlencode "match[]=${SERIES_MATCH}" \
  --data-urlencode "start=$(( now - LOOKBACK_SECONDS ))" \
  --data-urlencode "end=${now}" 2>/dev/null || true)"
series_count="$(echo "${series:-}" | jq '(.data // []) | length' 2>/dev/null || echo 0)"
if [ "$series_count" -lt "$MIN_STREAMS" ]; then
  echo "FAIL: /series for ${SERIES_MATCH} returned ${series_count} stream(s), expected at least ${MIN_STREAMS}" >&2
  echo "      (the query_range above DID return ${streams}, so this is a label-indexing difference, not missing data)" >&2
  dump_diagnostics
  exit 1
fi
echo "ok: /series returned ${series_count} indexed stream(s) for ${SERIES_MATCH}" >&2
echo "$series" | jq -S '.data' >&2
echo "$series" | jq -c '.data'
