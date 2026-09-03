#!/usr/bin/env python3
"""Export the object store's contents -- object count and bytes stored, per bucket.

Nothing free substitutes for the walk: `inodes_used` measured 1.86x the object
count on a metadata-faithful replica, drifting as Longhorn's block-store
directory fanout saturates. And nothing push-based substitutes for a scrape
target -- a StatsD gauge has no TTL, so a dead producer's last good value stands
forever, masking exactly the emptied store this exists to detect.
"""

import errno
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.environ.get("VERSITYGW_GATEWAY_ROOT", "/mnt/store/data")
INTERVAL = int(os.environ.get("VERSITYGW_INVENTORY_INTERVAL_SECONDS", "86400"))
# NOT `VERSITYGW_INVENTORY_PORT`: naming a Service `versitygw-inventory` reserves
# that name for the kubelet's Docker-link-style injection, where it means
# `tcp://<clusterIP>:9103`. The Deployment also turns the injection off; this
# name is what keeps the script correct in a pod that has not.
PORT = int(os.environ.get("VERSITYGW_INVENTORY_LISTEN_PORT", "9103"))
# A bounded pause every N stat()s, so the walk yields the array rather than
# holding it flat out. The default is deliberately near-free -- at the measured
# walk shape (367,000 stat()s) it adds ~0.15 s -- and it ships enabled rather
# than at 0 so the path is exercised on every walk instead of being untested
# code waiting for the day it is needed. It is the operator's lever, not a
# tuned value: the walk was timed on a virtio SSD and the store lives on an
# iSCSI LUN on a shared array, so if `versitygw_store_scan_duration_seconds`
# ever shows the walk starving that array, lower YIELD_EVERY and/or raise
# YIELD_SECONDS. Setting YIELD_EVERY to 0 disables the brake entirely.
YIELD_EVERY = int(os.environ.get("VERSITYGW_INVENTORY_YIELD_EVERY", "5000"))
YIELD_SECONDS = float(os.environ.get("VERSITYGW_INVENTORY_YIELD_SECONDS", "0.002"))
# A walk that raised keeps the previous snapshot but not its timestamp, so its
# only other signal is staleness -- which at a daily interval takes more than a
# day to become legible. Retry sooner instead, backing off so a persistent fault
# does not re-pay 367,000 reads in a loop.
RETRY_SECONDS = int(os.environ.get("VERSITYGW_INVENTORY_RETRY_SECONDS", "900"))

# Staged writes and multipart parts. Never returned by ListObjectsV2, so counting
# it as objects would make the store's own count disagree with what its clients
# see -- hence its own series rather than a silent drop.
RESIDUE_DIR = ".sgwtmp"
# The third form the sweep reclaims: an overwrite interrupted between its link
# and its rename leaves a full-size file beside the object, OUTSIDE .sgwtmp.
# This predicate is `sweep.sh`'s, deliberately character-for-character: change
# one and change the other, or the two stop agreeing on the shape. The age guard
# is NOT shared -- this is age-blind where the sweep reclaims only past
# VERSITYGW_SWEEP_AGE_MINUTES, so a write in flight right now counts here and the
# sweep correctly leaves it alone. The series is a superset of what the next
# sweep would reclaim; one sample of it is not a reading of sweep health.
OVERWRITE_RESIDUE = re.compile(r"^\.[^/]+\.sgwtmp\.[0-9]{16,}$")

_lock = threading.Lock()
_snapshot = (0, 0, None)


class Scan(object):
    def __init__(self):
        self.buckets = {}
        self.residue = {}
        self.overwrite_residue = {}
        self.errors = 0
        self.duration = 0.0
        self.completed = 0.0


