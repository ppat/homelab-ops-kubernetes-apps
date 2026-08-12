#!/usr/bin/env python3
"""H1 loader: PUTs the shared Loki-shaped corpus (../lib/keygen.py) into one target
(MinIO or Garage), pausing at each checkpoint to measure RSS and ListObjectsV2 latency.

Runs ON THE DOCKER VM (not through SSH from the workstation) so RSS is read via a plain
`docker exec <container> ...` -- no network hop, no ambiguity about whose /proc it's reading.

State is checkpointed to <name>-state.json (next index to write) and results are appended
to <name>-results.jsonl, one JSON object per checkpoint, so a killed/restarted run resumes
without re-uploading everything already acknowledged.

Usage:
  python3 loader.py --name garage --endpoint http://127.0.0.1:13900 \
      --access-key GKxxx --secret-key xxx --bucket h1falsify --container h1-garage \
      --checkpoints 100000,500000,1000000,2000000,3441460 --workers 128
"""
import argparse
import concurrent.futures
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
from keygen import key_and_size, content_for  # noqa: E402

import boto3  # noqa: E402
from botocore.config import Config  # noqa: E402


def make_client(endpoint, access_key, secret_key):
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        config=Config(
            s3={"addressing_style": "path"},
            retries={"max_attempts": 3, "mode": "standard"},
            max_pool_connections=256,
        ),
        region_name="garage",  # accepted by both; MinIO is region-lenient, Garage's default install uses "garage"
    )


def put_one(client, bucket, i):
    key, size = key_and_size(i)
    body = content_for(i, size)
    client.put_object(Bucket=bucket, Key=key, Body=body)
    return size


def read_rss_mib(container):
    # Garage's image ships only the /garage binary -- no shell, no coreutils -- so
    # `docker exec ... grep` is not an option (confirmed: "exec: sh: executable file not
    # found"). Read the container's init process's /proc/<pid>/status directly from the
    # HOST instead: docker containers share the host kernel, so this needs no tooling
    # inside the container at all, just the host PID (via `docker inspect`) and sudo (the
    # container's root-owned process isn't otherwise readable by the ssh user).
    pid = subprocess.run(
        ["docker", "inspect", "-f", "{{.State.Pid}}", container],
        capture_output=True, text=True, timeout=10, check=True,
    ).stdout.strip()
    status = subprocess.run(
        ["sudo", "cat", f"/proc/{pid}/status"],
        capture_output=True, text=True, timeout=10, check=True,
    ).stdout
    for line in status.splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1]) / 1024.0
    raise RuntimeError(f"VmRSS not found in /proc/{pid}/status for {container}")


def list_latency_probe(client, bucket, n_probes, known_prefixes):
    """Mixed-prefix ListObjectsV2 latency sample: unprefixed (full first page), a chunk
    fingerprint prefix, and an index-period prefix -- reflecting the two key families
    documented in keygen.py, not a uniform keyspace scan.
    """
    import random
    latencies_ms = []
    modes = ["none"] * 1 + ["fake"] * 2 + ["index"] * 1  # LIST is dominated by chunk-prefix scans in Loki
    for i in range(n_probes):
        mode = random.choice(modes)
        kwargs = {"Bucket": bucket, "MaxKeys": 1000}
        if mode == "fake" and known_prefixes.get("fake"):
            kwargs["Prefix"] = random.choice(known_prefixes["fake"])
        elif mode == "index" and known_prefixes.get("index"):
            kwargs["Prefix"] = random.choice(known_prefixes["index"])
        t0 = time.monotonic()
        client.list_objects_v2(**kwargs)
        latencies_ms.append((time.monotonic() - t0) * 1000.0)
    latencies_ms.sort()

    def pct(p):
        idx = min(len(latencies_ms) - 1, int(len(latencies_ms) * p))
        return latencies_ms[idx]

    return {"p50_ms": pct(0.50), "p90_ms": pct(0.90), "p99_ms": pct(0.99), "max_ms": latencies_ms[-1], "n": len(latencies_ms)}


