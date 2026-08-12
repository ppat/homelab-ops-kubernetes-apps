#!/usr/bin/env bash
# H2 hard-reset mechanic, step 3 of 3 (see hardreset_prep.sh and ../README.md for the full
# runbook). Run this AFTER reconnecting post-reboot. Restarts every cell's container
# (--restart unless-stopped may have already done this, but this is idempotent and doesn't
# assume it) and runs verify_cell.py against each, appending to results/h2-hardreset.jsonl.
#
# Usage: hardreset_verify.sh <iteration>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cells.sh
source "$HERE/cells.sh"

ITERATION="${1:?usage: hardreset_verify.sh <iteration>}"
OUT="$HERE/../results/h2-hardreset.jsonl"
mkdir -p "$(dirname "$OUT")"
touch "$OUT"

for i in "${!CELL_NAMES[@]}"; do
  name="${CELL_NAMES[$i]}"
  dir=$(cell_dir "$i")
  # shellcheck disable=SC1091
  source "$dir/creds.env"
  result=$(python3 "$HERE/verify_cell.py" \
    --container "${CELL_CONTAINER[$i]}" --s3-port "${CELL_S3_PORT[$i]}" \
    --endpoint "$CELL_ENDPOINT" --access-key "$CELL_ACCESS_KEY" --secret-key "$CELL_SECRET_KEY" \
    --bucket "$CELL_BUCKET" --manifest "$(cell_manifest "$i")" \
    --cell-name "$name" --iteration "$ITERATION" --mechanic hardreset \
    --start-timeout-s 60)
  echo "$result" >> "$OUT"
  verdict=$(echo "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])')
  echo "hardreset iter=$ITERATION cell=$name verdict=$verdict"
done
