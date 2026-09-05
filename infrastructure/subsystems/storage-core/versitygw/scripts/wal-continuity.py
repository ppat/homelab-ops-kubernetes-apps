#!/usr/bin/env python3
"""Export whether the archived PostgreSQL WAL chain in the store is contiguous."""
import errno
import glob
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.environ.get("VERSITYGW_GATEWAY_ROOT", "/mnt/store/data")
INTERVAL = int(os.environ.get("VERSITYGW_WAL_INTERVAL_SECONDS", "3600"))
# NOT `VERSITYGW_WAL_CONTINUITY_PORT`: the Service of that name reserves it, and
# reading it back would yield `tcp://<clusterIP>:9104` instead of a port.
PORT = int(os.environ.get("VERSITYGW_WAL_LISTEN_PORT", "9104"))
ARCHIVE_GLOB = os.environ.get("VERSITYGW_WAL_ARCHIVE_GLOB", "*/*/*/wals")
# Must match the database's wal_segment_size: a wrong value fabricates a gap at
# every logfile boundary.
SEGMENTS_PER_LOG = int(os.environ.get("VERSITYGW_WAL_SEGMENTS_PER_LOG", "256"))
MAX_SERVERS = int(os.environ.get("VERSITYGW_WAL_MAX_SERVERS", "64"))

COMPRESSION_SUFFIXES = (".gz", ".bz2", ".lz4", ".zst", ".snappy", ".xz")
SEGMENT_RE = re.compile(r"^[0-9A-F]{24}$")
# Base-backup label files. Source-verified against barman: `_xlog_re` matches
# `<segment>.<offset>.backup` with the segment groups populated, so `hash_dir()`
# returns the same 16-hex log directory the segments live in -- these sit BESIDE
# segments, not at the root of `wals/` where history files go. Recognised so they
# stop inflating `unrecognised_entries`: one per retained base backup per database
# is a chronic count, and a gauge that is never 0 cannot be read as 0-or-not.
BACKUP_LABEL_RE = re.compile(r"^[0-9A-F]{24}\.[0-9A-F]{8}\.backup$")
HISTORY_RE = re.compile(r"^([0-9A-F]{8})\.history$")
LOGDIR_RE = re.compile(r"^[0-9A-F]{16}$")

_lock = threading.Lock()
_snapshot = (0, 0, None)


class Chain(object):
    def __init__(self):
        self.ordinals = set()
        self.zero_byte = 0
        self.partial = 0
        self.oldest = None
        self.newest = None


class Server(object):
    def __init__(self):
        self.chains = {}
        self.history = set()
        self.backup_labels = 0
        self.unrecognised = 0

    def chain(self, timeline):
        return self.chains.setdefault(timeline, Chain())


class Scan(object):
    def __init__(self):
        self.servers = {}
        self.errors = 0
        self.unrecognised = 0
        self.backup_labels = 0
        self.duration = 0.0
        self.completed = 0.0


def strip_compression(name):
    for suffix in COMPRESSION_SUFFIXES:
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return name


def read_segment_dir(path, server, errors):
    prefix = os.path.basename(path)
    try:
        entries = list(os.scandir(path))
    except OSError as exc:
        if exc.errno != errno.ENOENT:
            raise
        errors[0] += 1
        return
    for entry in entries:
        try:
            if not entry.is_file(follow_symlinks=False):
                # Counted, never skipped: a silently dropped entry is a
                # silently short chain.
                server.unrecognised += 1
                continue
            name = strip_compression(entry.name)
            if BACKUP_LABEL_RE.match(name):
                server.backup_labels += 1
                continue
            # Never counted as a segment: a `.partial` standing in for its full
            # segment would paper over a hole.
            partial = name.endswith(".partial")
            if partial:
                name = name[: -len(".partial")]
            # The startswith half is not redundant: a misfiled segment would
            # otherwise land on the wrong timeline's chain.
            if not SEGMENT_RE.match(name) or not name.startswith(prefix):
                server.unrecognised += 1
                continue
            timeline = name[:8]
            log = int(name[8:16], 16)
            segment = int(name[16:24], 16)
            if segment >= SEGMENTS_PER_LOG:
                server.unrecognised += 1
                continue
            chain = server.chain(timeline)
            if partial:
                chain.partial += 1
                continue
            stat = entry.stat(follow_symlinks=False)
            chain.ordinals.add(log * SEGMENTS_PER_LOG + segment)
            if stat.st_size == 0:
                chain.zero_byte += 1
            if chain.oldest is None or stat.st_mtime < chain.oldest:
                chain.oldest = stat.st_mtime
            if chain.newest is None or stat.st_mtime > chain.newest:
                chain.newest = stat.st_mtime
        except OSError:
            errors[0] += 1


