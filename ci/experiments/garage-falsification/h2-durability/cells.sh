#!/usr/bin/env bash
# H2 cell definitions: the 4 substrates x 3 engine configs = 12 cells, plus the functions to
# bring one up, bootstrap its layout/bucket/key, and tear it down. Sourced by the
# orchestration scripts (run_failfirst.sh, run_kill9.sh, the hard-reset runbook).
#
# Ports: base 20000 + cell_index*10 (s3 = +0, admin = +1, rpc = +2). One fixed RPC secret is
# reused across all cells -- they never talk to each other (replication_factor=1, single
# node each), so a shared secret has no cross-cell security implication here.
set -u

RPC_SECRET="a7d0754a5ceaded2ceaeaeda44864637004a3d58aa844f4177c0b833463a4c32"
CELL_STATE_DIR=/opt/build-scratch/h2-cells

SUBSTRATE_MOUNTS=(
  "ext4-local:/mnt/h2-ext4-local"
  "ext4-iscsi:/mnt/h2-ext4-iscsi"
  "nfsv4.1:/mnt/h2-nfsv4.1"
  "tmpfs-loop:/mnt/h2-tmpfs-loop"
)

# engine_key:db_engine:metadata_fsync
ENGINE_CONFIGS=(
  "lmdb-nofsync:lmdb:false"
  "lmdb-fsync:lmdb:true"
  "sqlite-fsync:sqlite:true"
)

# Populate arrays: CELL_NAMES, CELL_SUBSTRATE_DIR, CELL_ENGINE, CELL_FSYNC, CELL_S3_PORT,
# CELL_ADMIN_PORT, CELL_RPC_PORT, CELL_CONTAINER -- all indexed identically.
CELL_NAMES=(); CELL_SUBSTRATE_DIR=(); CELL_ENGINE=(); CELL_FSYNC=()
CELL_S3_PORT=(); CELL_ADMIN_PORT=(); CELL_RPC_PORT=(); CELL_CONTAINER=()
idx=0
for sm in "${SUBSTRATE_MOUNTS[@]}"; do
  sname="${sm%%:*}"; sdir="${sm#*:}"
  for ec in "${ENGINE_CONFIGS[@]}"; do
    IFS=: read -r ekey edb efsync <<< "$ec"
    name="${sname}__${ekey}"
    port_base=$((20000 + idx * 10))
    CELL_NAMES+=("$name")
    CELL_SUBSTRATE_DIR+=("$sdir")
    CELL_ENGINE+=("$edb")
    CELL_FSYNC+=("$efsync")
    CELL_S3_PORT+=("$port_base")
    CELL_ADMIN_PORT+=("$((port_base + 1))")
    CELL_RPC_PORT+=("$((port_base + 2))")
    CELL_CONTAINER+=("h2-$name")
    idx=$((idx + 1))
  done
done
# shellcheck disable=SC2034 # used by scripts that `source` this file (run_setup.sh, run_kill9.sh, run_failfirst.sh)
NUM_CELLS=${#CELL_NAMES[@]}

cell_index_by_name() {
  local target="$1"
  for i in "${!CELL_NAMES[@]}"; do
    [ "${CELL_NAMES[$i]}" = "$target" ] && { echo "$i"; return 0; }
  done
  return 1
}

cell_dir() { # $1 = cell index -> host dir holding this cell's meta/data/creds
  echo "$CELL_STATE_DIR/${CELL_NAMES[$1]}"
}

cell_toml() { # $1 = cell index -> emits garage.toml content on stdout
  local i="$1"
  cat <<EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "${CELL_ENGINE[$i]}"
metadata_fsync = ${CELL_FSYNC[$i]}
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
}

cell_up() { # $1 = cell index -- create dirs, write toml, (re)start the container
  local i="$1"
  local dir; dir=$(cell_dir "$i")
  mkdir -p "$dir/meta" "$dir/data"
  local substrate_dir="${CELL_SUBSTRATE_DIR[$i]}/${CELL_NAMES[$i]}"
  mkdir -p "$substrate_dir/meta" "$substrate_dir/data"
  cell_toml "$i" > "$dir/garage.toml"
  docker rm -f "${CELL_CONTAINER[$i]}" >/dev/null 2>&1 || true
  docker run -d --name "${CELL_CONTAINER[$i]}" \
    --restart unless-stopped \
    -v "$dir/garage.toml":/etc/garage.toml:ro \
    -v "$substrate_dir/meta":/var/lib/garage/meta \
    -v "$substrate_dir/data":/var/lib/garage/data \
    -p "${CELL_S3_PORT[$i]}:3900" \
    -p "${CELL_ADMIN_PORT[$i]}:3903" \
    dxflrs/garage:v2.3.0 >/dev/null
}

cell_wait_ready() { # $1 = cell index -- poll until garage's own RPC round-trips or timeout;
  # echoes 0/1. `node id -q` alone was observed to succeed (it's a local key-file read)
  # before the netapp RPC listener would actually accept a loopback connection, which made
  # the immediately-following `layout assign` race it intermittently. `status` does a real
  # RPC round-trip (it reports cluster members), so it's a tighter readiness signal --
  # matches what ../h1-rss-list/failfirst-tmpfs.sh already uses successfully.
  local i="$1" tries=0
  while [ $tries -lt 30 ]; do
    if docker exec "${CELL_CONTAINER[$i]}" /garage status >/dev/null 2>&1; then
      echo 0; return
    fi
    sleep 1; tries=$((tries + 1))
  done
  echo 1
}

cell_bootstrap() { # $1 = cell index -- layout/bucket/key, writes creds to $dir/creds.env
  local i="$1"
  local dir; dir=$(cell_dir "$i")
  local c="${CELL_CONTAINER[$i]}"
  local node_id
  node_id=$(docker exec "$c" /garage node id -q | cut -d@ -f1)
  docker exec "$c" /garage layout assign -z dc1 -c 4G "$node_id" >/dev/null
  docker exec "$c" /garage layout apply --version 1 >/dev/null
  docker exec "$c" /garage bucket create h2falsify >/dev/null
  docker exec "$c" /garage key create h2-key >/dev/null
  docker exec "$c" /garage bucket allow --read --write --owner h2falsify --key h2-key >/dev/null
  local info access secret
  info=$(docker exec "$c" /garage key info h2-key --show-secret)
  access=$(echo "$info" | grep "Key ID:" | awk '{print $NF}')
  secret=$(echo "$info" | grep "Secret key:" | awk '{print $NF}')
  cat > "$dir/creds.env" <<EOF
CELL_ENDPOINT=http://127.0.0.1:${CELL_S3_PORT[$i]}
CELL_ACCESS_KEY=$access
CELL_SECRET_KEY=$secret
CELL_BUCKET=h2falsify
EOF
}

cell_container_pid() { docker inspect -f '{{.State.Pid}}' "${CELL_CONTAINER[$1]}" 2>/dev/null; }

cell_reset() { # $1 = cell index -- wipe this cell's on-disk state for a clean start
  local i="$1"
  docker rm -f "${CELL_CONTAINER[$i]}" >/dev/null 2>&1 || true
  local substrate_dir="${CELL_SUBSTRATE_DIR[$i]}/${CELL_NAMES[$i]}"
  sudo rm -rf "$substrate_dir"
  mkdir -p "$substrate_dir/meta" "$substrate_dir/data"
  rm -f "$(cell_dir "$i")/manifest.jsonl"
}

cell_manifest() { echo "$(cell_dir "$1")/manifest.jsonl"; }
