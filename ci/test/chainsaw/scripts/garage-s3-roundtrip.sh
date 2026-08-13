#!/bin/bash
set -euo pipefail

# Proves Garage's S3 API actually works, not merely that its Deployment
# reported Available (which, since readinessProbe is httpGet /health -- see
# deployment.yaml -- already implies the --single-node flag committed a
# layout, or Garage would never have started at all) -- see
# ci/test/infra-storage/validate-garage.yaml for why that alone is still
# checked separately first and is not enough on its own.
#
# This creates its own throwaway key + bucket via the Admin API (the exact
# imperative step this module deliberately does not automate -- bucket/key
# provisioning is Terraform's job, see the module README) purely to prove the
# wiring, then:
#   1. puts and gets an object back through the S3 API with that key and
#      diffs the bytes, and
#   2. repeats the get with a wrong secret key and asserts the response is
#      HTTP 403 -- a fake that accepts any key would pass every other
#      assertion in this suite and only this one would catch it.
#
# boto3 (not the aws CLI) drives the S3 calls so the wrong-key case can read
# the literal HTTP status code off ClientError.response['ResponseMetadata']
# instead of pattern-matching CLI error text, and so this script's behavior
# doesn't depend on which major version of the aws CLI happens to be
# preinstalled on the runner.

NAMESPACE="garage"
ADMIN_LOCAL_PORT=13903
S3_LOCAL_PORT=13900
DEADLINE=300

python3 -m pip install --quiet --user boto3

ADMIN_TOKEN="$(kubectl get secret -n "$NAMESPACE" garage-credentials -o jsonpath='{.data.admin-token}' | base64 -d)"

# Derived from the live ConfigMap, not hardcoded: this has to be the exact
# value Garage is configured with (conf.d/garage.toml's s3_region, a
# postBuild variable set per-cluster -- see that file's comment for why), not
# a second guess this script would otherwise have to keep in sync by hand.
# This matters beyond convenience: botocore's S3RegionRedirectorv2
# (redirect_from_error, in botocore/utils.py) treats an
# AuthorizationHeaderMalformed response that includes a Region field as a
# recoverable wrong-region error and silently retries with the corrected
# region -- confirmed against botocore's own source. A hardcoded *wrong*
# region here could therefore still "pass" by being transparently corrected
# client-side, which would leave this script unable to catch a real region
# misconfiguration at all. Deriving the live value sidesteps that path
# entirely rather than relying on it not triggering.
#
# The ConfigMap name is read off the Deployment's own volume spec, not
# guessed as "garage-config": kustomization.yaml's configMapGenerator
# appends a content-hash suffix to the name it actually creates (e.g.
# garage-config-<hash>), which Kustomize's own name-reference rewriting
# resolves for deployment.yaml automatically at build time -- but nothing
# does that rewriting for a script reaching in from outside the kustomize
# graph, so asking the Deployment what it actually mounted is the only way
# to get the real name right after every regeneration.
GARAGE_CONFIGMAP="$(kubectl get deployment -n "$NAMESPACE" garage -o jsonpath='{.spec.template.spec.volumes[?(@.name=="config")].configMap.name}')"
S3_REGION="$(kubectl get configmap -n "$NAMESPACE" "$GARAGE_CONFIGMAP" -o jsonpath='{.data.garage\.toml}' | sed -n 's/^s3_region = "\(.*\)"$/\1/p')"
if [ -z "$S3_REGION" ]; then
  echo "FAIL: could not read s3_region out of configmap/${GARAGE_CONFIGMAP} in ${NAMESPACE}" >&2
  exit 1
fi
echo "ok: garage is configured with s3_region=${S3_REGION}" >&2

kubectl port-forward -n "$NAMESPACE" svc/garage "${ADMIN_LOCAL_PORT}:3903" "${S3_LOCAL_PORT}:3900" \
  >/tmp/garage-port-forward.log 2>&1 &
PF_PID=$!
# shellcheck disable=SC2064  # PF_PID must be expanded now, not when the trap fires.
trap "kill ${PF_PID} >/dev/null 2>&1 || true" EXIT

ADMIN_BASE="http://127.0.0.1:${ADMIN_LOCAL_PORT}"
S3_ENDPOINT="http://127.0.0.1:${S3_LOCAL_PORT}"

auth_curl() {
  curl -fsS -H "Authorization: Bearer ${ADMIN_TOKEN}" "$@"
}

