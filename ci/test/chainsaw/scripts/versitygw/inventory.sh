#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="versitygw"
INVENTORY_DEPLOY="deployment/versitygw-inventory"
S3_LOCAL_PORT=17170
ADDED_OBJECTS=5

# Over loopback from inside the pod, not through a port-forward: the forced walks
# below restart the pod, and a port-forward outlives its target as a connection
# to nothing.
scrape() {
  kubectl exec -n "$NAMESPACE" "$INVENTORY_DEPLOY" -c inventory -- python3 -c \
    'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:9103/metrics", timeout=10).read().decode(), end="")'
}

sample() {
  awk -v name="$1" '$1 == name { print $2 }'
}

bucket_sample() {
  awk -v want="$1{bucket=\"$2\"}" '$1 == want { print $2 }'
}

force_walk() {
  kubectl rollout restart -n "$NAMESPACE" "$INVENTORY_DEPLOY" >/dev/null
  kubectl rollout status -n "$NAMESPACE" "$INVENTORY_DEPLOY" --timeout=180s >/dev/null
  # Ready is not walked: the readiness probe answers before the first walk
  # returns, so rollout status would pass before there is anything to read.
  local waited=0
  while [ "$waited" -lt 180 ]; do
    if scrape 2>/dev/null | grep -q '^versitygw_store_buckets '; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "FAIL: no walk completed within 180s of the exporter restarting" >&2
  scrape >&2 || true
  exit 1
}

python3 -m pip install --quiet --user boto3

S3_REGION="$(kubectl get deployment -n "$NAMESPACE" versitygw \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="VGW_REGION")].value}')"
PLAN="$("${HERE}/plan.sh")"
BUCKET_ONE="$(echo "$PLAN" | awk -F'\t' '$1 == "bucket" { print $2 }' | sed -n 1p)"
BUCKET_TWO="$(echo "$PLAN" | awk -F'\t' '$1 == "bucket" { print $2 }' | sed -n 2p)"
if [ -z "$S3_REGION" ] || [ -z "$BUCKET_ONE" ] || [ -z "$BUCKET_TWO" ]; then
  echo "FAIL: could not read region and bucket names off live state" >&2
  exit 1
fi

secret_value() { kubectl get secret -n "$NAMESPACE" versitygw-credentials -o "jsonpath={.data.$1}" | base64 -d; }
ROOT_ACCESS="$(secret_value rootAccessKeyId)"
ROOT_SECRET="$(secret_value rootSecretAccessKey)"

kubectl port-forward -n "$NAMESPACE" svc/versitygw "${S3_LOCAL_PORT}:7070" \
  >/tmp/versitygw-inventory-port-forward.log 2>&1 &
PF_PID=$!
trap "kill ${PF_PID} >/dev/null 2>&1 || true" EXIT
sleep 3

export AWS_ACCESS_KEY_ID="$ROOT_ACCESS"
export AWS_SECRET_ACCESS_KEY="$ROOT_SECRET"
export AWS_DEFAULT_REGION="$S3_REGION"
export S3_ENDPOINT="http://127.0.0.1:${S3_LOCAL_PORT}"
export BUCKET_ONE BUCKET_TWO ADDED_OBJECTS

s3_count() {
  BUCKET="$1" python3 - <<'PY'
import os
import boto3
s3 = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT"])
total = 0
token = None
while True:
    kwargs = {"Bucket": os.environ["BUCKET"], "MaxKeys": 1000}
    if token:
        kwargs["ContinuationToken"] = token
    page = s3.list_objects_v2(**kwargs)
    total += len(page.get("Contents", []))
    token = page.get("NextContinuationToken")
    if not page.get("IsTruncated"):
        break
print(total)
PY
}


force_walk
METRICS="$(scrape)"

BUCKETS="$(printf '%s\n' "$METRICS" | sample versitygw_store_buckets)"
if [ "$BUCKETS" != "2" ]; then
  echo "FAIL: expected 2 buckets, exporter reports '${BUCKETS}'." >&2
  echo "      3 would mean the walk root is the PVC root and the IAM store is being counted." >&2
  exit 1
fi
echo "ok: exporter sees ${BUCKETS} buckets and not the IAM store beside them" >&2

