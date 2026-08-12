#!/usr/bin/env bash
# H3-B: stand up throwaway Garage + MinIO (same images the harness used) and run the
# doubled-slash probe against both. Does not touch h1-*/h2-*/h4b-* containers.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GC=h3b-garage; MC=h3b-minio
GPORT=15920; GADMIN=15923; MPORT=15930
DATA_ROOT=/opt/build-scratch/h3b-data
RPC_SECRET="a7d0754a5ceaded2ceaeaeda44864637004a3d58aa844f4177c0b833463a4c32"

cleanup() { docker rm -f "$GC" "$MC" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup
sudo rm -rf "$DATA_ROOT"; mkdir -p "$DATA_ROOT/meta" "$DATA_ROOT/data" "$DATA_ROOT/minio"

cat > /tmp/h3b-garage.toml <<EOF
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

docker run -d --name "$GC" -v /tmp/h3b-garage.toml:/etc/garage.toml:ro \
  -v "$DATA_ROOT/meta":/var/lib/garage/meta -v "$DATA_ROOT/data":/var/lib/garage/data \
  -p "$GPORT:3900" -p "$GADMIN:3903" dxflrs/garage:v2.3.0 >/dev/null
for _ in $(seq 1 30); do docker exec "$GC" /garage status >/dev/null 2>&1 && break; sleep 1; done
NODE_ID=$(docker exec "$GC" /garage node id -q | cut -d@ -f1)
docker exec "$GC" /garage layout assign -z dc1 -c 1G "$NODE_ID" >/dev/null
docker exec "$GC" /garage layout apply --version 1 >/dev/null
docker exec "$GC" /garage bucket create h3b >/dev/null
docker exec "$GC" /garage key create h3b-key >/dev/null
docker exec "$GC" /garage bucket allow --read --write --owner h3b --key h3b-key >/dev/null
GINFO=$(docker exec "$GC" /garage key info h3b-key --show-secret)
GACCESS=$(echo "$GINFO" | grep "Key ID:" | awk '{print $NF}')
GSECRET=$(echo "$GINFO" | grep "Secret key:" | awk '{print $NF}')

docker run -d --name "$MC" -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin \
  -v "$DATA_ROOT/minio":/data -p "$MPORT:9000" \
  minio/minio:RELEASE.2025-04-22T22-12-26Z server /data >/dev/null
sleep 8
python3 - <<PY
import boto3
from botocore.config import Config
c = boto3.client("s3", endpoint_url="http://127.0.0.1:$MPORT", aws_access_key_id="minioadmin",
                 aws_secret_access_key="minioadmin", config=Config(s3={"addressing_style":"path"}),
                 region_name="us-east-1")
try: c.create_bucket(Bucket="h3b")
except Exception as e: print("bucket:", e)
PY

echo "### MINIO ###"
python3 "$HERE/h3b_probe.py" --endpoint "http://127.0.0.1:$MPORT" --access-key minioadmin \
  --secret-key minioadmin --bucket h3b --label minio || true
echo "### GARAGE ###"
python3 "$HERE/h3b_probe.py" --endpoint "http://127.0.0.1:$GPORT" --access-key "$GACCESS" \
  --secret-key "$GSECRET" --bucket h3b --region garage --label garage || true
