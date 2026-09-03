#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="versitygw"
WAL_DEPLOY="deployment/versitygw-wal-continuity"
S3_LOCAL_PORT=17171
PROBE_PREFIX="g5-wal-probe-db"
PROBE_SERVER="g5-wal-probe-v1"
PROBE_SEGMENTS=300
# The second phase's archive: a generation promoted onto timeline 2, which is
# the shape every `components/db-restore` rotation produces and which no
# timeline-1 fixture can exercise.
SWITCH_PREFIX="g5-wal-switch-db"
SWITCH_SERVER="g5-wal-switch-v2"
SWITCH_SEGMENTS=10

# From inside the pod: the forced passes restart it, and a port-forward that
# survives its target is a port-forward to nothing.
scrape() {
  kubectl exec -n "$NAMESPACE" "$WAL_DEPLOY" -c wal-continuity -- python3 -c \
    'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:9104/metrics", timeout=10).read().decode(), end="")'
}

# Matched on owned labels, not a reconstructed label string: a bucket rename or
# a label reorder would otherwise quietly match nothing. The optional second
# argument narrows to one prefix, which the timeline phase below needs.
probe_sample() {
  awk -v name="$1" -v prefix="prefix=\"${2:-$PROBE_PREFIX}\"" '
    index($1, name "{") == 1 && index($1, prefix) > 0 { print $2 }'
}

unlabelled_sample() {
  awk -v name="$1" '$1 == name { print $2 }'
}

force_pass() {
  kubectl rollout restart -n "$NAMESPACE" "$WAL_DEPLOY" >/dev/null
  kubectl rollout status -n "$NAMESPACE" "$WAL_DEPLOY" --timeout=180s >/dev/null
  local waited=0
  while [ "$waited" -lt 180 ]; do
    if scrape 2>/dev/null | grep -q '^versitygw_wal_archive_servers '; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "FAIL: no pass completed within 180s of the reader restarting" >&2
  scrape >&2 || true
  exit 1
}

expect() {
  local what="$1" got="$2" want="$3"
  if [ "$got" != "$want" ]; then
    echo "FAIL: ${what} is '${got}', expected '${want}'" >&2
    echo "--- full probe-archive series ---" >&2
    scrape | grep -e "${PROBE_PREFIX}" -e "${SWITCH_PREFIX}" >&2 || true
    exit 1
  fi
  echo "ok: ${what} = ${want}" >&2
}

python3 -m pip install --quiet --user boto3

S3_REGION="$(kubectl get deployment -n "$NAMESPACE" versitygw \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="VGW_REGION")].value}')"
# Off the provisioning plan the module's own suite reads, through the same
# parser -- the module ships no provisioning CronJob to interrogate: which
# accounts and buckets exist is a cluster fact, converged from outside.
BUCKET="$("${HERE}/../../chainsaw/scripts/versitygw/plan.sh" \
  | awk -F'\t' '$1 == "bucket" { print $2 }' | sed -n 1p)"
if [ -z "$S3_REGION" ] || [ -z "$BUCKET" ]; then
  echo "FAIL: could not read region and bucket name off live state" >&2
  exit 1
fi

secret_value() { kubectl get secret -n "$NAMESPACE" versitygw-credentials -o "jsonpath={.data.$1}" | base64 -d; }
ROOT_ACCESS="$(secret_value rootAccessKeyId)"
ROOT_SECRET="$(secret_value rootSecretAccessKey)"

kubectl port-forward -n "$NAMESPACE" svc/versitygw "${S3_LOCAL_PORT}:7070" \
  >/tmp/versitygw-wal-continuity-port-forward.log 2>&1 &
PF_PID=$!
sleep 3

export AWS_ACCESS_KEY_ID="$ROOT_ACCESS"
export AWS_SECRET_ACCESS_KEY="$ROOT_SECRET"
export AWS_DEFAULT_REGION="$S3_REGION"
export S3_ENDPOINT="http://127.0.0.1:${S3_LOCAL_PORT}"
export BUCKET PROBE_PREFIX PROBE_SERVER PROBE_SEGMENTS

# Which archive the verbs act on. Reassigned once, for the timeline phase.
WAL_PREFIX="$PROBE_PREFIX"
WAL_SERVER="$PROBE_SERVER"
WAL_TIMELINE=1
export WAL_PREFIX WAL_SERVER WAL_TIMELINE