def walk_bucket(path, residue_root, counters):
    """One pass over a bucket, splitting objects from staged residue.

    Iterative rather than recursive: the block store nests
    volumes/<xx>/<yy>/<name>/blocks/<xx>/<yy>/ and a deeper layout would reach
    the interpreter's recursion limit for no visible reason.

    An overwrite-race file is counted in BOTH the object totals and the
    overwrite-residue totals, and that is not double-counting a mistake: it is
    S3-visible as an ordinary key, so leaving it out of the object count would
    break the one property worth the most here -- that the exported count is
    what a client's ListObjectsV2 returns -- while leaving it out of residue is
    how unreclaimable bytes accumulate with every derived series reading calm.
    """
    totals = [0, 0, 0, 0, 0, 0]
    errors = 0
    stack = [(path, False)]
    while stack:
        current, in_residue = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    try:
                        if entry.is_dir(follow_symlinks=False):
                            stack.append((entry.path, in_residue or entry.path == residue_root))
                            continue
                        if not entry.is_file(follow_symlinks=False):
                            continue
                        offset = 2 if in_residue else 0
                        size = entry.stat(follow_symlinks=False).st_size
                        totals[offset] += 1
                        totals[offset + 1] += size
                        if not in_residue and OVERWRITE_RESIDUE.match(entry.name):
                            totals[4] += 1
                            totals[5] += size
                        counters[0] += 1
                        if YIELD_EVERY and counters[0] % YIELD_EVERY == 0:
                            time.sleep(YIELD_SECONDS)
                    except OSError:
                        # A file unlinked between getdents and stat is normal on
                        # a live store, not a fault -- counted, not raised.
                        errors += 1
        except OSError as exc:
            if exc.errno != errno.ENOENT:
                raise
            errors += 1
    return totals, errors


def scan():
    result = Scan()
    started = time.time()
    counters = [0]
    with os.scandir(ROOT) as entries:
        for entry in entries:
            if not entry.is_dir(follow_symlinks=False):
                continue
            residue_root = os.path.join(entry.path, RESIDUE_DIR)
            totals, errors = walk_bucket(entry.path, residue_root, counters)
            result.buckets[entry.name] = (totals[0], totals[1])
            result.residue[entry.name] = (totals[2], totals[3])
            result.overwrite_residue[entry.name] = (totals[4], totals[5])
            result.errors += errors
    result.duration = time.time() - started
    result.completed = time.time()
    return result