# The sweep step ran immediately before this one and its fixture deliberately
# leaves exactly one in-flight overwrite-race file -- <BUCKET_ONE>/wal/
# .0000...0010.sgwtmp.1900000000000000000 -- as the negative control proving the
# sweep spares fresh residue. That file is the third form the sweep reclaims and
# the one that lives OUTSIDE .sgwtmp, so it is what this assertion is for: with
# the exporter blind to it the count reads 0 here and the bytes are attributed to
# nothing. Held at exactly 1 rather than >= 1 so an exporter that started
# matching ordinary objects fails too.
for SPEC in "${BUCKET_ONE}:1" "${BUCKET_TWO}:0"; do
  BUCKET="${SPEC%:*}"
  WANT="${SPEC##*:}"
  GOT="$(printf '%s\n' "$METRICS" | bucket_sample versitygw_store_overwrite_residue_objects "$BUCKET")"
  if [ "$GOT" != "$WANT" ]; then
    echo "FAIL: bucket ${BUCKET}: expected ${WANT} overwrite-race residue file(s), exporter reports '${GOT}'." >&2
    echo "      The sweep fixture leaves exactly one in ${BUCKET_ONE} and none in ${BUCKET_TWO};" >&2
    echo "      an empty value means the series is absent, i.e. the exporter no longer classifies" >&2
    echo "      the form sweep.sh matches at its 'overwrites' find." >&2
    exit 1
  fi
done
echo "ok: overwrite-race residue counted where the sweep fixture left it, and nowhere else" >&2

for BUCKET in "$BUCKET_ONE" "$BUCKET_TWO"; do
  EXPORTED="$(printf '%s\n' "$METRICS" | bucket_sample versitygw_store_objects "$BUCKET")"
  LISTED="$(s3_count "$BUCKET")"
  if [ -z "$EXPORTED" ]; then
    echo "FAIL: no versitygw_store_objects series for bucket ${BUCKET}" >&2
    exit 1
  fi
  if [ "$EXPORTED" != "$LISTED" ]; then
    echo "FAIL: bucket ${BUCKET}: exporter says ${EXPORTED} objects, ListObjectsV2 says ${LISTED}" >&2
    exit 1
  fi
  echo "ok: bucket ${BUCKET}: exporter and ListObjectsV2 agree at ${EXPORTED} objects" >&2
done

BASELINE="$(printf '%s\n' "$METRICS" | bucket_sample versitygw_store_objects "$BUCKET_ONE")"


python3 - <<'PY'
import os
import boto3
s3 = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT"])
for i in range(int(os.environ["ADDED_OBJECTS"])):
    s3.put_object(
        Bucket=os.environ["BUCKET_ONE"],
        Key="inventory-probe/%d" % i,
        Body=b"x" * 128,
    )
print("uploaded", os.environ["ADDED_OBJECTS"], "objects")
PY

UNWALKED="$(scrape | bucket_sample versitygw_store_objects "$BUCKET_ONE")"
if [ "$UNWALKED" != "$BASELINE" ]; then
  echo "FAIL: the count changed from ${BASELINE} to ${UNWALKED} without a walk." >&2
  echo "      The gauge is meant to be the last walk's result and nothing else." >&2
  exit 1
fi
echo "ok: count still ${UNWALKED} before a walk -- the gauge is the walk's output" >&2

force_walk
WALKED="$(scrape | bucket_sample versitygw_store_objects "$BUCKET_ONE")"
EXPECTED=$((BASELINE + ADDED_OBJECTS))
if [ "$WALKED" != "$EXPECTED" ]; then
  echo "FAIL: after adding ${ADDED_OBJECTS} objects the count is ${WALKED}, expected ${EXPECTED}" >&2
  exit 1
fi
echo "ok: count moved ${BASELINE} -> ${WALKED} for ${ADDED_OBJECTS} added objects" >&2

python3 - <<'PY'
import os
import boto3
s3 = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT"])
for i in range(int(os.environ["ADDED_OBJECTS"])):
    s3.delete_object(Bucket=os.environ["BUCKET_ONE"], Key="inventory-probe/%d" % i)
print("removed the probe objects")
PY

echo "ok: the store's contents are exported, agree with the S3 API, and track it" >&2
