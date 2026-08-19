#!/bin/bash
set -euo pipefail

# Runs a PromQL instant query against an in-cluster Prometheus and fails if it does not
# return at least one result before --deadline expires.
#
# This exists for the same reason ../scripts/loki-query.sh does: everything else in
# ci/test/ checks that a resource's own status looks healthy, which a remote_write path
# can fail silently underneath - the ruler stays Ready, Prometheus stays Ready, and
# nothing in the Kubernetes API shows a wrong URL, a receiver that never actually turned
# on, or a rule that never got loaded. The only thing that can tell "configured" from
# "actually delivering" is querying Prometheus for the series the write is supposed to
# have produced.
#
# Contract with callers:
#   stdout - on success only, the query's `data.result` as a single JSON array.
#   stderr - all progress and diagnostics. Never parse it.
#   exit 1 - no result was returned before the deadline, or Prometheus never became
#            reachable. Before exiting it dumps the metric names Prometheus currently
#            knows about matching --diagnostic-match, because "assertion failed" alone
#            doesn't say whether the series never arrived or the query was just wrong.

QUERY=""
NAMESPACE="monitoring"
SERVICE="kube-prometheus-stack-prometheus"
SERVICE_PORT=9090
LOCAL_PORT=19090
DEADLINE=300
# Every curl below is bounded by this. Without a per-request cap the --deadline above is
# unenforceable: the polling loop only re-checks the clock *between* attempts, so a request
# that hangs inside curl never returns control to it, and the chainsaw step's own `timeout`
# does the killing instead. That reports "the assertion ran out of budget" for what was
# actually "this query never returned" -- which invites raising a budget that was never the
# problem. See issue #3724.
#
# 20s is derived from the budget this has to fit inside, not copied from a sibling: a healthy
# instant query here answers in well under a second, while ../steps/assert-prometheus-query.yaml
# allows 6m against this 300s deadline. The worst case past the deadline is one overshooting
# query plus one diagnostic query, so the cap has to leave 2x itself inside that 60s of slack.
CURL_MAX_TIME=20
DIAGNOSTIC_MATCH=""

for param in "$@"
do
  case $param in
    --query=*)
      QUERY="${param#*=}"
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
    --deadline=*)
      DEADLINE="${param#*=}"
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
  echo "--query=<promql> is required" >&2
  exit 1
fi

BASE="http://127.0.0.1:${LOCAL_PORT}"

kubectl port-forward -n "$NAMESPACE" "svc/${SERVICE}" "${LOCAL_PORT}:${SERVICE_PORT}" \
  >"/tmp/prometheus-query-port-forward.log" 2>&1 &
PF_PID=$!
# shellcheck disable=SC2064  # PF_PID must be expanded now, not when the trap fires.
trap "kill ${PF_PID} >/dev/null 2>&1 || true" EXIT

# Wait for the port-forward itself, separately from waiting for data: conflating the two
# turns "Prometheus was never reachable" into an indistinguishable timeout.
ready=0
for _ in $(seq 1 60); do
  # A liveness ping on an already-forwarded local port, not a query, so it takes a much tighter
  # bound than CURL_MAX_TIME: a hung probe then costs 10s of this readiness phase instead of
  # blocking the loop's 60 attempts from ever completing.
  if curl -fsS --max-time 10 "${BASE}/-/ready" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "FAIL: prometheus (svc/${SERVICE} in ${NAMESPACE}) never answered /-/ready through the port-forward" >&2
  cat "/tmp/prometheus-query-port-forward.log" >&2 || true
  exit 1
fi

run_query() {
  curl -fsS --max-time "${CURL_MAX_TIME}" -G "${BASE}/api/v1/query" \
    --data-urlencode "query=${QUERY}" 2>/dev/null
}

dump_diagnostics() {
  if [ -n "$DIAGNOSTIC_MATCH" ]; then
    echo "--- diagnostics: metric names currently matching ${DIAGNOSTIC_MATCH} ---" >&2
    curl -fsS --max-time "${CURL_MAX_TIME}" -G "${BASE}/api/v1/label/__name__/values" \
      --data-urlencode "match[]=${DIAGNOSTIC_MATCH}" 2>/dev/null \
      | jq -c '.data' >&2 || echo "(label values endpoint unavailable)" >&2
  fi
  echo "--- diagnostics: last response body for the failing query ---" >&2
  echo "${response:-<none>}" | head -c 4000 >&2
  echo >&2
}

# A remote-write sample takes a full rule-evaluation interval (plus ruler ring/WAL
# startup) to show up - poll to a deadline rather than sleeping a fixed amount, for the
# same reason loki-query.sh does: a fixed sleep is a race that passes on a fast runner
# and flakes on a slow one.
echo "querying prometheus: ${QUERY} (deadline ${DEADLINE}s)" >&2
deadline_at=$(( $(date +%s) + DEADLINE ))
response=""
result_count=0
while :; do
  response="$(run_query || true)"
  if [ -n "$response" ]; then
    result_count="$(echo "$response" | jq '(.data.result // []) | length' 2>/dev/null || echo 0)"
  else
    result_count=0
  fi
  if [ "$result_count" -ge 1 ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline_at" ]; then
    echo "FAIL: query returned ${result_count} result(s), expected at least 1" >&2
    echo "      query: ${QUERY}" >&2
    dump_diagnostics
    exit 1
  fi
  sleep 5
done

echo "ok: query returned ${result_count} result(s):" >&2
echo "$response" | jq -S '.data.result' >&2

echo "$response" | jq -c '.data.result'
