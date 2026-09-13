#!/usr/bin/env python3
"""Seed the residue sweep's fixture, or verify what the sweep left behind.

Two modes in one file, because seed and verify run as separate pods and must
agree exactly on every path -- splitting them is how a fixture ends up hunting
for something it never created.

ONE of the four aged shapes is DISCOVERED rather than constructed: an abandoned
upload the S3 round-trip left through the ordinary API, so at least one shape
the sweep matches is one the gateway really produces.
"""

"""Seed the sweep's fixture, or verify what it left."""
import os
import re
import sys
import time

mode = os.environ["MODE"]
root = os.path.join("/pvc", "data")
bucket = os.environ["BUCKET_ONE"]
age_minutes = int(os.environ["AGE_MINUTES"])

STATE = "/pvc/fixture-discovered-upload"

aged = time.time() - (age_minutes * 60) - 3600

mp = os.path.join(root, bucket, ".sgwtmp", "multipart")
FRESH_KEY = "b" * 64
EMPTY_KEY = "c" * 64
ETAG = "d41d8cd98f00b204e9800998ecf8427e"
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
SHA256HEX = re.compile(r"^[0-9a-f]{64}$")

def discover_produced_upload():
    """Find the abandoned upload the S3 round-trip left, asserting its shape.

    Every assertion here is about the layout `sweep.sh` depends on. If upstream
    inserts a directory level, renames `multipart`, or shards the key hash, this
    is where the suite goes red -- instead of the sweep quietly matching nothing
    in production forever.
    """
    if not os.path.isdir(mp):
        raise SystemExit(
            "FAIL: %s does not exist. Either versitygw-roundtrip.sh did not run before this "
            "step (check the step order in validate-versitygw.yaml), or it did and the "
            "gateway no longer places multipart uploads under <bucket>/.sgwtmp/multipart/ -- "
            "in which case sweep.sh's find is matching nothing in production." % mp)

    keydirs = sorted(os.listdir(mp))
    if len(keydirs) != 1:
        raise SystemExit(
            "FAIL: expected exactly one key directory under %s (the round-trip's single "
            "abandoned upload), found %r" % (mp, keydirs))
    keydir = keydirs[0]
    if not SHA256HEX.match(keydir):
        raise SystemExit(
            "FAIL: %s is not a 64-character hex key hash. sweep.sh matches upload "
            "directories at a fixed depth beneath this one; a changed naming or sharding "
            "scheme moves them out from under it." % keydir)

    uploads = sorted(os.listdir(os.path.join(mp, keydir)))
    if len(uploads) != 1 or not UUID.match(uploads[0]):
        raise SystemExit(
            "FAIL: expected exactly one uploadId directory under %s/%s, found %r"
            % (mp, keydir, uploads))

    produced = os.path.join(mp, keydir, uploads[0])
    parts = sorted(os.listdir(produced))
    if not parts:
        raise SystemExit("FAIL: the discovered upload %s holds no part files" % produced)

    print("ok: discovered a gateway-produced abandoned upload at the expected layout")
    print("     %s (parts: %r)" % (produced, parts))
    return produced

OLD_KEY = "a" * 64
old_assembly = os.path.join(mp, OLD_KEY, "22222222-2222-2222-2222-222222222222.%s-1.inprogress" % ETAG)
old_overwrite = os.path.join(root, bucket, "wal", ".000000010000000000000009.sgwtmp.1756880000000000000")
old_empty = os.path.join(mp, EMPTY_KEY)

fresh_upload = os.path.join(mp, FRESH_KEY, "33333333-3333-3333-3333-333333333333")
fresh_assembly = os.path.join(mp, FRESH_KEY, "44444444-4444-4444-4444-444444444444.%s-1.inprogress" % ETAG)
fresh_overwrite = os.path.join(root, bucket, "wal", ".000000010000000000000010.sgwtmp.1900000000000000000")

real_object = os.path.join(root, bucket, "wal", "000000010000000000000001")

def reclaim_list(produced):
    return [
        (produced, "aged abandoned upload (gateway-produced, discovered on disk)"),
        (old_assembly, "aged interrupted assembly"),
        (old_overwrite, "aged overwrite-race file"),
        (old_empty, "aged empty key directory"),
    ]

SURVIVE = [
    (fresh_upload, "in-flight upload"),
    (fresh_assembly, "in-flight assembly"),
    (fresh_overwrite, "in-flight overwrite-race file"),
    (real_object, "a real object written through the S3 API"),
]

# Backdating is bottom-up: writing a child resets the parent's mtime, which is
# what the sweep reads. The wrong order ages the leaves and leaves the tested
# directory fresh.
def seed():
    produced = discover_produced_upload()
    with open(STATE, "w") as handle:
        handle.write(produced)

    for path in (old_assembly, fresh_upload, fresh_assembly):
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, "1"), "wb") as handle:
            handle.write(b"part-payload")
    os.makedirs(old_empty, exist_ok=True)
    os.makedirs(os.path.join(root, bucket, "wal"), exist_ok=True)
    for path in (old_overwrite, fresh_overwrite):
        with open(path, "wb") as handle:
            handle.write(b"overwrite-payload")

    for path in ([os.path.join(produced, name) for name in sorted(os.listdir(produced))] +
                 [produced,
                  os.path.join(old_assembly, "1"), old_assembly,
                  old_overwrite, old_empty]):
        os.utime(path, (aged, aged))

    for path, label in reclaim_list(produced) + SURVIVE:
        print("seeded %-40s %s" % (label, path))
    print("---")
    print("fixture seeded")

def verify():
    if not os.path.isfile(STATE):
        raise SystemExit("FAIL: %s is missing -- the seed pass did not record the "
                         "gateway-produced upload it discovered" % STATE)
    with open(STATE) as handle:
        produced = handle.read().strip()

    failures = []
    for path, label in reclaim_list(produced):
        if os.path.exists(path):
            print("FAIL: %s was NOT reclaimed: %s" % (label, path))
            failures.append(label)
        else:
            print("ok: %s was reclaimed" % label)
    for path, label in SURVIVE:
        if os.path.exists(path):
            print("ok: %s survived" % label)
        else:
            print("FAIL: %s was DESTROYED by the sweep: %s" % (label, path))
            failures.append(label)
    print("---")
    if failures:
        print("%d sweep assertion(s) failed" % len(failures))
        sys.exit(1)
    print("sweep reclaimed every aged form and left every in-flight one intact")

{"seed": seed, "verify": verify}[mode]()
