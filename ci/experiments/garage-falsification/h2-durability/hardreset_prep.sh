#!/usr/bin/env bash
# H2 hard-reset mechanic, step 1 of 3 (see ../README.md "Running the hard-reset mechanic" for
# the full runbook -- this cannot be one unattended script because the host being rebooted
# cannot supervise its own reboot).
#
# Ensures all 12 cells are up, then launches one cell_iteration.py writer per cell in the
# background (all ~simultaneously) and returns immediately WITHOUT triggering the reboot --
# the caller (an operator or the driving harness, from a session that survives the reboot)
# is responsible for waiting until the writers are mid-transfer and then separately
# triggering `echo b > /proc/sysrq-trigger`.
#
# Usage: hardreset_prep.sh <iteration> [large-duration-s]
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cells.sh
source "$HERE/cells.sh"

ITERATION="${1:?usage: hardreset_prep.sh <iteration> [large-duration-s]}"
DURATION="${2:-15}"

for i in "${!CELL_NAMES[@]}"; do
  docker start "${CELL_CONTAINER[$i]}" >/dev/null 2>&1 || cell_up "$i"
done
for i in "${!CELL_NAMES[@]}"; do
  rc=$(cell_wait_ready "$i")
  [ "$rc" = "0" ] || echo "WARNING: ${CELL_NAMES[$i]} not ready before hardreset iteration $ITERATION"
done

for i in "${!CELL_NAMES[@]}"; do
  dir=$(cell_dir "$i")
  # shellcheck disable=SC1091
  source "$dir/creds.env"
  nohup python3 "$HERE/cell_iteration.py" \
    --endpoint "$CELL_ENDPOINT" --access-key "$CELL_ACCESS_KEY" --secret-key "$CELL_SECRET_KEY" \
    --bucket "$CELL_BUCKET" --manifest "$(cell_manifest "$i")" --iteration "$ITERATION" \
    --small-count 5 --large-mb 24 --large-duration-s "$DURATION" \
    > "$dir/iter-$ITERATION-write.log" 2>&1 &
  disown
done
echo "launched ${#CELL_NAMES[@]} writers for iteration $ITERATION, each ~${DURATION}s -- trigger the reboot ~half that time from now"