echo "waiting for garage admin API through the port-forward ..." >&2
ready=0
deadline_at=$(( $(date +%s) + DEADLINE ))
while :; do
  if auth_curl "${ADMIN_BASE}/v2/GetClusterStatus" >/tmp/status.json 2>/tmp/status.err; then
    ready=1
    break
  fi
  if [ "$(date +%s)" -ge "$deadline_at" ]; then
    break
  fi
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  echo "FAIL: garage admin API (svc/garage in ${NAMESPACE}) never answered GetClusterStatus through the port-forward" >&2
  cat /tmp/garage-port-forward.log /tmp/status.err >&2
  exit 1
fi

# The consequence, not the appearance: Deployment Available already implies
# --single-node succeeded (Garage would otherwise have failed to start at
# all -- see deployment.yaml's args comment), but asserting the actual
# committed role via the Admin API -- not just trusting a Kubernetes status
# condition -- is what actually proves the S3 API can serve requests.
ROLE="$(jq -c '.nodes[0].role' /tmp/status.json)"
if [ "$ROLE" = "null" ]; then
  echo "FAIL: node has no role in the committed cluster layout -- the S3 API cannot be serving requests" >&2
  cat /tmp/status.json >&2
  exit 1
fi
echo "ok: node has a committed layout role: ${ROLE}" >&2

echo "creating throwaway test key + bucket via the admin API ..." >&2
KEY_RESPONSE="$(auth_curl -X POST "${ADMIN_BASE}/v2/CreateKey" \
  -H "Content-Type: application/json" -d '{"name":"chainsaw-test-key"}')"
ACCESS_KEY="$(echo "$KEY_RESPONSE" | jq -r '.accessKeyId')"
SECRET_KEY="$(echo "$KEY_RESPONSE" | jq -r '.secretAccessKey')"

BUCKET_RESPONSE="$(auth_curl -X POST "${ADMIN_BASE}/v2/CreateBucket" \
  -H "Content-Type: application/json" -d '{"globalAlias":"chainsaw-test-bucket"}')"
BUCKET_ID="$(echo "$BUCKET_RESPONSE" | jq -r '.id')"

auth_curl -X POST "${ADMIN_BASE}/v2/AllowBucketKey" \
  -H "Content-Type: application/json" \
  -d "{\"bucketId\":\"${BUCKET_ID}\",\"accessKeyId\":\"${ACCESS_KEY}\",\"permissions\":{\"read\":true,\"write\":true}}" \
  >/dev/null

echo "ok: created key ${ACCESS_KEY} with read/write on bucket ${BUCKET_ID}" >&2

S3_ENDPOINT="$S3_ENDPOINT" ACCESS_KEY="$ACCESS_KEY" SECRET_KEY="$SECRET_KEY" S3_REGION="$S3_REGION" python3 <<'PYEOF'
import os
import sys

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

endpoint = os.environ["S3_ENDPOINT"]
access_key = os.environ["ACCESS_KEY"]
secret_key = os.environ["SECRET_KEY"]
region = os.environ["S3_REGION"]
bucket = "chainsaw-test-bucket"
object_key = "roundtrip.txt"
body = b"hello from chainsaw"

client = boto3.client(
    "s3",
    endpoint_url=endpoint,
    aws_access_key_id=access_key,
    aws_secret_access_key=secret_key,
    region_name=region,
    config=Config(signature_version="s3v4"),
)

client.put_object(Bucket=bucket, Key=object_key, Body=body)
got = client.get_object(Bucket=bucket, Key=object_key)["Body"].read()
if got != body:
    print(f"FAIL: round-trip mismatch: put {body!r}, got {got!r}", file=sys.stderr)
    sys.exit(1)
print("ok: put/get round-trip matched", file=sys.stderr)

wrong_client = boto3.client(
    "s3",
    endpoint_url=endpoint,
    aws_access_key_id=access_key,
    aws_secret_access_key="wrongwrongwrongwrongwrongwrongwrongwrong",
    region_name=region,
    config=Config(signature_version="s3v4"),
)
try:
    wrong_client.get_object(Bucket=bucket, Key=object_key)
    print("FAIL: get-object with a wrong secret key succeeded -- credential wiring is not being enforced", file=sys.stderr)
    sys.exit(1)
except ClientError as e:
    status = e.response["ResponseMetadata"]["HTTPStatusCode"]
    if status != 403:
        print(f"FAIL: wrong secret key got HTTP {status}, expected 403 (error code {e.response['Error']['Code']})", file=sys.stderr)
        sys.exit(1)
    print(f"ok: wrong secret key correctly got HTTP 403 (error code {e.response['Error']['Code']})", file=sys.stderr)
PYEOF
