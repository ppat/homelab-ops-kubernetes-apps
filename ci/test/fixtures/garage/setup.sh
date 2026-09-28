#!/bin/bash
set -euo pipefail

: "${GARAGE_SECRET_STORE:?GARAGE_SECRET_STORE is required}"
: "${GARAGE_ACCESS_KEY_STORE_KEY:?GARAGE_ACCESS_KEY_STORE_KEY is required}"
: "${GARAGE_SECRET_KEY_STORE_KEY:?GARAGE_SECRET_KEY_STORE_KEY is required}"
: "${GARAGE_BUCKETS:?GARAGE_BUCKETS is required}"

read -r -a buckets <<<"$GARAGE_BUCKETS"

NAMESPACE="garage"
ADMIN_LOCAL_PORT=13903
CURL_MAX_TIME=15

scratch_dir="$(mktemp -d)"
pf_pid=""
cleanup() {
  if [ -n "$pf_pid" ]; then
    kill "$pf_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$scratch_dir"
}
trap cleanup EXIT

admin_token="$(kubectl get secret -n "$NAMESPACE" garage-credentials \
  -o jsonpath='{.data.admin-token}' | base64 -d)"

kubectl port-forward -n "$NAMESPACE" svc/garage "${ADMIN_LOCAL_PORT}:3903" \
  >"${scratch_dir}/port-forward.log" 2>&1 &
pf_pid=$!

admin_base="http://127.0.0.1:${ADMIN_LOCAL_PORT}"
auth_curl() {
  curl -fsS --max-time "$CURL_MAX_TIME" \
    -H "Authorization: Bearer ${admin_token}" "$@"
}

ready=0
for _ in $(seq 1 30); do
  if auth_curl "${admin_base}/v2/GetClusterStatus" >/dev/null 2>"${scratch_dir}/status.err"; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  echo "FAIL: Garage admin API did not become reachable through the port-forward" >&2
  cat "${scratch_dir}/port-forward.log" "${scratch_dir}/status.err" >&2
  exit 1
fi

key_name="chainsaw-${buckets[0]}"
key_request="$(jq -cn --arg name "$key_name" '{name: $name}')"
key_response="$(auth_curl -X POST "${admin_base}/v2/CreateKey" \
  -H "Content-Type: application/json" -d "$key_request")"
access_key="$(jq -er '.accessKeyId' <<<"$key_response")"
secret_key="$(jq -er '.secretAccessKey' <<<"$key_response")"

for bucket in "${buckets[@]}"; do
  bucket_request="$(jq -cn --arg alias "$bucket" '{globalAlias: $alias}')"
  bucket_response="$(auth_curl -X POST "${admin_base}/v2/CreateBucket" \
    -H "Content-Type: application/json" -d "$bucket_request")"
  bucket_id="$(jq -er '.id' <<<"$bucket_response")"
  permission_request="$(jq -cn --arg bucket "$bucket_id" --arg key "$access_key" \
    '{bucketId: $bucket, accessKeyId: $key, permissions: {read: true, write: true}}')"
  auth_curl -X POST "${admin_base}/v2/AllowBucketKey" \
    -H "Content-Type: application/json" -d "$permission_request" >/dev/null
  echo "ok: granted ${key_name} read/write access to bucket/${bucket}" >&2
done

patch_store_value() {
  local store_key="$1"
  local value="$2"
  local index patch

  index="$(kubectl get clustersecretstore "$GARAGE_SECRET_STORE" -o json | \
    jq -er --arg key "$store_key" '.spec.provider.fake.data | map(.key == $key) | index(true)')"
  patch="$(jq -cn --arg index "$index" --arg value "$value" \
    '[{op: "replace", path: ("/spec/provider/fake/data/" + $index + "/value"), value: $value}]')"
  kubectl patch clustersecretstore "$GARAGE_SECRET_STORE" --type=json -p "$patch" >/dev/null
}

patch_store_value "$GARAGE_ACCESS_KEY_STORE_KEY" "$access_key"
patch_store_value "$GARAGE_SECRET_KEY_STORE_KEY" "$secret_key"
echo "ok: injected Garage credentials into clustersecretstore/${GARAGE_SECRET_STORE}" >&2
