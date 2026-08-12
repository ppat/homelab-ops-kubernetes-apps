#!/usr/bin/env bash
# H2 fail-first gate: for EVERY cell, deliberately damage its (fresh, empty) metadata store
# and confirm verify_cell.py reports CORRUPT. Per the house idiom, this must be run and
# observed to fail (as CORRUPT) before any real H2 iteration from that cell's detector is
# trusted -- a cell that comes back CLEAN or DATA-LOSS here means its detector is broken and
# every subsequent kill9/hardreset result for that cell is VOID.
#
# Must run after run_setup.sh. Leaves every cell freshly reset (cell_reset) and re-bootstrapped
# afterward so run_kill9.sh / the hard-reset runbook start from a clean, uncorrupted state.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cells.sh
source "$HERE/cells.sh"

OUT="$HERE/../results/h2-failfirst.jsonl"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

any_broken=0
for i in "${!CELL_NAMES[@]}"; do
  name="${CELL_NAMES[$i]}"
  echo "=== FAIL-FIRST: $name ==="
  # A brand-new cell has no acknowledged writes, so assertions (c)/(d) are vacuous --
  # the only way the induced damage can be observed is (a) process won't start or
  # (b) repair reports errors, both of which verify_cell.py classifies as CORRUPT.
  bash "$HERE/corrupt_cell.sh" "$name"
  # shellcheck disable=SC1091
  source "$(cell_dir "$i")/creds.env"
  python3 "$HERE/verify_cell.py" \
    --container "${CELL_CONTAINER[$i]}" --s3-port "${CELL_S3_PORT[$i]}" \
    --endpoint "$CELL_ENDPOINT" --access-key "$CELL_ACCESS_KEY" --secret-key "$CELL_SECRET_KEY" \
    --bucket "$CELL_BUCKET" --manifest "$(cell_manifest "$i")" \
    --cell-name "$name" --iteration 0 --mechanic failfirst --expect-corrupt \
    | tee -a "$OUT"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "!!! $name: DETECTOR-BROKEN -- fail-first did not report CORRUPT"
    any_broken=1
  fi
  # Reset for the real matrix regardless of outcome, so a broken detector on one cell
  # doesn't block observing the others.
  cell_reset "$i"
  cell_up "$i"
  rc2=$(cell_wait_ready "$i")
  if [ "$rc2" != "0" ]; then
    echo "FATAL: $name S3 API never became ready after post-failfirst reset"; any_broken=1; continue
  fi
  sleep 1
  cell_bootstrap "$i"
done

if [ "$any_broken" -ne 0 ]; then
  echo "SUMMARY test=h2-failfirst verdict=DETECTOR-BROKEN -- see $OUT for which cell(s)"
  exit 1
fi
echo "SUMMARY test=h2-failfirst cells=$NUM_CELLS verdict=DETECTOR-OK"