def read_archive(path, errors):
    server = Server()
    stack = [path]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(current))
        except OSError as exc:
            if exc.errno != errno.ENOENT:
                raise
            errors[0] += 1
            continue
        for entry in entries:
            try:
                if entry.is_dir(follow_symlinks=False):
                    if LOGDIR_RE.match(entry.name):
                        read_segment_dir(entry.path, server, errors)
                    else:
                        server.unrecognised += 1
                    continue
                if not entry.is_file(follow_symlinks=False):
                    server.unrecognised += 1
                    continue
                match = HISTORY_RE.match(strip_compression(entry.name))
                if match:
                    server.history.add(match.group(1))
                else:
                    server.unrecognised += 1
            except OSError:
                errors[0] += 1
    return server


def scan():
    result = Scan()
    started = time.time()
    errors = [0]
    for path in sorted(glob.glob(os.path.join(ROOT, ARCHIVE_GLOB))):
        if not os.path.isdir(path):
            continue
        parts = os.path.relpath(os.path.dirname(path), ROOT).split(os.sep)
        if len(parts) < 2:
            continue
        key = (parts[0], "/".join(parts[1:-1]), parts[-1])
        result.servers[key] = read_archive(path, errors)
    result.errors = errors[0]
    result.unrecognised = sum(s.unrecognised for s in result.servers.values())
    result.backup_labels = sum(s.backup_labels for s in result.servers.values())
    result.duration = time.time() - started
    result.completed = time.time()
    return result


def gaps(ordinals):
    """Bounded by what is present, never from zero: an archive legitimately
    begins where its consumer started writing to THIS store. The cost is that a
    missing TAIL moves nothing here -- `_last_segment_ordinal` is what sees that.
    """
    if not ordinals:
        return 0, 0, 0, 0
    low = min(ordinals)
    high = max(ordinals)
    missing = (high - low + 1) - len(ordinals)
    runs = 0
    if missing:
        previous = None
        for value in sorted(ordinals):
            if previous is not None and value != previous + 1:
                runs += 1
            previous = value
    return low, high, missing, runs


def kept_servers(keys):
    if len(keys) <= MAX_SERVERS:
        return set(keys), False
    return set(sorted(keys)[:MAX_SERVERS]), True


def escape(value):
    # Without the round-trip, one filename the filesystem accepts and UTF-8 does
    # not takes down the whole endpoint.
    value = value.encode("utf-8", "replace").decode("utf-8")
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def labels(key, timeline=None):
    bucket, prefix, server = key
    out = 'bucket="%s",prefix="%s",server="%s"' % (
        escape(bucket),
        escape(prefix),
        escape(server),
    )
    if timeline is not None:
        out += ',timeline="%s"' % escape(timeline)
    return "{%s}" % out


