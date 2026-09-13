#!/bin/bash
set -euo pipefail

# Proves Garage's S3 API and website endpoint actually work, not merely that
# its Deployment reported Available (which, since readinessProbe is httpGet
# /health -- see deployment.yaml -- already implies the --single-node flag
# committed a layout, or Garage would never have started at all) -- see
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
#      assertion in this suite and only this one would catch it, and
#   3. enables website access on the same bucket, uploads an index.html, and
#      reads it back through Garage's own web port (3902) with an explicit
#      Host header -- the same <bucket>.garage-web.${domain_name} suffix
#      match ingress-web.yaml's wildcard rule exists to route in production
#      (see conf.d/garage.toml's [s3_web] comment for the two-mechanism
#      Host-to-bucket resolution this proves the first of), plus a
#      falsification pair: a missing *key* on the same (real) bucket must
#      come back as the S3 API's typed NoSuchKey error (body contains
#      "NoSuchKey", response carries an access-control-allow-origin header),
#      while a missing *bucket* must come back as Garage's generic bare 404
#      with neither -- confirmed against a live instance. Without that
#      distinction, a bucket that never resolved and a resolved bucket
#      missing one file would look identical, which would silently pass a
#      naive "is it 404" check even if the suffix match were broken.
#
# This suite installs no ingress controller (that's networking-core's job),
# so the web check below goes straight to svc/garage's own web port through
# a port-forward with an explicit Host header -- it proves Garage's own
# Host-to-bucket resolution, not Traefik's wildcard routing, DNS, or the
# certificate-web.yaml Certificate in front of it in production.
#
# boto3 (not the aws CLI) drives the S3 calls so the wrong-key case can read
# the literal HTTP status code off ClientError.response['ResponseMetadata']
# instead of pattern-matching CLI error text, and so this script's behavior
# doesn't depend on which major version of the aws CLI happens to be
# preinstalled on the runner.

NAMESPACE="garage"
ADMIN_LOCAL_PORT=13903
S3_LOCAL_PORT=13900
WEB_LOCAL_PORT=13902
DEADLINE=300
# Every curl below is bounded by this. Without a per-request cap the readiness poll's DEADLINE
# is unenforceable: that loop only re-checks the clock *between* attempts, so a request that
# hangs inside curl never returns control to it and the chainsaw step's own `timeout` does the
# killing instead -- reporting "the assertion ran out of budget" for what was actually "the
# admin API never answered". See issue #3724.
#
# 15s, deliberately not the larger cap an object round-trip would suggest: none of the curls
# here carries object data. They are small Admin API JSON calls and a 45-byte index.html read
# back over a local port-forward, all sub-second when healthy -- the S3 put/get is boto3
# further down and is bounded by botocore's own timeouts, not by this. At 5% of the step's 5m
# (../../infra-storage/validate-garage.yaml) apiece, even several consecutive hung admin calls
# still leave the round-trip and website phases their share of the budget.
CURL_MAX_TIME=15

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
GARAGE_TOML="$(kubectl get configmap -n "$NAMESPACE" "$GARAGE_CONFIGMAP" -o jsonpath='{.data.garage\.toml}')"
S3_REGION="$(echo "$GARAGE_TOML" | sed -n 's/^s3_region = "\(.*\)"$/\1/p')"
if [ -z "$S3_REGION" ]; then
  echo "FAIL: could not read s3_region out of configmap/${GARAGE_CONFIGMAP} in ${NAMESPACE}" >&2
  exit 1
fi
echo "ok: garage is configured with s3_region=${S3_REGION}" >&2

# Same reasoning as s3_region above: this is [s3_web]'s root_domain, a
# postBuild variable (domain_name), not a value this script can know ahead
# of time -- read the live value rather than hardcoding CI's own
# cluster.example.com, so this keeps working unchanged if that ever changes.
ROOT_DOMAIN="$(echo "$GARAGE_TOML" | sed -n 's/^root_domain = "\(.*\)"$/\1/p')"
if [ -z "$ROOT_DOMAIN" ]; then
  echo "FAIL: could not read root_domain out of configmap/${GARAGE_CONFIGMAP} in ${NAMESPACE}" >&2
  exit 1
fi
echo "ok: garage's [s3_web] is configured with root_domain=${ROOT_DOMAIN}" >&2

kubectl port-forward -n "$NAMESPACE" svc/garage "${ADMIN_LOCAL_PORT}:3903" "${S3_LOCAL_PORT}:3900" "${WEB_LOCAL_PORT}:3902" \
  >/tmp/garage-port-forward.log 2>&1 &
PF_PID=$!
# shellcheck disable=SC2064  # PF_PID must be expanded now, not when the trap fires.
trap "kill ${PF_PID} >/dev/null 2>&1 || true" EXIT

ADMIN_BASE="http://127.0.0.1:${ADMIN_LOCAL_PORT}"
S3_ENDPOINT="http://127.0.0.1:${S3_LOCAL_PORT}"
WEB_ENDPOINT="http://127.0.0.1:${WEB_LOCAL_PORT}"

