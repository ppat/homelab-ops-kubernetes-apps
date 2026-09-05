#!/bin/sh
set -eu

ROOT="${VERSITYGW_GATEWAY_ROOT:?VERSITYGW_GATEWAY_ROOT must be set}"
# The clock is not the obvious one: an upload directory's mtime is set by the
# last UploadPart and never moves again, so the bar is the SUM of the client's
# last-part-to-completion gap and the assembly's own duration. Reasoning from
# assembly duration alone unlinks parts from under a live assembler.
AGE_MINUTES="${VERSITYGW_SWEEP_AGE_MINUTES:?VERSITYGW_SWEEP_AGE_MINUTES must be set}"

[ -d "$ROOT" ] || { echo "FAIL: gateway root $ROOT is not a directory" >&2; exit 1; }

reclaimed=0
unreclaimable=0

reclaim() {
  if rm -rf -- "$1" 2>/dev/null && [ ! -e "$1" ]; then
    echo "reclaimed $2: $1"
    reclaimed=$((reclaimed + 1))
  else
    echo "FAIL: could not reclaim $2: $1" >&2
    unreclaimable=$((unreclaimable + 1))
  fi
}

reclaim_empty_dir() {
  if rmdir -- "$1" 2>/dev/null; then
    echo "reclaimed $2: $1"
    reclaimed=$((reclaimed + 1))
  elif [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
    echo "skipped $2 (an upload arrived between the check and the unlink): $1"
  else
    echo "FAIL: could not reclaim $2 -- it is still empty, so this is not the race: $1" >&2
    unreclaimable=$((unreclaimable + 1))
  fi
}

uploads="$(find "$ROOT" -mindepth 5 -maxdepth 5 -type d -path '*/.sgwtmp/multipart/*' -mmin "+${AGE_MINUTES}")"
overwrites="$(find "$ROOT" -mindepth 2 -type f -name '.*.sgwtmp.*' ! -path '*/.sgwtmp/*' -mmin "+${AGE_MINUTES}" |
  grep -E '/\.[^/]+\.sgwtmp\.[0-9]{16,}$' || true)"

while IFS= read -r d; do
  [ -n "$d" ] || continue
  case "$d" in
  *.inprogress) reclaim "$d" interrupted-assembly ;;
  *) reclaim "$d" abandoned-upload ;;
  esac
done <<EOF
$uploads
EOF

while IFS= read -r f; do
  [ -n "$f" ] || continue
  reclaim "$f" overwrite-race
done <<EOF
$overwrites
EOF

keydirs="$(find "$ROOT" -mindepth 4 -maxdepth 4 -type d -path '*/.sgwtmp/multipart/*' -mmin "+${AGE_MINUTES}")"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -z "$(ls -A "$d" 2>/dev/null)" ] || continue
  reclaim_empty_dir "$d" empty-key-directory
done <<EOF
$keydirs
EOF

echo "sweep complete: reclaimed=${reclaimed} unreclaimable=${unreclaimable} root=${ROOT} age_minutes=${AGE_MINUTES}"
[ "$unreclaimable" -eq 0 ] || exit 1
