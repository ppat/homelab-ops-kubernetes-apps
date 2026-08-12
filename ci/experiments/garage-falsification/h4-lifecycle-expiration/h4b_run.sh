#!/usr/bin/env bash
# H4-B adjudication retest driver. Mirrors ci/experiments/garage-falsification/h4-lifecycle-expiration/run.sh
# (same image, same engine/fsync config, same single-node layout) so the only differences from
# the original H4 are the three defects being corrected: distinct object bodies, a real
# positive control, and a wait longer than Garage's hardcoded 600 s BLOCK_GC_DELAY.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTAINER=h4b-garage
DATA_ROOT=/opt/build-scratch/h4b-data
RPC_SECRET="a7d0754a5ceaded2ceaeaeda44864637004a3d58aa844f4177c0b833463a4c32"
S3_PORT=15910
ADMIN_PORT=15913
OUT="$HERE/h4b-lifecycle-retest.json"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
sudo rm -rf "$DATA_ROOT"
mkdir -p "$DATA_ROOT/meta" "$DATA_ROOT/data"

cat > /tmp/h4b-garage.toml <<EOF
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
  -v /tmp/h4b-garage.toml:/etc/garage.toml:ro \
  -v "$DATA_ROOT/meta":/var/lib/garage/meta \
  -v "$DATA_ROOT/data":/var/lib/garage/data \
  -p "$S3_PORT:3900" -p "$ADMIN_PORT:3903" \
  dxflrs/garage:v2.3.0 >/dev/null

for _ in $(seq 1 30); do docker exec "$CONTAINER" /garage status >/dev/null 2>&1 && break; sleep 1; done

NODE_ID=$(docker exec "$CONTAINER" /garage node id -q | cut -d@ -f1)
docker exec "$CONTAINER" /garage layout assign -z dc1 -c 2G "$NODE_ID" >/dev/null
docker exec "$CONTAINER" /garage layout apply --version 1 >/dev/null
docker exec "$CONTAINER" /garage bucket create h4blifecycle >/dev/null
docker exec "$CONTAINER" /garage key create h4b-key >/dev/null
docker exec "$CONTAINER" /garage bucket allow --read --write --owner h4blifecycle --key h4b-key >/dev/null
INFO=$(docker exec "$CONTAINER" /garage key info h4b-key --show-secret)
ACCESS=$(echo "$INFO" | grep "Key ID:" | awk '{print $NF}')
SECRET=$(echo "$INFO" | grep "Secret key:" | awk '{print $NF}')

echo "garage version: $(docker exec "$CONTAINER" /garage --version 2>&1 | head -1)"

python3 "$HERE/h4b_retest.py" \
  --endpoint "http://127.0.0.1:$S3_PORT" --access-key "$ACCESS" --secret-key "$SECRET" \
  --bucket h4blifecycle --container "$CONTAINER" \
  --data-dir "$DATA_ROOT/data" --meta-dir "$DATA_ROOT/meta" \
  --n-objects 50 --object-mib 1 --max-wait-s 1200 \
  --out "$OUT"

echo "=== RESULT FILE ==="
cat "$OUT"
