#!/usr/bin/env bash
# H1 fail-first gate: run the loader against a Garage instance whose metadata_dir is a
# 512MiB tmpfs, pre-filled to leave only ~32MiB free. This MUST end in ENOSPC (or the
# container being OOMKilled) before any real H1 measurement is trusted -- if the loader
# reports success here, the loader isn't really writing what it claims (or isn't checking
# errors), and every later H1 number from it is void. Per the house idiom
# (clusters-repo sandbox falsifiability-check.sh): this is a warm-up gate, not a nice-to-have.
#
# Must be run ON the Docker VM (needs local docker + python3/boto3, same as loader.py).
set -euo pipefail

CONTAINER=h1-failfirst-garage
NETWORK=h1-failfirst-net
DATA_ROOT=/opt/build-scratch/h1-failfirst

TMPFS_VOL=h1-failfirst-meta-tmpfs

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  docker volume rm "$TMPFS_VOL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== H1 FAIL-FIRST: tmpfs metadata_dir, must ENOSPC or OOM ==="
cleanup
sudo rm -rf "$DATA_ROOT"
mkdir -p "$DATA_ROOT/data"
docker network create "$NETWORK" >/dev/null
# A real --tmpfs mount is per-container and invisible on the host, so we can't pre-fill it
# from a sidecar. A named volume with the tmpfs driver is a real tmpfs (same ENOSPC-at-512MiB
# behavior) but is shareable -- a busybox sidecar pre-fills it, then garage mounts the same
# volume as its metadata_dir. Garage's own image has no shell utilities (dd/df not present),
# which is why the pre-fill has to happen from outside it.
docker volume create --driver local --opt type=tmpfs --opt device=tmpfs --opt o=size=512m "$TMPFS_VOL" >/dev/null

cat > /tmp/h1-failfirst-garage.toml <<'EOF'
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"
replication_factor = 1
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "a7d0754a5ceaded2ceaeaeda44864637004a3d58aa844f4177c0b833463a4c32"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[admin]
api_bind_addr = "[::]:3903"
metrics_token = "h1failfirst-metrics-token"
admin_token = "h1failfirst-admin-token"
EOF

docker run -d --name "$CONTAINER" --network "$NETWORK" \
  -v "$TMPFS_VOL":/var/lib/garage/meta \
  -v /tmp/h1-failfirst-garage.toml:/etc/garage.toml:ro \
  -v "$DATA_ROOT/data":/var/lib/garage/data \
  -p 13910:3900 -p 13911:3903 \
  --memory 2g \
  dxflrs/garage:v2.3.0 >/dev/null

echo "waiting for garage to come up..."
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER" /garage status >/dev/null 2>&1; then break; fi
  sleep 1
done

NODE_ID=$(docker exec "$CONTAINER" /garage node id -q | cut -d@ -f1)
docker exec "$CONTAINER" /garage layout assign -z dc1 -c 1G "$NODE_ID"
docker exec "$CONTAINER" /garage layout apply --version 1
docker exec "$CONTAINER" /garage bucket create h1failfirst
docker exec "$CONTAINER" /garage key create h1failfirst-key
docker exec "$CONTAINER" /garage bucket allow --read --write --owner h1failfirst --key h1failfirst-key
KEY_INFO=$(docker exec "$CONTAINER" /garage key info h1failfirst-key --show-secret)
ACCESS_KEY=$(echo "$KEY_INFO" | grep "Key ID:" | awk '{print $NF}')
SECRET_KEY=$(echo "$KEY_INFO" | grep "Secret key:" | awk '{print $NF}')

echo "pre-filling tmpfs to leave ~32MiB free out of 512MiB (before garage writes anything of its own)..."
docker run --rm -v "$TMPFS_VOL":/meta alpine sh -c 'head -c 470000000 /dev/zero > /meta/.junk && df -h /meta'

echo "hammering PUTs until the detector observes ENOSPC or the container dies..."
set +e
python3 - "$ACCESS_KEY" "$SECRET_KEY" "$CONTAINER" <<'PYEOF'
import sys, time
import boto3
from botocore.config import Config

access_key, secret_key, container = sys.argv[1:4]
client = boto3.client(
    "s3", endpoint_url="http://127.0.0.1:13910",
    aws_access_key_id=access_key, aws_secret_access_key=secret_key,
    config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 1}),
    region_name="garage",
)

failed = False
reason = None
for i in range(200_000):
    try:
        client.put_object(Bucket="h1failfirst", Key=f"failfirst/{i:08d}", Body=b"x" * 4096)
    except Exception as e:  # noqa: BLE001
        failed = True
        reason = f"PUT #{i} raised: {e}"
        break
    if i % 2000 == 0:
        print(f"  ...{i} PUTs acknowledged so far, no failure yet", flush=True)

if failed:
    print(f"DETECTOR-FIRED: {reason}")
    sys.exit(3)  # distinct code: detector caught the induced failure as expected
else:
    print("DETECTOR-DID-NOT-FIRE: 200000 PUTs into a 512MiB tmpfs (32MiB free) all acknowledged -- something is wrong with either the loader's error handling or this test's assumptions")
    sys.exit(1)
PYEOF
LOADER_RC=$?
set -e

INSPECT=$(docker inspect "$CONTAINER" --format '{{.State.Status}} OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}' 2>/dev/null || echo "container gone")
echo "container state after hammering: $INSPECT"

if [ "$LOADER_RC" -eq 3 ]; then
  echo "SUMMARY test=h1-failfirst-tmpfs mechanism=enospc-or-error verdict=DETECTOR-OK"
  exit 0
elif echo "$INSPECT" | grep -q "OOMKilled=true"; then
  echo "SUMMARY test=h1-failfirst-tmpfs mechanism=oomkill verdict=DETECTOR-OK"
  exit 0
elif echo "$INSPECT" | grep -qE "^(exited|dead)"; then
  echo "SUMMARY test=h1-failfirst-tmpfs mechanism=container-died verdict=DETECTOR-OK"
  exit 0
else
  echo "SUMMARY test=h1-failfirst-tmpfs verdict=DETECTOR-BROKEN"
  echo "FATAL: the fail-first gate did not fail. Every H1 result produced by this loader is VOID until this is fixed."
  exit 1
fi
