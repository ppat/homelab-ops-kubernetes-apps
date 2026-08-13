#!/usr/bin/env python3
"""Scripted LogQL correctness check for the object-store migration trial (issue #3611).

What this proves: that Loki's query results for a fixed, already-flushed time
window are byte-for-byte identical no matter which object-store backend is
serving the chunks underneath. It talks only to Loki's query API - never to
the object store directly - so the same baseline captured today, while Loki
is MinIO-backed, keeps being re-verified every day straight through a future
cutover to another backend. A mismatch means the migration altered or lost
log data; that is what makes this a safety check and not a liveness probe.

Baseline capture happens exactly once, on the first run after deployment, and
is rejected (retried next schedule) if either query returns too few lines to
be a meaningful check - a check that could pass by both sides returning
nothing proves nothing. The anchor window is fixed at capture time and reused
forever after, so it must stay within Loki's configured retention for the
life of the trial; capturing it within the first day after deployment leaves
comfortable headroom under a 30-day retention/trial window.

State (the anchor window and its expected hashes) lives in a ConfigMap this
script owns, not in git - the whole point is that it is set once, by
whichever backend is live the first time this runs, and never touched again.
"""
import hashlib
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

LOKI_URL = os.environ.get("LOKI_URL", "http://loki.logging.svc.cluster.local.:3100")
NAMESPACE = os.environ["POD_NAMESPACE"]
BASELINE_CONFIGMAP = "loki-query-correctness-baseline"

# Both selectors are universal Kubernetes/Flux primitives (kube-system always
# exists; this is a FluxCD-managed repo so flux-system always exists) rather
# than anything cluster- or environment-specific, so this script needs no
# per-cluster configuration.
QUERIES = ['{namespace="kube-system"}', '{namespace="flux-system"}']

MIN_LINES_PER_QUERY = 10
PAGE_SIZE = 2000
ANCHOR_LAG_SECONDS = 2 * 3600  # how far behind "now" the anchor window's end sits
ANCHOR_WIDTH_SECONDS = 3600

K8S_API = "https://kubernetes.default.svc"
SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"


def k8s_request(method, path, body=None):
    with open(f"{SA_DIR}/token") as f:
        token = f.read().strip()
    ctx = ssl.create_default_context(cafile=f"{SA_DIR}/ca.crt")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{K8S_API}{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read()
        return e.code, (json.loads(body) if body else {})


def get_baseline():
    path = f"/api/v1/namespaces/{NAMESPACE}/configmaps/{BASELINE_CONFIGMAP}"
    status, body = k8s_request("GET", path)
    if status == 404:
        return None
    if status != 200:
        raise RuntimeError(f"failed to read baseline configmap: {status} {body}")
    return body["data"]


def write_baseline(data):
    path = f"/api/v1/namespaces/{NAMESPACE}/configmaps"
    manifest = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {"name": BASELINE_CONFIGMAP},
        "data": data,
    }
    status, body = k8s_request("POST", path, manifest)
    if status != 201:
        raise RuntimeError(f"failed to create baseline configmap: {status} {body}")


def query_loki_page(query, start_ns, end_ns, page_size):
    params = urllib.parse.urlencode(
        {
            "query": query,
            "start": start_ns,
            "end": end_ns,
            "limit": page_size,
            "direction": "forward",
        }
    )
    url = f"{LOKI_URL}/loki/api/v1/query_range?{params}"
    with urllib.request.urlopen(url, timeout=60) as resp:
        payload = json.loads(resp.read())
    if payload.get("status") != "success":
        raise RuntimeError(f"loki query failed for {query!r}: {payload}")
    return payload["data"]["result"]


def fetch_all_entries(query, start_ns, end_ns):
    """Page through query_range and return every (labels_json, ts_ns, line) tuple.

    Loki's query_range is limited per-call; paginate by advancing `start` past
    the last-seen timestamp until a page comes back under the page size, so
    the byte-for-byte claim isn't silently truncated on a busy window.
    """
    entries = []
    cursor = start_ns
    while True:
        streams = query_loki_page(query, cursor, end_ns, PAGE_SIZE)
        page_count = 0
        max_ts = cursor
        for stream in streams:
            labels_json = json.dumps(stream["stream"], sort_keys=True, separators=(",", ":"))
            for ts_ns, line in stream["values"]:
                entries.append((labels_json, int(ts_ns), line))
                page_count += 1
                max_ts = max(max_ts, int(ts_ns))
        if page_count < PAGE_SIZE or max_ts <= cursor:
            break
        cursor = max_ts + 1  # ns timestamps: strictly monotonic advance, no re-fetch overlap
    return entries


def canonical_hash(entries):
    """Order-independent, byte-for-byte digest of a query's log content."""
    entries = sorted(entries)
    h = hashlib.sha256()
    for labels_json, ts_ns, line in entries:
        h.update(labels_json.encode())
        h.update(b"\x00")
        h.update(str(ts_ns).encode())
        h.update(b"\x00")
        h.update(line.encode())
        h.update(b"\x1e")  # record separator
    return h.hexdigest()


def capture_baseline(now_ns):
    end_ns = (now_ns // 10**9 - ANCHOR_LAG_SECONDS) * 10**9
    start_ns = end_ns - ANCHOR_WIDTH_SECONDS * 10**9

    data = {"start_ns": str(start_ns), "end_ns": str(end_ns)}
    for query in QUERIES:
        entries = fetch_all_entries(query, start_ns, end_ns)
        if len(entries) < MIN_LINES_PER_QUERY:
            print(
                f"REJECTED baseline capture: query {query!r} returned "
                f"{len(entries)} lines (< {MIN_LINES_PER_QUERY}); a check that "
                f"could pass on empty results proves nothing. Retrying next schedule."
            )
            return 2
        data[query] = canonical_hash(entries)
        print(f"baseline: {query!r} -> {len(entries)} lines, hash {data[query][:12]}")

    write_baseline(data)
    print(f"baseline captured for window [{start_ns}, {end_ns}) and stored in {BASELINE_CONFIGMAP}")
    return 0


def verify_baseline(baseline):
    start_ns = int(baseline["start_ns"])
    end_ns = int(baseline["end_ns"])
    mismatches = []
    for query in QUERIES:
        entries = fetch_all_entries(query, start_ns, end_ns)
        actual_hash = canonical_hash(entries)
        expected_hash = baseline[query]
        if actual_hash != expected_hash:
            mismatches.append((query, expected_hash, actual_hash, len(entries)))
            print(
                f"MISMATCH: {query!r} expected {expected_hash[:12]} got "
                f"{actual_hash[:12]} ({len(entries)} lines now)"
            )
        else:
            print(f"OK: {query!r} matches baseline ({len(entries)} lines)")

    if mismatches:
        print(
            f"{len(mismatches)}/{len(QUERIES)} quer(y/ies) diverged from the "
            f"baseline captured for window [{start_ns}, {end_ns}) - object-store "
            "backend returned different log content for an already-closed window."
        )
        return 1
    return 0


def main():
    import time

    baseline = get_baseline()
    if baseline is None:
        return capture_baseline(time.time_ns())
    return verify_baseline(baseline)


if __name__ == "__main__":
    sys.exit(main())
