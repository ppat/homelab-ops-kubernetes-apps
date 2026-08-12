#!/usr/bin/env bash
# H2 kill-9 mechanic: `docker kill -9` the Garage process mid-PUT-stream. Does NOT lose the
# page cache (this is the mechanic the H2 brief explicitly warns is insufficient on its own
# -- "a process-kill-only test passes in nearly every cell and demonstrates nothing"). Run
# alongside the hard-reset mechanic (hardreset_prep.sh/hardreset_verify.sh), never instead of
# it.
#
# Usage: run_kill9.sh <iterations>
# Must run after run_setup.sh (and normally after run_failfirst.sh, which leaves cells reset
# and re-bootstrapped).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cells.sh
source "$HERE/cells.sh"

ITERATIONS="${1:?usage: run_kill9.sh <iterations>}"
OUT="$HERE/../results/h2-kill9.jsonl"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

for it in $(seq 1 "$ITERATIONS"); do
  for i in "${!CELL_NAMES[@]}"; do
    name="${CELL_NAMES[$i]}"
    dir=$(cell_dir "$i")
    # shellcheck disable=SC1091
    source "$dir/creds.env"
    manifest=$(cell_manifest "$i")

    nohup python3 "$HERE/cell_iteration.py" \
      --endpoint "$CELL_ENDPOINT" --access-key "$CELL_ACCESS_KEY" --secret-key "$CELL_SECRET_KEY" \
      --bucket "$CELL_BUCKET" --manifest "$manifest" --iteration "$it" \
      --small-count 5 --large-mb 12 --large-duration-s 8 \
      > "$dir/iter-$it-write.log" 2>&1 &
    writer_pid=$!

    sleep 4  # mid-transfer point for an 8s throttled large PUT
    docker kill -9 "${CELL_CONTAINER[$i]}" >/dev/null 2>&1

    wait "$writer_pid" 2>/dev/null || true

    result=$(python3 "$HERE/verify_cell.py" \
      --container "${CELL_CONTAINER[$i]}" --s3-port "${CELL_S3_PORT[$i]}" \
      --endpoint "$CELL_ENDPOINT" --access-key "$CELL_ACCESS_KEY" --secret-key "$CELL_SECRET_KEY" \
      --bucket "$CELL_BUCKET" --manifest "$manifest" \
      --cell-name "$name" --iteration "$it" --mechanic kill9)
    echo "$result" >> "$OUT"
    verdict=$(echo "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])')
    echo "kill9 iter=$it cell=$name verdict=$verdict"
  done
done

clean=$(grep -c '"verdict": "CLEAN"' "$OUT" || true)
total=$(wc -l < "$OUT")
echo "SUMMARY test=h2-kill9 iterations=$ITERATIONS cells=$NUM_CELLS total_checks=$total clean=$clean verdict=SEE-RESULTS-CSV"
