#!/usr/bin/env python3
"""H4 body: PUT real objects, measure the three assertions BEFORE the rule is even applied
(fail-first -- validated against a real control that proves the `du` probe can register a
DROP, not just a nonzero value), apply an Expiration rule dated yesterday, restart Garage
(triggers its startup lifecycle-worker run), then measure all three again after waiting past
Garage's block-GC delay.

Fixed after the original run's fail-first and timing turned out to be void, not negative (see
RESULTS.md H4 for the full account):

  - Every object body is now distinct (`os.urandom` per object). The original PUT the SAME
    body 200 times; Garage is content-addressed, so 200 MiB of PUTs deduplicated into a
    single ~1 MiB block, and `du` on data_dir was tracking one block's lifecycle, not 200
    objects' worth of blocks.
  - The fail-first now actually proves the `du` probe CAN register a drop, using a small
    control set removed via plain DeleteObject and polled to the same wait floor used for the
    real result. The original fail-first only asserted `du_bytes > 0` before the rule was
    applied -- true by construction, and it never demonstrated the probe could observe a
    decrease at all. A fail-first that cannot fail makes the downstream result void, not
    negative -- that is the standing rule this whole harness is built around (see README).
  - The wait after triggering GC is now >= BLOCK_GC_DELAY + 10s (610s), not ~60s. Garage
    v2.3.0 hardcodes `BLOCK_GC_DELAY = 600s` (src/block/manager.rs:44) and schedules the
    deleting resync at `now + BLOCK_GC_DELAY + 10s` (:490) -- there is no config knob for
    this; `block_gc_delay` does not appear in `src/util/config.rs` or the config docs, so
    there is no tuning tradeoff to weigh, only a floor to wait out. `garage repair --yes
    blocks` CANNOT shorten this: it is exclusively `put_to_resync(hash, 0)`
    (src/block/repair.rs:92-150), and `resync_block` no-ops on a block whose `at_time` hasn't
    elapsed. Upstream removed repair-triggered deletion deliberately in PR #135 to fix
    data-loss issue #39 -- do not "fix" this by making repair force the delete, that
    reintroduces #39. This script still runs `repair --yes blocks` (matching the brief's
    falsifier), it just no longer relies on it to shorten the wait.

Note this test's 1 MiB objects do NOT exercise Garage's inline-object path
(`INLINE_THRESHOLD = 3072 B`) that covers 95.4% of the real production estate -- see
`h4c_inline.sh` in this directory for that separate, still-open question.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
import time

import boto3
from botocore.config import Config

# See module docstring: Garage v2.3.0's block deletion resync is scheduled at
# now + BLOCK_GC_DELAY(600s) + 10s, with no config knob to shorten it.
BLOCK_GC_DELAY_S = 600
MIN_WAIT_S = BLOCK_GC_DELAY_S + 30  # floor + margin
POLL_INTERVAL_S = 30


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def du_bytes(path):
    return int(sh(["sudo", "du", "-sb", path], check=True).stdout.split()[0])


def object_count(container, bucket):
    out = sh(["docker", "exec", container, "/garage", "bucket", "info", bucket], check=True).stdout
    for line in out.splitlines():
        if line.strip().startswith("Objects:"):
            return int(line.split(":")[1].strip())
    return None


def list_count(client, bucket, prefix=""):
    resp = client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    return resp.get("KeyCount", 0)


def snapshot(client, bucket, container, data_dir, label, prefix=""):
    s = {
        "label": label,
        "list_key_count": list_count(client, bucket, prefix),
        "bucket_object_count": object_count(container, bucket),
        "du_bytes": du_bytes(data_dir),
    }
    print(f"SNAPSHOT[{label}]: list={s['list_key_count']} bucket_objects={s['bucket_object_count']} du_bytes={s['du_bytes']}", flush=True)
    return s


def poll_for_drop(data_dir, baseline_du, max_wait_s, interval=POLL_INTERVAL_S):
    """Poll du until it drops materially (>10%) below baseline_du, or max_wait_s elapses.
    Returns (dropped: bool, final_du: int)."""
    deadline = time.time() + max_wait_s
    du = baseline_du
    while True:
        du = du_bytes(data_dir)
        if du < baseline_du * 0.9:
            return True, du
        if time.time() >= deadline:
            return False, du
        time.sleep(interval)


def put_distinct(client, bucket, prefix, n, mib):
    for i in range(n):
        client.put_object(Bucket=bucket, Key=f"{prefix}{i:05d}", Body=os.urandom(mib * 1024 * 1024))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--container", required=True)
    ap.add_argument("--data-dir", required=True)
    ap.add_argument("--meta-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n-objects", type=int, default=200)
    ap.add_argument("--object-mib", type=int, default=1)
    ap.add_argument("--n-control-objects", type=int, default=10)
    args = ap.parse_args()

    client = boto3.client(
        "s3", endpoint_url=args.endpoint, aws_access_key_id=args.access_key, aws_secret_access_key=args.secret_key,
        config=Config(s3={"addressing_style": "path"}), region_name="garage",
    )

    result = {}

    # --- Fail-first: prove the du probe can register a DROP, not just a nonzero value. ---
    print(f"FAIL-FIRST CONTROL: PUT {args.n_control_objects}x{args.object_mib}MiB distinct objects, "
          f"delete them, and confirm du drops before trusting any real result.", flush=True)
    put_distinct(client, args.bucket, "control-me/", args.n_control_objects, args.object_mib)
    result["control_before_delete"] = snapshot(
        client, args.bucket, args.container, args.data_dir, "control_before_delete", prefix="control-me/")
    keys = [{"Key": o["Key"]} for o in client.list_objects_v2(Bucket=args.bucket, Prefix="control-me/").get("Contents", [])]
    client.delete_objects(Bucket=args.bucket, Delete={"Objects": keys})
    control_dropped, control_final_du = poll_for_drop(
        args.data_dir, result["control_before_delete"]["du_bytes"], MIN_WAIT_S)
    result["control_dropped"] = control_dropped
    result["control_final_du"] = control_final_du
    print(f"FAIL-FIRST CONTROL result: du {'DROPPED' if control_dropped else 'DID NOT DROP'} "
          f"within {MIN_WAIT_S}s of DeleteObject -> {'DETECTOR-OK' if control_dropped else 'DETECTOR-BROKEN'}", flush=True)
    if not control_dropped:
        # By this harness's own governing rule, a fail-first that cannot fail makes every
        # downstream result void, not negative. Stop here rather than reporting NOT-RECLAIMED.
        result["verdict"] = "VOID"
        result["failfirst_ok"] = False
        print("SUMMARY test=h4-lifecycle-expiration verdict=VOID reason=du-probe-cannot-register-a-drop")
        with open(args.out, "w") as f:
            json.dump(result, f, indent=2)
        sys.exit(1)
    result["failfirst_ok"] = True

    # --- Real test: a distinct body per object. Garage is content-addressed, so a single
    # body reused across N PUTs deduplicates to one block and makes `du` measure the wrong
    # thing -- this is exactly what invalidated the original run of this test. ---
    print(f"PUTting {args.n_objects} x {args.object_mib}MiB DISTINCT objects...", flush=True)
    put_distinct(client, args.bucket, "expire-me/", args.n_objects, args.object_mib)

    result["before_rule"] = snapshot(
        client, args.bucket, args.container, args.data_dir, "before_rule", prefix="expire-me/")

    yesterday = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).strftime("%Y-%m-%dT00:00:00.000Z")
    client.put_bucket_lifecycle_configuration(
        Bucket=args.bucket,
        LifecycleConfiguration={
            "Rules": [{
                "ID": "expire-me-yesterday",
                "Status": "Enabled",
                "Filter": {"Prefix": "expire-me/"},
                "Expiration": {"Date": yesterday},
            }],
        },
    )
    print(f"lifecycle rule applied: Expiration.Date={yesterday}", flush=True)

    # A plain `docker restart` does NOT re-trigger the worker on a second same-day restart --
    # Garage persists a per-day `last_completed` marker in <meta>/lifecycle_worker_state.
    # Clearing that file before restart forces a fresh run.
    print("stopping garage, clearing lifecycle_worker_state, restarting...", flush=True)
    sh(["docker", "stop", args.container], check=True)
    sh(["sudo", "rm", "-f", os.path.join(args.meta_dir, "lifecycle_worker_state")])
    sh(["docker", "start", args.container], check=True)
    for _ in range(30):
        if sh(["docker", "exec", args.container, "/garage", "status"]).returncode == 0:
            break
        time.sleep(1)
    time.sleep(15)  # let the startup lifecycle-worker pass finish expiring the objects

    result["after_worker"] = snapshot(
        client, args.bucket, args.container, args.data_dir, "after_worker", prefix="expire-me/")

    # `repair --yes blocks` cannot shorten BLOCK_GC_DELAY (see module docstring) -- run it
    # anyway so this matches the brief's falsifier, but poll for the real floor regardless.
    sh(["docker", "exec", args.container, "/garage", "repair", "--yes", "blocks"])
    dropped, final_du = poll_for_drop(args.data_dir, result["before_rule"]["du_bytes"], MIN_WAIT_S)
    result["reclaimed_within_wait"] = dropped
    result["final_du_bytes"] = final_du
    result["after_repair_blocks"] = snapshot(
        client, args.bucket, args.container, args.data_dir, "after_repair_blocks", prefix="expire-me/")

    result["verdict"] = "RECLAIMED" if dropped else "NOT-RECLAIMED"
    print(f"SUMMARY test=h4-lifecycle-expiration verdict={result['verdict']} wait_floor_s={MIN_WAIT_S}")

    with open(args.out, "w") as f:
        json.dump(result, f, indent=2)


if __name__ == "__main__":
    main()