auth_curl() {
  curl -fsS --max-time "${CURL_MAX_TIME}" -H "Authorization: Bearer ${ADMIN_TOKEN}" "$@"
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

# id is a query parameter on this endpoint, unlike CreateBucket/AllowBucketKey
# above which take it in the JSON body -- confirmed against the v2 OpenAPI
# spec (garagehq.deuxfleurs.fr/api/garage-admin-v2.json).
auth_curl -X POST "${ADMIN_BASE}/v2/UpdateBucket?id=${BUCKET_ID}" \
  -H "Content-Type: application/json" \
  -d '{"websiteAccess":{"enabled":true,"indexDocument":"index.html"}}' \
  >/dev/null

echo "ok: enabled website access on bucket ${BUCKET_ID} (indexDocument=index.html)" >&2

WEB_INDEX_BODY="hello from chainsaw's garage web endpoint test"

S3_ENDPOINT="$S3_ENDPOINT" ACCESS_KEY="$ACCESS_KEY" SECRET_KEY="$SECRET_KEY" S3_REGION="$S3_REGION" WEB_INDEX_BODY="$WEB_INDEX_BODY" python3 <<'PYEOF'
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

# Uploaded via the same authenticated S3 client as the round-trip object
# above; read back over plain, unauthenticated HTTP through Garage's website
# endpoint further down this script -- proving the two Garage modules ([s3_api]
# and [s3_web]) agree on the same bucket's contents, not just that each
# independently answers something.
web_index_body = os.environ["WEB_INDEX_BODY"].encode()
client.put_object(Bucket=bucket, Key="index.html", Body=web_index_body, ContentType="text/html")
print("ok: uploaded index.html for the website endpoint check", file=sys.stderr)

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

# --- Website endpoint: Host-header suffix match, proven by write-then-read ---
#
# Plain, unauthenticated HTTP straight to svc/garage's web port with an
# explicit Host header -- there is no ingress controller in this suite (see
# the header comment), so this is Garage's own [s3_web] resolution, not
# Traefik's.

WEB_HOST="chainsaw-test-bucket.${ROOT_DOMAIN}"
MISSING_BUCKET_HOST="chainsaw-test-bucket-does-not-exist.${ROOT_DOMAIN}"

echo "reading index.html back through the website endpoint (Host=${WEB_HOST}) ..." >&2
web_body_file="$(mktemp)"
web_status="$(curl -sS --max-time "${CURL_MAX_TIME}" -o "$web_body_file" -w '%{http_code}' \
  -H "Host: ${WEB_HOST}" "${WEB_ENDPOINT}/index.html")"
if [ "$web_status" != "200" ]; then
  echo "FAIL: website endpoint returned HTTP ${web_status} for Host=${WEB_HOST} /index.html, expected 200" >&2
  cat "$web_body_file" >&2
  exit 1
fi
web_body="$(cat "$web_body_file")"
if [ "$web_body" != "$WEB_INDEX_BODY" ]; then
  printf 'FAIL: website endpoint content mismatch for Host=%s: got %q, want %q\n' \
    "$WEB_HOST" "$web_body" "$WEB_INDEX_BODY" >&2
  exit 1
fi
echo "ok: website endpoint served index.html's actual content for Host=${WEB_HOST}" >&2
rm -f "$web_body_file"

# Falsification pair: a missing key on a bucket that DID resolve must look
# different from a bucket that never resolved at all, or the suffix match
# could be broken (e.g. always routing to the same bucket, or not resolving
# per-Host at all) without any check here noticing. Distinguishing signal
# (both confirmed against a live instance): a resolved, website-enabled
# bucket's own S3 API renders a typed NoSuchKey error, with an
# access-control-allow-origin response header; a bucket that never resolved
# renders Garage's generic bare "404 Not Found" with neither.
check_web_404() {
  local host="$1" path="$2" want_typed="$3" label="$4"
  local headers body status has_marker=0
  headers="$(mktemp)"
  body="$(mktemp)"
  status="$(curl -sS --max-time "${CURL_MAX_TIME}" -o "$body" -D "$headers" -w '%{http_code}' \
    -H "Host: ${host}" "${WEB_ENDPOINT}${path}")"
  if [ "$status" != "404" ]; then
    echo "FAIL: ${label}: expected HTTP 404 for Host=${host} ${path}, got ${status}" >&2
    cat "$headers" "$body" >&2
    exit 1
  fi
  if grep -qi 'NoSuchKey' "$body" && grep -qi '^access-control-allow-origin:' "$headers"; then
    has_marker=1
  fi
  if [ "$want_typed" = "yes" ] && [ "$has_marker" -ne 1 ]; then
    echo "FAIL: ${label}: expected the typed S3 NoSuchKey 404 (with access-control-allow-origin) for Host=${host}, got a generic 404 instead" >&2
    cat "$headers" "$body" >&2
    exit 1
  fi
  if [ "$want_typed" = "no" ] && [ "$has_marker" -eq 1 ]; then
    echo "FAIL: ${label}: expected a generic bare 404 for Host=${host}, but got the typed NoSuchKey response -- a bucket that should not exist resolved anyway" >&2
    cat "$headers" "$body" >&2
    exit 1
  fi
  if [ "$want_typed" = "yes" ]; then
    echo "ok: ${label}: Host=${host} correctly returned the typed NoSuchKey 404" >&2
  else
    echo "ok: ${label}: Host=${host} correctly returned a generic bare 404" >&2
  fi
  rm -f "$headers" "$body"
}

check_web_404 "$WEB_HOST" "/this-key-does-not-exist.html" yes "existing bucket, missing key"
check_web_404 "$MISSING_BUCKET_HOST" "/index.html" no "bucket that was never created"
