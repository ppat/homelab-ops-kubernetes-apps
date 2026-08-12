#!/usr/bin/env python3
"""H2 per-cell writer for one iteration: PUTs a handful of small "committed" objects, then
one large object via a THROTTLED streaming body so it takes several real seconds -- giving
the kill mechanic (kill -9 or a VM hard reset) a genuine mid-transfer window instead of
completing before the kill can land on loopback-fast localhost networking.

Ground truth for "acknowledged" writes: this script appends to a manifest file on the HOST
(never inside a substrate under test) immediately after each successful 2xx response, and
calls os.fsync() on it before moving on. That fsync is load-bearing: a hard reset drops the
page cache, so a merely-flushed-not-fsynced manifest could itself vanish and falsely blame
Garage for "losing" a write this harness never durably recorded as acknowledged in the first
place. If a PUT never returns 2xx (because the mechanic killed the server, or because the
whole VM died with it), nothing is appended -- that object is, correctly, not part of the
acknowledged set, and per the H2 brief its loss is expected and NOT a verdict of corruption.

Usage:
  python3 cell_iteration.py --endpoint http://127.0.0.1:20000 --access-key GK... \
      --secret-key ... --bucket h2 --manifest /path/manifest.jsonl \
      --small-count 5 --large-mb 24 --large-duration-s 12
"""
import argparse
import hashlib
import json
import os
import random
import time

import boto3
from botocore.config import Config


class ThrottledRandomBody:
    """A file-like object that yields random bytes in chunks, sleeping between chunks so a
    `size`-byte PUT takes approximately `duration_s` wall-clock seconds to stream -- this is
    what gives the kill mechanic a real "mid-PUT-stream" window on an otherwise-instant
    loopback connection.
    """

    def __init__(self, size, duration_s, seed):
        self.size = size
        self.remaining = size
        self.rng = random.Random(seed)
        self.chunk = 256 * 1024
        n_chunks = max(1, size // self.chunk)
        self.sleep_per_chunk = duration_s / n_chunks
        self._hash = hashlib.sha256()

    def read(self, n=-1):
        if self.remaining <= 0:
            return b""
        take = self.chunk if n in (-1, None) else min(n, self.chunk)
        take = min(take, self.remaining)
        data = self.rng.randbytes(take)
        self._hash.update(data)
        self.remaining -= take
        time.sleep(self.sleep_per_chunk)
        return data

    def sha256_so_far(self):
        return self._hash.hexdigest()


def append_manifest(path, record):
    with open(path, "a") as f:
        f.write(json.dumps(record) + "\n")
        f.flush()
        os.fsync(f.fileno())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--iteration", type=int, required=True)
    ap.add_argument("--small-count", type=int, default=5)
    ap.add_argument("--large-mb", type=int, default=24)
    ap.add_argument("--large-duration-s", type=float, default=12.0)
    args = ap.parse_args()

    client = boto3.client(
        "s3", endpoint_url=args.endpoint,
        aws_access_key_id=args.access_key, aws_secret_access_key=args.secret_key,
        config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 1}, connect_timeout=5, read_timeout=args.large_duration_s + 30),
        region_name="garage",
    )

    seed_base = args.iteration * 1000

    for j in range(args.small_count):
        key = f"iter{args.iteration:04d}/small-{j:02d}"
        body = random.Random(seed_base + j).randbytes(2048)
        digest = hashlib.sha256(body).hexdigest()
        try:
            client.put_object(Bucket=args.bucket, Key=key, Body=body)
        except Exception as e:  # noqa: BLE001
            print(f"small PUT {key} failed (not logged as acknowledged): {e}", flush=True)
            continue
        append_manifest(args.manifest, {"key": key, "size": len(body), "sha256": digest, "kind": "small"})
        print(f"acked small: {key}", flush=True)

    large_key = f"iter{args.iteration:04d}/large"
    size = args.large_mb * 1024 * 1024
    body = ThrottledRandomBody(size, args.large_duration_s, seed_base + 999)
    print(f"starting large PUT {large_key} ({args.large_mb}MiB over ~{args.large_duration_s}s) -- kill mechanic should land during this window", flush=True)
    try:
        client.put_object(Bucket=args.bucket, Key=large_key, Body=body, ContentLength=size)
    except Exception as e:  # noqa: BLE001
        print(f"large PUT {large_key} failed/interrupted (expected if the kill landed mid-stream, not logged as acknowledged): {e}", flush=True)
        return
    append_manifest(args.manifest, {"key": large_key, "size": size, "sha256": body.sha256_so_far(), "kind": "large"})
    print(f"acked large: {large_key} (kill mechanic did not land during the transfer window -- widen --large-duration-s)", flush=True)


if __name__ == "__main__":
    main()
