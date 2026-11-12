#!/bin/bash
# S3 canary. PUTs a 1 MiB random object under health-canary/ in the canary bucket, GETs it back
# and compares its SHA-256, LISTs the prefix and requires the object, DELETEs it, then LISTs
# again and requires it gone. Each step is one of the operations backup clients depend on, so a
# key without delete rights, a bucket that does not exist or a policy that hides listings fails
# here rather than in the next backup.
#
# The object name is the pod name, so concurrent or leftover runs never collide. A run that
# fails after its PUT still tries to delete its object on exit.
#
# Runs on the health-canary image: s5cmd and bash, with head and sha256sum from Alpine.
set -euo pipefail

if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  echo "FAIL: AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY is not set; Secret ${S3_CANARY_SECRET} is missing or incomplete"
  exit 1
fi

endpoint="${S3_CANARY_ENDPOINT}"
prefix="s3://${S3_CANARY_BUCKET}/health-canary/"
object="${prefix}${POD_NAME}"
s5() { s5cmd --endpoint-url "${endpoint}" --retry-count 2 "$@"; }

put_done=0
deleted=0
cleanup() {
  if [[ "${put_done}" == 1 && "${deleted}" == 0 ]]; then
    s5 rm "${object}" >/dev/null 2>&1 || echo "WARN: could not remove ${object} after a failed run"
  fi
  rm -f /tmp/object
}
trap cleanup EXIT

head -c 1048576 /dev/urandom > /tmp/object
expected="$(sha256sum /tmp/object | cut -d' ' -f1)"

if ! s5 cp /tmp/object "${object}" >/dev/null; then
  echo "FAIL: PUT ${object} on ${endpoint}"
  exit 1
fi
put_done=1

if ! actual="$(s5 cat "${object}" | sha256sum | cut -d' ' -f1)"; then
  echo "FAIL: GET ${object} on ${endpoint}"
  exit 1
fi
if [[ "${actual}" != "${expected}" ]]; then
  echo "FAIL: GET ${object} returned checksum ${actual}, PUT ${expected}"
  exit 1
fi

if ! listing="$(s5 ls "${prefix}")"; then
  echo "FAIL: LIST ${prefix} on ${endpoint}"
  exit 1
fi
if ! grep -qF "${POD_NAME}" <<<"${listing}"; then
  echo "FAIL: LIST ${prefix} does not show ${POD_NAME}"
  exit 1
fi

if ! s5 rm "${object}" >/dev/null; then
  echo "FAIL: DELETE ${object} on ${endpoint}"
  exit 1
fi
deleted=1

# s5cmd exits non-zero when a listing matches nothing, so an empty prefix is the normal case.
if s5 ls "${prefix}" 2>/dev/null | grep -qF "${POD_NAME}"; then
  echo "FAIL: ${object} is still listed after DELETE"
  exit 1
fi

echo "ok: PUT, GET (checksum match), LIST and DELETE of ${object} on ${endpoint}"
