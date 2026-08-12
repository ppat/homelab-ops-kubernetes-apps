#!/bin/bash
set -euo pipefail

# Proves the object-store fixture (../fixtures/object-store) actually enforces
# credentials, not just that it answers requests.
#
# Every other assertion that touches the fixture proves the CORRECT key works (Loki
# successfully writes chunks, barman-cloud successfully archives WAL) - none of them
# prove a WRONG key is rejected. A fake that accepts any key would pass all of those
# checks and prove nothing about credential wiring, which is exactly the gap the two old
# per-suite minio/ fixtures left open.
#
# Reachability is via `kubectl port-forward` and the `aws` CLI pre-installed on the
# GitHub-hosted ubuntu-24.04 runner, matching ../scripts/loki-query.sh's choice of the
# runner's own tools over a pod, an image to pin, and a second thing that can fail to
# schedule.

NAMESPACE=""
SERVICE="object-store"
SERVICE_PORT=9000
LOCAL_PORT=19000
BUCKET=""
REGION="us-east-1"

for param in "$@"
do
  case $param in
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
    --bucket=*)
      BUCKET="${param#*=}"
      shift
      ;;
    --region=*)
      REGION="${param#*=}"
      shift
      ;;
    *)
      echo "Unknown parameter: $param" >&2
      exit 1
      ;;
  esac
done

if [ -z "$NAMESPACE" ] || [ -z "$BUCKET" ]; then
  echo "--namespace=<ns> and --bucket=<bucket> are required" >&2
  exit 1
fi

kubectl port-forward -n "$NAMESPACE" "svc/${SERVICE}" "${LOCAL_PORT}:${SERVICE_PORT}" \
  >"/tmp/object-store-wrong-key-port-forward.log" 2>&1 &
PF_PID=$!
# shellcheck disable=SC2064  # PF_PID must be expanded now, not when the trap fires.
trap "kill ${PF_PID} >/dev/null 2>&1 || true" EXIT

# A bare TCP probe, not `curl -f`: Garage answers an unauthenticated GET with a 4xx S3
# error body, which curl -f treats as failure even though it proves the port is up.
ready=0
for _ in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null; then
    exec 3<&- 3>&- 2>/dev/null || true
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "FAIL: object store (svc/${SERVICE} in ${NAMESPACE}) never answered through the port-forward" >&2
  cat "/tmp/object-store-wrong-key-port-forward.log" >&2 || true
  exit 1
fi

echo "probing s3://${BUCKET} with a deliberately wrong access key..." >&2
set +e
output="$(AWS_ACCESS_KEY_ID="wrong-key-this-must-be-rejected" \
  AWS_SECRET_ACCESS_KEY="wrong-secret-this-must-be-rejected" \
  aws --endpoint-url "http://127.0.0.1:${LOCAL_PORT}" --region "${REGION}" \
  s3api put-object --bucket "${BUCKET}" --key chainsaw-wrong-key-probe --body /dev/null 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: a request signed with a WRONG access key succeeded - credentials are not being enforced" >&2
  echo "$output" >&2
  exit 1
fi

if ! echo "$output" | grep -q "AccessDenied"; then
  echo "FAIL: the wrong-key request failed, but not with AccessDenied - this proves nothing about credential wiring" >&2
  echo "$output" >&2
  exit 1
fi

echo "ok: wrong access key was rejected with AccessDenied" >&2