def escape(value):
    # The round-trip is not cosmetic: a directory name the filesystem accepts but
    # UTF-8 does not arrives here with surrogate escapes, and encoding the
    # response would then raise -- taking the whole endpoint down over one stray
    # directory. A mangled label is the better outcome.
    value = value.encode("utf-8", "replace").decode("utf-8")
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def render(state):
    scans, failures, snap = state
    out = []
    add = out.append
    add("# HELP versitygw_store_scans_total Inventory walks that completed.")
    add("# TYPE versitygw_store_scans_total counter")
    add("versitygw_store_scans_total %d" % scans)
    add("# HELP versitygw_store_scan_failures_total Inventory walks that raised.")
    add("# TYPE versitygw_store_scan_failures_total counter")
    add("versitygw_store_scan_failures_total %d" % failures)
    if snap is None:
        # No gauges before the first walk finishes, deliberately: a zeroed object
        # count would be indistinguishable from an emptied store, which is the
        # one reading this exists to make unambiguous.
        return "\n".join(out) + "\n"
    add("# HELP versitygw_store_last_scan_timestamp_seconds Unix time the last walk finished.")
    add("# TYPE versitygw_store_last_scan_timestamp_seconds gauge")
    add("versitygw_store_last_scan_timestamp_seconds %f" % snap.completed)
    add("# HELP versitygw_store_scan_duration_seconds Wall-clock seconds of the last walk.")
    add("# TYPE versitygw_store_scan_duration_seconds gauge")
    add("versitygw_store_scan_duration_seconds %f" % snap.duration)
    add("# HELP versitygw_store_scan_errors Entries the last walk could not read.")
    add("# TYPE versitygw_store_scan_errors gauge")
    add("versitygw_store_scan_errors %d" % snap.errors)
    add("# HELP versitygw_store_buckets Bucket directories at the gateway root.")
    add("# TYPE versitygw_store_buckets gauge")
    add("versitygw_store_buckets %d" % len(snap.buckets))
    add("# HELP versitygw_store_objects Objects a client would list, per bucket.")
    add("# TYPE versitygw_store_objects gauge")
    buckets = snap.buckets
    for name in sorted(buckets):
        add('versitygw_store_objects{bucket="%s"} %d' % (escape(name), buckets[name][0]))
    add("# HELP versitygw_store_bytes Sum of object sizes as S3 reports them, per bucket.")
    add("# TYPE versitygw_store_bytes gauge")
    for name in sorted(buckets):
        add('versitygw_store_bytes{bucket="%s"} %d' % (escape(name), buckets[name][1]))
    residue = snap.residue
    add("# HELP versitygw_store_residue_objects Staged part files under .sgwtmp, per bucket.")
    add("# TYPE versitygw_store_residue_objects gauge")
    for name in sorted(residue):
        add('versitygw_store_residue_objects{bucket="%s"} %d' % (escape(name), residue[name][0]))
    add("# HELP versitygw_store_residue_bytes Bytes held by staged part files, per bucket.")
    add("# TYPE versitygw_store_residue_bytes gauge")
    for name in sorted(residue):
        add('versitygw_store_residue_bytes{bucket="%s"} %d' % (escape(name), residue[name][1]))
    overwrite = snap.overwrite_residue
    add("# HELP versitygw_store_overwrite_residue_objects Overwrite-race files beside their objects, per bucket; age-blind, so writes still in flight are included.")
    add("# TYPE versitygw_store_overwrite_residue_objects gauge")
    for name in sorted(overwrite):
        add('versitygw_store_overwrite_residue_objects{bucket="%s"} %d'
            % (escape(name), overwrite[name][0]))
    add("# HELP versitygw_store_overwrite_residue_bytes Bytes held by overwrite-race files beside their objects, per bucket.")
    add("# TYPE versitygw_store_overwrite_residue_bytes gauge")
    for name in sorted(overwrite):
        add('versitygw_store_overwrite_residue_bytes{bucket="%s"} %d'
            % (escape(name), overwrite[name][1]))
    return "\n".join(out) + "\n"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path.split("?")[0] not in ("/metrics", "/"):
            self.send_error(404)
            return
        with _lock:
            body = render(_snapshot).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def loop():
    global _snapshot
    scans = 0
    failures = 0
    consecutive = 0
    last = None
    while True:
        try:
            last = scan()
            scans += 1
            consecutive = 0
            print(
                "scan ok: buckets=%d objects=%d bytes=%d errors=%d duration=%.1fs"
                % (
                    len(last.buckets),
                    sum(v[0] for v in last.buckets.values()),
                    sum(v[1] for v in last.buckets.values()),
                    last.errors,
                    last.duration,
                ),
                flush=True,
            )
        except Exception as exc:  # noqa: BLE001 -- see below
            failures += 1
            consecutive += 1
            # Broad on purpose: a narrower except lets an unanticipated exception
            # kill this thread while the server keeps serving the last good
            # numbers. The previous snapshot is kept but its timestamp is not
            # touched, so a failing walk surfaces as rising staleness.
            print("scan failed (%d in a row): %s" % (consecutive, exc),
                  file=sys.stderr, flush=True)
        with _lock:
            _snapshot = (scans, failures, last)
        # A single unreadable directory unwinds the whole walk, and at the daily
        # interval a transient one would cost a full day of currency. Retry
        # sooner, doubling up to the interval so a permanent fault settles back
        # to the ordinary cadence instead of re-walking 367,000 entries in a
        # loop. `versitygw_store_scan_failures_total` is what distinguishes this
        # state from a slow walk; staleness alone cannot.
        if consecutive:
            time.sleep(min(RETRY_SECONDS * (2 ** (consecutive - 1)), INTERVAL))
        else:
            time.sleep(INTERVAL)


def main():
    global _snapshot
    _snapshot = (0, 0, None)
    if not os.path.isdir(ROOT):
        print("FAIL: %s is not a directory" % ROOT, file=sys.stderr)
        sys.exit(1)
    threading.Thread(target=loop, daemon=True).start()
    ThreadingHTTPServer(("", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
