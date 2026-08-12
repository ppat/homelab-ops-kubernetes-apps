#!/usr/bin/env python3
"""H5 byte-diff checker: sha256 every file in a directory tree, and either record that as
a manifest (--generate, run against the pre-backup writer-pod data) or compare against a
previously recorded manifest (--verify, run against the restored-volume mount).

--expect-mismatch is the fail-first proof mode required by the harness's standing rule
("prove the checker can detect a bad restore before trusting it"): with this flag, a
MISMATCH is the PASSING outcome for the *checker itself* (proves it can actually detect
corruption) and a clean MATCH means the checker is broken (exit 2, loud failure -- per the
brief: "if it doesn't, your checker is broken and the real result is void, say so loudly").

FAIL-FIRST RESULT (recorded 2026-08-12, see NOTES.md): generated a manifest from
/tmp/h5-fixture (3 files, ~15MiB total, /dev/urandom content -- see fixture-fail-first.sh),
copied the tree, flipped a single byte in one copied file, and ran --verify
--expect-mismatch against it. Output: `MISMATCH: 1/3 files differ (fixture-b.bin)` and exit
0 (expect-mismatch mode: MISMATCH-when-expected is success). Confirms the checker's hashing
+ comparison logic actually distinguishes correct from corrupted bytes rather than trivially
reporting MATCH regardless of content -- see NOTES.md for the full transcript.
"""
import argparse
import hashlib
import json
import os
import sys


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def walk_files(root):
    out = {}
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, root)
            out[rel] = full
    return out


def generate(root, manifest_path):
    files = walk_files(root)
    if not files:
        print(f"FAIL: no files found under {root} -- refusing to write an empty manifest")
        sys.exit(2)
    manifest = {rel: sha256_file(full) for rel, full in sorted(files.items())}
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
    total_bytes = sum(os.path.getsize(p) for p in files.values())
    print(f"GENERATED manifest={manifest_path} files={len(manifest)} bytes={total_bytes}")
    for rel, digest in manifest.items():
        print(f"  {digest}  {rel}")


def verify(root, manifest_path, expect_mismatch):
    with open(manifest_path) as f:
        expected = json.load(f)

    actual_files = walk_files(root)
    missing = sorted(set(expected) - set(actual_files))
    extra = sorted(set(actual_files) - set(expected))
    diffs = []
    for rel in sorted(set(expected) & set(actual_files)):
        actual_hash = sha256_file(actual_files[rel])
        if actual_hash != expected[rel]:
            diffs.append(rel)

    mismatch = bool(missing or extra or diffs)

    if missing:
        print(f"MISSING ({len(missing)}): {missing}")
    if extra:
        print(f"EXTRA ({len(extra)}): {extra}")
    if diffs:
        print(f"CONTENT MISMATCH ({len(diffs)}/{len(expected)}): {diffs}")

    if mismatch:
        print(f"MISMATCH: {len(missing) + len(extra) + len(diffs)}/{len(expected)} files differ")
    else:
        print(f"MATCH: all {len(expected)} files byte-identical")

    if expect_mismatch:
        # fail-first proof mode: we WANT a mismatch here, to prove the checker can detect one
        if mismatch:
            print("FAIL-FIRST OK: checker correctly reported MISMATCH on deliberately-broken input")
            sys.exit(0)
        else:
            print("FAIL-FIRST FAILED: checker reported MATCH on deliberately-broken input -- "
                  "CHECKER IS BROKEN, do not trust any MATCH result from this script until fixed")
            sys.exit(2)
    else:
        sys.exit(1 if mismatch else 0)


def main():
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--generate", action="store_true", help="write a manifest from --dir")
    mode.add_argument("--verify", action="store_true", help="compare --dir against --manifest")
    ap.add_argument("--dir", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--expect-mismatch", action="store_true",
                     help="fail-first mode: exit 0 only if a MISMATCH was found (proves the detector works)")
    args = ap.parse_args()

    if args.generate:
        if args.expect_mismatch:
            print("--expect-mismatch only applies to --verify")
            sys.exit(2)
        generate(args.dir, args.manifest)
    else:
        verify(args.dir, args.manifest, args.expect_mismatch)


if __name__ == "__main__":
    main()