s3() {
  VERB="$1" ARGS="${2:-}" python3 - <<'PY'
import os
import boto3

s3 = boto3.client("s3", endpoint_url=os.environ["S3_ENDPOINT"])
bucket = os.environ["BUCKET"]
prefix = os.environ["WAL_PREFIX"]
server = os.environ["WAL_SERVER"]
timeline = int(os.environ["WAL_TIMELINE"])


def key(ordinal):
    name = "%08X%08X%08X" % (timeline, ordinal // 256, ordinal % 256)
    return "%s/%s/wals/%s/%s.snappy" % (prefix, server, name[:16], name)


# Barman writes history files at the ROOT of wals/, never in a log directory --
# `hash_dir()` returns "" for them. A fixture that placed one a level down would
# agree with a reader looking in the wrong place.
def history_key():
    return "%s/%s/wals/%08X.history" % (prefix, server, timeline)


verb = os.environ["VERB"]
args = [int(a) for a in os.environ["ARGS"].split()] if os.environ["ARGS"] else []

if verb == "build":
    count = args[0] if args else int(os.environ["PROBE_SEGMENTS"])
    for i in range(count):
        s3.put_object(Bucket=bucket, Key=key(i), Body=b"x" * 256)
    print("built", count, "segments on timeline", timeline)
elif verb == "history":
    s3.put_object(Bucket=bucket, Key=history_key(),
                  Body=b"1\t0/2000000\tno recovery target specified\n")
    print("archived", history_key())
elif verb == "delete":
    for i in args:
        s3.delete_object(Bucket=bucket, Key=key(i))
    print("deleted", args)
elif verb == "zero":
    for i in args:
        s3.put_object(Bucket=bucket, Key=key(i), Body=b"")
    print("zeroed", args)
elif verb == "purge":
    token = None
    removed = 0
    while True:
        kwargs = {"Bucket": bucket, "Prefix": prefix + "/", "MaxKeys": 1000}
        if token:
            kwargs["ContinuationToken"] = token
        page = s3.list_objects_v2(**kwargs)
        for obj in page.get("Contents", []):
            s3.delete_object(Bucket=bucket, Key=obj["Key"])
            removed += 1
        token = page.get("NextContinuationToken")
        if not page.get("IsTruncated"):
            break
    print("purged", removed, "probe objects")
PY
}

# On every exit path: each injection leaves a broken archive, and the next run's
# baseline would be it. Before the port-forward goes, because the purge uses it.
cleanup() {
  for WAL_PREFIX in "$PROBE_PREFIX" "$SWITCH_PREFIX"; do
    export WAL_PREFIX
    s3 purge >/dev/null 2>&1 || true
  done
  kill "${PF_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# 300 spans the 256-segment logfile boundary: a reader treating the last eight
# hex digits as a flat counter passes on any shorter archive.

s3 build
force_pass
METRICS="$(scrape)"

expect "probe archive segments" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_segments)" "$PROBE_SEGMENTS"
expect "missing segments over a contiguous archive" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_segments)" "0"
expect "gaps over a contiguous archive" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_gaps)" "0"
echo "ok: 300 segments spanning the 256-boundary read as one unbroken chain" >&2

SERVERS_INTACT="$(printf '%s\n' "$METRICS" | unlabelled_sample versitygw_wal_archive_servers)"
if [ -z "$SERVERS_INTACT" ] || [ "$SERVERS_INTACT" -lt 1 ]; then
  echo "FAIL: versitygw_wal_archive_servers is '${SERVERS_INTACT}' with a probe archive present" >&2
  exit 1
fi

s3 delete "100"
force_pass
METRICS="$(scrape)"
expect "missing segments after deleting one from the middle" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_segments)" "1"
expect "gaps after deleting one from the middle" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_gaps)" "1"
expect "segments held after deleting one" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_segments)" "$((PROBE_SEGMENTS - 1))"

s3 delete "200 201 202"
force_pass
METRICS="$(scrape)"
expect "missing segments after a second, three-wide hole" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_segments)" "4"
expect "distinct gaps after a second hole" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_gaps)" "2"

s3 zero "150"
force_pass
METRICS="$(scrape)"
expect "zero-byte segments after truncating one in place" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_zero_byte_segments)" "1"
# Must NOT move: the object still exists and still lists, so the chain is
# unchanged by presence. Weakening this assertion removes the whole check.
expect "missing segments UNCHANGED by an emptied object" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_segments)" "4"
expect "segments held UNCHANGED by an emptied object" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_segments)" "$((PROBE_SEGMENTS - 4))"
echo "ok: presence and intactness are reported separately, and neither stands in for the other" >&2

s3 purge
force_pass
METRICS="$(scrape)"