def known_prefixes_for(count):
    """Sample a handful of real prefixes that exist at this checkpoint, for the LIST probe."""
    fake_prefixes, index_prefixes = [], []
    for i in range(0, count, max(1, count // 50)):
        key, _ = key_and_size(i)
        if key.startswith("fake/"):
            fake_prefixes.append("/".join(key.split("/")[:2]) + "/")
        else:
            index_prefixes.append(key.split("/")[0] + "/")
    return {"fake": fake_prefixes[:20] or None, "index": index_prefixes[:20] or None}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--container", required=True, help="docker container name to read RSS from")
    ap.add_argument("--checkpoints", required=True, help="comma-separated cumulative object counts")
    ap.add_argument("--workers", type=int, default=128)
    ap.add_argument("--list-probes", type=int, default=200)
    ap.add_argument("--state-dir", default=".")
    args = ap.parse_args()

    checkpoints = [int(x) for x in args.checkpoints.split(",")]
    state_path = os.path.join(args.state_dir, f"{args.name}-state.json")
    results_path = os.path.join(args.state_dir, f"{args.name}-results.jsonl")

    next_index = 0
    if os.path.exists(state_path):
        next_index = json.load(open(state_path))["next_index"]
        print(f"[{args.name}] resuming from index {next_index}", flush=True)

    client = make_client(args.endpoint, args.access_key, args.secret_key)

    for target in checkpoints:
        if target <= next_index:
            print(f"[{args.name}] checkpoint {target} already done (next_index={next_index}), skipping write phase", flush=True)
        else:
            t0 = time.monotonic()
            bytes_written = 0
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
                futs = {}
                i = next_index
                submitted = 0
                batch = target - next_index
                while i < target:
                    while len(futs) < args.workers * 4 and i < target:
                        futs[pool.submit(put_one, client, args.bucket, i)] = i
                        i += 1
                        submitted += 1
                    done, _ = concurrent.futures.wait(futs, return_when=concurrent.futures.FIRST_COMPLETED)
                    for f in done:
                        idx = futs.pop(f)
                        try:
                            bytes_written += f.result()
                        except Exception as e:  # noqa: BLE001
                            print(f"[{args.name}] PUT failed at index {idx}: {e}", file=sys.stderr, flush=True)
                            raise
                        next_index = max(next_index, idx + 1)
                    if submitted % 50000 < args.workers * 4:
                        elapsed = time.monotonic() - t0
                        rate = (next_index - (target - batch)) / elapsed if elapsed > 0 else 0
                        print(f"[{args.name}] {next_index}/{target} ({rate:.0f} obj/s)", flush=True)
                # drain remaining
                for f in concurrent.futures.as_completed(list(futs.keys())):
                    idx = futs[f]
                    bytes_written += f.result()
                    next_index = max(next_index, idx + 1)
            next_index = target
            json.dump({"next_index": next_index}, open(state_path, "w"))
            elapsed = time.monotonic() - t0
            print(f"[{args.name}] checkpoint {target} write phase done in {elapsed:.1f}s ({batch / elapsed:.0f} obj/s)", flush=True)

        # --- measurement phase (always re-measured, even on a resumed/skip-write checkpoint) ---
        time.sleep(3)  # let RSS settle briefly after a write burst
        rss = read_rss_mib(args.container)
        kp = known_prefixes_for(target)
        list_lat = list_latency_probe(client, args.bucket, args.list_probes, kp)
        record = {
            "target": args.name,
            "checkpoint": target,
            "ts": time.time(),
            "rss_mib": rss,
            "list_latency": list_lat,
        }
        with open(results_path, "a") as f:
            f.write(json.dumps(record) + "\n")
        print(f"[{args.name}] CHECKPOINT {target}: RSS={rss:.1f}MiB list_p50={list_lat['p50_ms']:.1f}ms list_p99={list_lat['p99_ms']:.1f}ms", flush=True)

    print(f"[{args.name}] DONE", flush=True)


if __name__ == "__main__":
    main()
