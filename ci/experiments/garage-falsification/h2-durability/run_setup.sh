#!/usr/bin/env bash
# H2 one-time setup: provision the 4 substrates, then bring up + bootstrap all 12 cells
# fresh. Run this once before run_failfirst.sh / run_kill9.sh / the hard-reset runbook.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cells.sh
source "$HERE/cells.sh"

bash "$HERE/substrates.sh"

mkdir -p "$CELL_STATE_DIR"
for i in "${!CELL_NAMES[@]}"; do
  echo "=== cell ${CELL_NAMES[$i]} (${CELL_ENGINE[$i]}, fsync=${CELL_FSYNC[$i]}) on ${CELL_SUBSTRATE_DIR[$i]} ==="
  cell_reset "$i"
  cell_up "$i"
  rc=$(cell_wait_ready "$i")
  if [ "$rc" != "0" ]; then
    echo "FATAL: ${CELL_NAMES[$i]} S3 API never became ready"; exit 1
  fi
  sleep 1  # small safety margin past the first successful `garage status` round-trip
  cell_bootstrap "$i"
  echo "  ready: $(tr '\n' ' ' < "$(cell_dir "$i")/creds.env")"
done
echo "=== all $NUM_CELLS cells up and bootstrapped ==="
