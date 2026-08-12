#!/usr/bin/env bash
# Fail-first proof for checksum_verify.py, run independent of Longhorn/K8s (pure local
# filesystem) so the checker itself is proven correct before it's ever trusted against a
# real restore. See NOTES.md for the actual recorded output of this script.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

ORIG="$ROOT/orig"
COPY="$ROOT/copy"
mkdir -p "$ORIG"

# varied, real, checksummable content -- not just a few bytes (per the brief: enough that a
# truncated/corrupted restore would plausibly be caught)
head -c 5242880 /dev/urandom > "$ORIG/fixture-a.bin"     # 5 MiB random
head -c 10485760 /dev/urandom > "$ORIG/fixture-b.bin"    # 10 MiB random
for i in $(seq 1 20000); do echo "h5-fixture line $i: the quick brown fox jumps over the lazy dog"; done > "$ORIG/fixture-c.txt"

cp -r "$ORIG" "$COPY"

echo "=== 1/2: MATCH case (copy is byte-identical) -- checker must report MATCH, verify runs clean ==="
python3 "$HERE/checksum_verify.py" --generate --dir "$ORIG" --manifest "$ROOT/manifest.json"
python3 "$HERE/checksum_verify.py" --verify --dir "$COPY" --manifest "$ROOT/manifest.json"
echo "OK: clean copy verified as MATCH (exit 0)"

echo "=== 2/2: FAIL-FIRST -- flip one byte in the copy, verify with --expect-mismatch ==="
python3 - "$COPY/fixture-b.bin" <<'EOF'
import sys
path = sys.argv[1]
with open(path, "r+b") as f:
    f.seek(1234567)
    b = f.read(1)
    f.seek(1234567)
    f.write(bytes([b[0] ^ 0xFF]))
print(f"flipped 1 byte in {path} at offset 1234567")
EOF
python3 "$HERE/checksum_verify.py" --verify --dir "$COPY" --manifest "$ROOT/manifest.json" --expect-mismatch
echo "FAIL-FIRST PROOF PASSED: checker correctly detected the corrupted byte"