def render(state):
    scans, failures, snap = state
    out = []
    add = out.append
    add("# HELP versitygw_wal_archive_scans_total WAL archive passes that completed.")
    add("# TYPE versitygw_wal_archive_scans_total counter")
    add("versitygw_wal_archive_scans_total %d" % scans)
    add("# HELP versitygw_wal_archive_scan_failures_total WAL archive passes that raised.")
    add("# TYPE versitygw_wal_archive_scan_failures_total counter")
    add("versitygw_wal_archive_scan_failures_total %d" % failures)
    if snap is None:
        # No gauges before the first pass: a zeroed missing count cannot be told
        # from a verified-contiguous chain.
        return "\n".join(out) + "\n"
    add("# HELP versitygw_wal_archive_last_scan_timestamp_seconds Unix time the last pass finished.")
    add("# TYPE versitygw_wal_archive_last_scan_timestamp_seconds gauge")
    add("versitygw_wal_archive_last_scan_timestamp_seconds %f" % snap.completed)
    add("# HELP versitygw_wal_archive_scan_duration_seconds Wall-clock seconds of the last pass.")
    add("# TYPE versitygw_wal_archive_scan_duration_seconds gauge")
    add("versitygw_wal_archive_scan_duration_seconds %f" % snap.duration)
    add("# HELP versitygw_wal_archive_scan_errors Entries the last pass could not read.")
    add("# TYPE versitygw_wal_archive_scan_errors gauge")
    add("versitygw_wal_archive_scan_errors %d" % snap.errors)
    # The anchor: every other series vanishes with its server, and a vanished
    # series reads as "nothing over threshold" in any comparison.
    add("# HELP versitygw_wal_archive_servers WAL archives discovered beneath the gateway root.")
    add("# TYPE versitygw_wal_archive_servers gauge")
    add("versitygw_wal_archive_servers %d" % len(snap.servers))
    add("# HELP versitygw_wal_archive_unrecognised_entries Entries under wals/ this reader does not model.")
    add("# TYPE versitygw_wal_archive_unrecognised_entries gauge")
    add("versitygw_wal_archive_unrecognised_entries %d" % snap.unrecognised)
    add("# HELP versitygw_wal_archive_backup_labels Base-backup label files recognised beside the segments.")
    add("# TYPE versitygw_wal_archive_backup_labels gauge")
    add("versitygw_wal_archive_backup_labels %d" % snap.backup_labels)

    keep, overflowed = kept_servers(snap.servers)
    if overflowed:
        add("# HELP versitygw_wal_archive_servers_unreported Servers folded out of the per-server series.")
        add("# TYPE versitygw_wal_archive_servers_unreported gauge")
        add("versitygw_wal_archive_servers_unreported %d" % (len(snap.servers) - len(keep)))
    shown = sorted(k for k in snap.servers if k in keep)

    rows = []
    for key in shown:
        for timeline in sorted(snap.servers[key].chains):
            chain = snap.servers[key].chains[timeline]
            low, high, missing, runs = gaps(chain.ordinals)
            rows.append((key, timeline, chain, low, high, missing, runs))

    # A server directory whose `wals/` survives while its contents do not holds no
    # chain, so it contributes no per-timeline row to anything below and simply
    # stops being reported -- and a series that vanished satisfies every threshold
    # comparison in silence. That is the filesystem-loss shape, and it is the one
    # the rules cannot close from their side: `or vector()` substitutes for an
    # expression that is empty overall, never for one server's missing row among
    # others still reporting. So the presence is emitted here, without a timeline
    # label because there is no timeline: a zero segment count that is a
    # measurement, and a newest-segment timestamp of 0, which any age derived from
    # it renders as an unmistakable half-century rather than as nothing at all.
    chainless = [key for key in shown if not snap.servers[key].chains]

    def emit(name, help_text, value_of, extra=(), kind="gauge"):
        add("# HELP %s %s" % (name, help_text))
        add("# TYPE %s %s" % (name, kind))
        for row in rows:
            value = value_of(row)
            if value is not None:
                add("%s%s %s" % (name, labels(row[0], row[1]), value))
        for key in extra:
            add("%s%s 0" % (name, labels(key)))

    emit(
        "versitygw_wal_archive_segments",
        "Complete segments held, per timeline; per server and 0 where no chain is held at all.",
        lambda r: "%d" % len(r[2].ordinals),
        extra=chainless,
    )
    emit(
        "versitygw_wal_archive_missing_segments",
        "Segments absent between the first and last held, per timeline. The gate's number.",
        lambda r: "%d" % r[5],
    )
    emit(
        "versitygw_wal_archive_gaps",
        "Distinct runs of absent segments, per timeline.",
        lambda r: "%d" % r[6],
    )
    # Never folded into the missing count: a segment emptied in place leaves the
    # chain contiguous by presence.
    emit(
        "versitygw_wal_archive_zero_byte_segments",
        "Held segments of zero length -- present, listable, and empty.",
        lambda r: "%d" % r[2].zero_byte,
    )
    emit(
        "versitygw_wal_archive_partial_segments",
        "Archived .partial segments, excluded from the contiguity set.",
        lambda r: "%d" % r[2].partial,
    )
    emit(
        "versitygw_wal_archive_first_segment_ordinal",
        "Ordinal of the earliest held segment (LSN >> 24 at 16 MiB segments).",
        lambda r: "%d" % r[3] if r[2].ordinals else None,
    )
    # A gap test is blind to a lost TAIL, so a green missing count does not on
    # its own clear a cutover. This is `LSN >> 24` at a 16 MiB segment size, and
    # comparing it with the LSN Postgres reports archived is what sees one.
    emit(
        "versitygw_wal_archive_last_segment_ordinal",
        "Ordinal of the latest held segment. Comparable with what Postgres believes it archived.",
        lambda r: "%d" % r[4] if r[2].ordinals else None,
    )
    emit(
        "versitygw_wal_archive_oldest_segment_timestamp_seconds",
        "Modification time of the earliest-written held segment.",
        lambda r: "%f" % r[2].oldest if r[2].oldest else None,
    )
    emit(
        "versitygw_wal_archive_newest_segment_timestamp_seconds",
        "Modification time of the latest-written held segment; 0 where a server holds none.",
        lambda r: "%f" % r[2].newest if r[2].newest else None,
        extra=chainless,
    )

    # Expected for every timeline held from the lowest upward, EXCEPT timeline 1,
    # which is the only one that has no history file to archive. Bounding this at
    # `lowest + 1` instead reads the lowest held timeline as if it were timeline
    # 1, and in this estate it usually is not: `components/db-restore` rotates
    # generations, and a restored generation archives under a NEW serverName
    # starting on the timeline it was promoted to, so its lowest held timeline is
    # >= 2 and its own `.history` file is the first thing it archives. Losing that
    # file makes the generation unrecoverable -- `readTimeLineHistory()` needs it
    # for any target timeline above 1 -- with every segment present and every
    # other number here green.
    add("# HELP versitygw_wal_archive_timelines Distinct timelines held, per server.")
    add("# TYPE versitygw_wal_archive_timelines gauge")
    for key in shown:
        add("versitygw_wal_archive_timelines%s %d" % (labels(key), len(snap.servers[key].chains)))
    add("# HELP versitygw_wal_archive_missing_history_files Timeline history files a restore would need and cannot find.")
    add("# TYPE versitygw_wal_archive_missing_history_files gauge")
    for key in shown:
        server = snap.servers[key]
        timelines = sorted(int(t, 16) for t in server.chains)
        expected = (
            {t for t in range(min(timelines), max(timelines) + 1) if t > 1}
            if timelines
            else set()
        )
        held = set(int(t, 16) for t in server.history)
        add(
            "versitygw_wal_archive_missing_history_files%s %d"
            % (labels(key), len(expected - held))
        )
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
    last = None
    while True:
        try:
            last = scan()
            scans += 1
            print(
                "wal scan ok: servers=%d segments=%d missing=%d zero_byte=%d "
                "unrecognised=%d errors=%d duration=%.1fs"
                % (
                    len(last.servers),
                    sum(len(c.ordinals) for s in last.servers.values() for c in s.chains.values()),
                    sum(
                        gaps(c.ordinals)[2]
                        for s in last.servers.values()
                        for c in s.chains.values()
                    ),
                    sum(c.zero_byte for s in last.servers.values() for c in s.chains.values()),
                    last.unrecognised,
                    last.errors,
                    last.duration,
                ),
                flush=True,
            )
        except Exception as exc:  # noqa: BLE001
            failures += 1
            # Broad on purpose: a narrower except would kill this thread while
            # the server kept serving the last numbers. The snapshot's timestamp
            # is deliberately not touched, so a failing pass reads as staleness.
            print("wal scan failed: %s" % exc, file=sys.stderr, flush=True)
        with _lock:
            _snapshot = (scans, failures, last)
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
