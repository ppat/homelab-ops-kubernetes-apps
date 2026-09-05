#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

NAMESPACE="versitygw"
export S3_LOCAL_PORT=17070
export ADMIN_LOCAL_PORT=17071
# The counters must have MOVED: a zero is equally consistent with "idle" and
# "the StatsD path is broken", and neither reports itself over UDP.
METRICS_LOCAL_PORT=19102
CURL_MAX_TIME=15

python3 -m pip install --quiet --user boto3

S3_REGION="$(kubectl get deployment -n "$NAMESPACE" versitygw \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="VGW_REGION")].value}')"
if [ -z "$S3_REGION" ]; then
  echo "FAIL: could not read VGW_REGION off deployment/versitygw" >&2
  exit 1
fi

PLAN="$("${HERE}/plan.sh")"
BUCKET_ONE="$(echo "$PLAN" | awk -F'\t' '$1 == "bucket" { print $2 }' | sed -n 1p)"
BUCKET_TWO="$(echo "$PLAN" | awk -F'\t' '$1 == "bucket" { print $2 }' | sed -n 2p)"
OWNER_ONE="$(echo "$PLAN" | awk -F'\t' -v b="$BUCKET_ONE" '$1 == "bucket" && $2 == b { print $3 }')"
if [ -z "$BUCKET_ONE" ] || [ -z "$BUCKET_TWO" ] || [ -z "$OWNER_ONE" ]; then
  echo "FAIL: the provisioning document does not declare two buckets with owners, which is" >&2
  echo "      what the isolation checks below need in order to mean anything" >&2
  exit 1
fi
export S3_REGION BUCKET_ONE BUCKET_TWO
echo "ok: gateway configured with region=${S3_REGION}, buckets=${BUCKET_ONE},${BUCKET_TWO}" >&2

secret_value() { kubectl get secret -n "$NAMESPACE" versitygw-credentials -o "jsonpath={.data.$1}" | base64 -d; }
CLIENT1_ACCESS="$OWNER_ONE"
CLIENT1_SECRET="$(echo "$PLAN" | awk -F'\t' -v a="$OWNER_ONE" '$1 == "account" && $2 == a { print $3 }')"
ROOT_ACCESS="$(secret_value rootAccessKeyId)"
ROOT_SECRET="$(secret_value rootSecretAccessKey)"
export CLIENT1_ACCESS CLIENT1_SECRET ROOT_ACCESS ROOT_SECRET

wait_for_forward() {
  local log="$1" pid="$2"
  shift 2
  local deadline
  deadline=$(( $(date +%s) + 30 ))
  while :; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "FAIL: kubectl port-forward exited instead of binding. Its output was:" >&2
      cat "$log" >&2
      echo "      A local port is most likely already in use by another process." >&2
      exit 1
    fi
    local ok=1
    for port in "$@"; do
      grep -qE "^Forwarding from .+:${port} ->" "$log" || ok=0
    done
    [ "$ok" -eq 1 ] && return 0
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "FAIL: kubectl port-forward did not report forwarding on $* within 30s:" >&2
      cat "$log" >&2
      exit 1
    fi
    sleep 1
  done
}

forward_host() {
  local host
  host="$(sed -n "s/^Forwarding from \(.*\):${2} -> .*/\1/p" "$1" | head -1)"
  if [ -z "$host" ]; then
    echo "FAIL: could not read the bound address for port ${2} out of ${1}" >&2
    exit 1
  fi
  echo "$host"
}

PF_LOG=/tmp/versitygw-port-forward.log
: >"$PF_LOG"
kubectl port-forward -n "$NAMESPACE" svc/versitygw "${S3_LOCAL_PORT}:7070" "${ADMIN_LOCAL_PORT}:7071" \
  >"$PF_LOG" 2>&1 &
PF_PID=$!
trap "kill ${PF_PID} >/dev/null 2>&1 || true" EXIT
wait_for_forward "$PF_LOG" "$PF_PID" "$S3_LOCAL_PORT" "$ADMIN_LOCAL_PORT"
FORWARD_HOST="$(forward_host "$PF_LOG" "$S3_LOCAL_PORT")"
export FORWARD_HOST

python3 "${HERE}/python/admin-listener-check.py"

export S3_ENDPOINT="http://${FORWARD_HOST}:${S3_LOCAL_PORT}"
python3 "${HERE}/python/s3-probe.py"

MPF_LOG=/tmp/versitygw-metrics-port-forward.log
: >"$MPF_LOG"
kubectl port-forward -n "$NAMESPACE" svc/versitygw-metrics "${METRICS_LOCAL_PORT}:9102" \
  >"$MPF_LOG" 2>&1 &
MPF_PID=$!
trap "kill ${PF_PID} ${MPF_PID} >/dev/null 2>&1 || true" EXIT
wait_for_forward "$MPF_LOG" "$MPF_PID" "$METRICS_LOCAL_PORT"
METRICS_HOST="$(forward_host "$MPF_LOG" "$METRICS_LOCAL_PORT")"

deadline=$(( $(date +%s) + 60 ))
while :; do
  metrics="$(curl -sS --max-time "${CURL_MAX_TIME}" "http://${METRICS_HOST}:${METRICS_LOCAL_PORT}/metrics" || true)"
  if echo "$metrics" | grep -qE '^versitygw_success_count\{.*action="PutObject".*\} [1-9]'; then
    echo "ok: the gateway's PutObject success counter reached the exporter and is non-zero" >&2
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL: no non-zero versitygw_success_count{action=\"PutObject\"} series at the exporter after driving a real PUT" >&2
    echo "$metrics" | grep -i versitygw >&2 || echo "(no versitygw series at all)" >&2
    exit 1
  fi
  sleep 3
done

if echo "$metrics" | grep -qE '^versitygw_failed_count\{.*status="403".*\} [1-9]'; then
  echo "ok: the 403s from the isolation checks are visible as failed_count at the exporter" >&2
else
  echo "FAIL: no non-zero versitygw_failed_count{status=\"403\"} series despite three real 403 responses" >&2
  echo "$metrics" | grep -i versitygw_failed >&2 || echo "(no failed_count series at all)" >&2
  exit 1
fi