# Vanished, not zero: a per-server series that disappears satisfies every
# threshold comparison silently.
REMAINING="$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_segments)"
if [ -n "$REMAINING" ]; then
  echo "FAIL: the probe archive was purged but its series is still reporting '${REMAINING}'" >&2
  exit 1
fi
echo "ok: the probe archive's series vanished with it -- NOT zero, absent" >&2

SERVERS_GONE="$(printf '%s\n' "$METRICS" | unlabelled_sample versitygw_wal_archive_servers)"
if [ -z "$SERVERS_GONE" ]; then
  echo "FAIL: versitygw_wal_archive_servers is absent, so nothing separates 'no gaps' from 'no data'" >&2
  exit 1
fi
if [ "$SERVERS_GONE" -ne "$((SERVERS_INTACT - 1))" ]; then
  echo "FAIL: servers went ${SERVERS_INTACT} -> ${SERVERS_GONE}, expected a fall of exactly 1" >&2
  exit 1
fi
echo "ok: servers ${SERVERS_INTACT} -> ${SERVERS_GONE}; the anchor moved when the series disappeared" >&2

# ---------------------------------------------------------------------------
# Second phase: an archive that begins ABOVE timeline 1.
#
# Every injection above is timeline 1, which is the one timeline whose history
# file legitimately does not exist -- so the whole history-file path, and the
# lower bound that decides which files a restore would need, went unexercised.
# This estate does not produce timeline-1-only archives for long: a
# `components/db-restore` rotation archives the restored generation under a new
# serverName starting on the timeline it was promoted to, so its LOWEST held
# timeline is >= 2 and its own `.history` file is the first thing it writes.
# Lose that file and the generation cannot be recovered at all, with every
# segment present.
WAL_PREFIX="$SWITCH_PREFIX"
WAL_SERVER="$SWITCH_SERVER"
WAL_TIMELINE=2
export WAL_PREFIX WAL_SERVER WAL_TIMELINE

s3 build "$SWITCH_SEGMENTS"
force_pass
METRICS="$(scrape)"

expect "segments held by a generation promoted onto timeline 2" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_segments "$SWITCH_PREFIX")" \
  "$SWITCH_SEGMENTS"
expect "timelines held by that generation" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_timelines "$SWITCH_PREFIX")" "1"
# The load-bearing assertion. Before this reader bounded the expected set at the
# lowest held timeline itself, it read every archive as if its lowest timeline
# were 1 -- so this returned 0 with the file genuinely absent.
expect "missing history files with 00000002.history absent" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_history_files "$SWITCH_PREFIX")" "1"
expect "missing segments across a promoted archive" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_segments "$SWITCH_PREFIX")" "0"

s3 history
force_pass
METRICS="$(scrape)"
# The negative control: without it, a reader that simply reported 1 forever
# would pass the assertion above.
expect "missing history files once 00000002.history is archived" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_missing_history_files "$SWITCH_PREFIX")" "0"
echo "ok: the history file a restore needs to follow a promotion is checked, both ways" >&2

# ---------------------------------------------------------------------------
# Third phase: the archive's contents are lost while its directory survives.
#
# Deleting every segment but leaving the history file behind keeps `wals/`
# present with no chain in it -- the shape a filesystem-level loss produces, and
# the one the purge above does NOT cover, since that removes the directory too
# and the server count falls. Here the count does not move, so if the per-server
# series simply vanished nothing anywhere would change.
DELETE_ARGS=""
for i in $(seq 0 $((SWITCH_SEGMENTS - 1))); do DELETE_ARGS="${DELETE_ARGS}${i} "; done
s3 delete "$DELETE_ARGS"
force_pass
METRICS="$(scrape)"

SERVERS_EMPTIED="$(printf '%s\n' "$METRICS" | unlabelled_sample versitygw_wal_archive_servers)"
if [ "$SERVERS_EMPTIED" -ne "$((SERVERS_GONE + 1))" ]; then
  echo "FAIL: servers is ${SERVERS_EMPTIED}, expected ${SERVERS_GONE} + 1 -- the emptied archive's" >&2
  echo "      directory should still be discovered, which is what makes this case distinct" >&2
  exit 1
fi
expect "segments reported for a server whose archive was emptied in place" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_segments "$SWITCH_PREFIX")" "0"
expect "newest-segment timestamp for that server" \
  "$(printf '%s\n' "$METRICS" | probe_sample versitygw_wal_archive_newest_segment_timestamp_seconds "$SWITCH_PREFIX")" "0"
echo "ok: an emptied-but-present archive reports 0 rather than dropping off the endpoint" >&2

echo "ok: the WAL chain's continuity is exported, and it goes red when the chain breaks" >&2
