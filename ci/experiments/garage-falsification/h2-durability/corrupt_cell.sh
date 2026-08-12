#!/usr/bin/env bash
# H2 fail-first damage injector. Engine-aware because lmdb and sqlite lay out their metadata
# differently on disk (confirmed by probing a live instance of each -- see ../README.md
# "Metadata file layout"):
#   lmdb:   <meta>/db.lmdb/data.mdb
#   sqlite: <meta>/db.sqlite (+ -wal if present, since sqlite here runs in WAL mode and the
#           most recent writes live in the WAL, not the main file -- corrupting only
#           db.sqlite would leave a fail-first gate that can't detect damage to the file
#           that actually matters)
#
# DEVIATION FROM THE H2 BRIEF, RECORD OF WHY: the brief specifies "dd the last 4KiB off
# data.mdb". We ran exactly that first and it produced DETECTOR-BROKEN (reported CLEAN) on
# 11 of 12 cells -- see ../README.md "Fail-first mechanic: a finding, not just a bug" for the
# full writeup. Root cause: LMDB's two meta pages (the only structures that must be intact
# for the env to open at all) live at the START of the file (pages 0-1), and LMDB's
# copy-on-write B+tree means old/free pages can be anywhere, including the tail -- on the
# small, mostly-empty test databases these cells start from, the last 4KiB is very likely
# unused free space that LMDB never reads. Tail-only corruption is a real risk on a SMALL
# database; it would very likely start being effective again on production's multi-GB
# data.mdb where the tail is live pages, but that's exactly the scale mismatch a fail-first
# gate exists to not have to trust by assumption. Fix: corrupt BOTH the head (guaranteed to
# hit the meta pages) and the tail (matching the brief's literal instruction) of every file.
# For sqlite this is redundant with corrupting the header (already in the first 100 bytes)
# but costs nothing and keeps the two engines' injectors symmetric.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cells.sh
source "$HERE/cells.sh"

usage() { echo "usage: $0 <cell-name>"; exit 2; }
[ $# -eq 1 ] || usage
i=$(cell_index_by_name "$1") || { echo "unknown cell: $1"; exit 2; }

substrate_dir="${CELL_SUBSTRATE_DIR[$i]}/${CELL_NAMES[$i]}"
meta_dir="$substrate_dir/meta"

echo "stopping ${CELL_CONTAINER[$i]} before corrupting its metadata store..."
docker stop "${CELL_CONTAINER[$i]}" >/dev/null

corrupt_head_and_tail_4k() {
  local f="$1"
  [ -f "$f" ] || { echo "  (no such file, skipping) $f"; return; }
  local size
  size=$(stat -c %s "$f")
  if [ "$size" -le 4096 ]; then
    echo "  $f is only ${size}B, zeroing it entirely"
    sudo dd if=/dev/zero of="$f" bs=1 count="$size" conv=notrunc status=none
    return
  fi
  echo "  $f: corrupting first 4096 bytes (meta pages) and last 4096 bytes (size=$size)"
  sudo dd if=/dev/urandom of="$f" bs=1 seek=0 count=4096 conv=notrunc status=none
  sudo dd if=/dev/urandom of="$f" bs=1 seek=$((size - 4096)) count=4096 conv=notrunc status=none
}

case "${CELL_ENGINE[$i]}" in
  lmdb)
    corrupt_head_and_tail_4k "$meta_dir/db.lmdb/data.mdb"
    ;;
  sqlite)
    corrupt_head_and_tail_4k "$meta_dir/db.sqlite"
    corrupt_head_and_tail_4k "$meta_dir/db.sqlite-wal"
    ;;
  *)
    echo "unknown engine ${CELL_ENGINE[$i]}"; exit 2 ;;
esac

echo "done: ${CELL_NAMES[$i]} metadata store deliberately damaged while stopped."
