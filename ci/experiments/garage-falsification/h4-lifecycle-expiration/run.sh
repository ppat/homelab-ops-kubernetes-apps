#!/usr/bin/env bash
# H4: does a plain S3 Expiration lifecycle rule on a NON-versioned bucket actually reclaim
# disk space? This is the exact incumbent-MinIO failure mode (delete markers + noncurrent
# versions never reclaimed) wearing different clothes if we only check LIST/metrics and not
# `du` -- see ../README.md and the H4 brief for why (3) is the only assertion that would
# have caught it.
#
# Timing trick (documented deviation from the brief's two suggested options -- "offset the
# container clock" or "accept a 26h background run"): Garage's lifecycle worker runs once on
# process START, but ONLY if it hasn't already completed a run for today -- it persists a
# `last_completed: <date>` marker in <meta>/lifecycle_worker_state and skips re-running on a
# same-day restart. (First guess was "every restart re-triggers it" from watching one cold
# start; that guess was wrong and a plain `docker restart` produced no second run -- see
# lifecycle_check.py's comment for how this was caught.) Deleting that state file before
# restart forces a fresh run regardless of what day it thinks it already ran. Since
# expirationDate is set to YESTERDAY (as instructed, because expirationDays is age-based and
# can't fire on a freshly-written object), a worker run "for today" still catches it
# (yesterday <= today). This substitutes for both of the brief's suggested options and
# completes in seconds instead of 26h.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTAINER=h4-garage
DATA_ROOT=/opt/build-scratch/h4-data
RPC_SECRET="a7d0754a5ceaded2ceaeaeda44864637004a3d58aa844f4177c0b833463a4c32"
S3_PORT=15900
ADMIN_PORT=15903
OUT="$HERE/../results/h4-lifecycle.json"
mkdir -p "$(dirname "$OUT")"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
sudo rm -rf "$DATA_ROOT"
mkdir -p "$DATA_ROOT/meta" "$DATA_ROOT/data"

cat > /tmp/h4-garage.toml <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"
metadata_fsync = true
replication_factor = 1
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "$RPC_SECRET"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[admin]
api_bind_addr = "[::]:3903"
EOF

docker run -d --name "$CONTAINER" \
  -v /tmp/h4-garage.toml:/etc/garage.toml:ro \
  -v "$DATA_ROOT/meta":/var/lib/garage/meta \
  -v "$DATA_ROOT/data":/var/lib/garage/data \
  -p "$S3_PORT:3900" -p "$ADMIN_PORT:3903" \
  dxflrs/garage:v2.3.0 >/dev/null

for _ in $(seq 1 30); do docker exec "$CONTAINER" /garage status >/dev/null 2>&1 && break; sleep 1; done

NODE_ID=$(docker exec "$CONTAINER" /garage node id -q | cut -d@ -f1)
docker exec "$CONTAINER" /garage layout assign -z dc1 -c 2G "$NODE_ID" >/dev/null
docker exec "$CONTAINER" /garage layout apply --version 1 >/dev/null
docker exec "$CONTAINER" /garage bucket create h4lifecycle >/dev/null
docker exec "$CONTAINER" /garage key create h4-key >/dev/null
docker exec "$CONTAINER" /garage bucket allow --read --write --owner h4lifecycle --key h4-key >/dev/null
INFO=$(docker exec "$CONTAINER" /garage key info h4-key --show-secret)
ACCESS=$(echo "$INFO" | grep "Key ID:" | awk '{print $NF}')
SECRET=$(echo "$INFO" | grep "Secret key:" | awk '{print $NF}')

python3 "$HERE/lifecycle_check.py" \
  --endpoint "http://127.0.0.1:$S3_PORT" --access-key "$ACCESS" --secret-key "$SECRET" \
  --bucket h4lifecycle --container "$CONTAINER" --data-dir "$DATA_ROOT/data" \
  --out "$OUT"
