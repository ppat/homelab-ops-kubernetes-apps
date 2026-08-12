#!/usr/bin/env python3
"""H4 body: PUT real objects, measure the three assertions BEFORE the rule is even applied
(fail-first -- all three must report NOT-RECLAIMED), apply an Expiration rule dated
yesterday, restart Garage (triggers its startup lifecycle-worker run), then measure all
three again. If `du` hasn't dropped, run `garage repair --yes blocks` once (the brief's
falsifier: "du does not drop within one worker cycle plus one repair blocks pass") and
measure a third time.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys

import boto3
from botocore.config import Config


def du_bytes(path):
    out = subprocess.run(["sudo", "du", "-sb", path], capture_output=True, text=True, check=True).stdout
    return int(out.split()[0])


def object_count(container, bucket):
    out = subprocess.run(["docker", "exec", container, "/garage", "bucket", "info", bucket],
                          capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        if line.strip().startswith("Objects:"):
            return int(line.split(":")[1].strip())
    return None


def list_count(client, bucket):
    resp = client.list_objects_v2(Bucket=bucket)
    return resp.get("KeyCount", 0)


def snapshot(client, bucket, container, data_dir, label):
    s = {
        "label": label,
        "list_key_count": list_count(client, bucket),
        "bucket_object_count": object_count(container, bucket),
        "du_bytes": du_bytes(data_dir),
    }
    print(f"SNAPSHOT[{label}]: list={s['list_key_count']} bucket_objects={s['bucket_object_count']} du_bytes={s['du_bytes']}", flush=True)
    return s


def reclaimed(before, after):
    return after["list_key_count"] < before["list_key_count"] and (after["bucket_object_count"] or 0) < (before["bucket_object_count"] or 0) and after["du_bytes"] < before["du_bytes"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--container", required=True)
    ap.add_argument("--data-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n-objects", type=int, default=200)
    ap.add_argument("--object-mib", type=int, default=1)
    args = ap.parse_args()

    client = boto3.client(
        "s3", endpoint_url=args.endpoint, aws_access_key_id=args.access_key, aws_secret_access_key=args.secret_key,
        config=Config(s3={"addressing_style": "path"}), region_name="garage",
    )

    print(f"PUTting {args.n_objects} x {args.object_mib}MiB objects...", flush=True)
    body = os.urandom(args.object_mib * 1024 * 1024)
    for i in range(args.n_objects):
        client.put_object(Bucket=args.bucket, Key=f"expire-me/{i:05d}", Body=body)

    result = {}
    result["before_rule"] = snapshot(client, args.bucket, args.container, args.data_dir, "before_rule")
    before_not_reclaimed = (
        result["before_rule"]["list_key_count"] > 0
        and (result["before_rule"]["bucket_object_count"] or 0) > 0
        and result["before_rule"]["du_bytes"] > 0
    )
    result["failfirst_ok"] = before_not_reclaimed
    print(f"FAIL-FIRST (pre-rule, must be NOT-RECLAIMED on all 3): {'OK' if before_not_reclaimed else 'DETECTOR-BROKEN'}", flush=True)

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

    # DEVIATION, RECORD OF WHY (see run.sh's header for the fuller version): a plain
    # `docker restart` was tried FIRST and did NOT re-trigger the worker -- Garage persists
    # a per-day "already ran today" marker in <meta>/lifecycle_worker_state and skips
    # re-running on a same-day restart. Deleting that file before restart forces it to
    # re-evaluate, confirmed against this exact container: the very next start logged
    # "Lifecycle: expiring 1 object in bucket ..." x200 and "objects expired: 200".
    print("stopping garage, clearing lifecycle_worker_state (see script comment), restarting...", flush=True)
    subprocess.run(["docker", "stop", args.container], check=True, capture_output=True)
    subprocess.run(["sudo", "rm", "-f", os.path.join(os.path.dirname(args.data_dir.rstrip("/")), "meta", "lifecycle_worker_state")], capture_output=True)
    subprocess.run(["docker", "start", args.container], check=True, capture_output=True)
    import time
    for _ in range(30):
        r = subprocess.run(["docker", "exec", args.container, "/garage", "status"], capture_output=True)
        if r.returncode == 0:
            break
        time.sleep(1)
    time.sleep(5)  # let the startup lifecycle-worker pass (and its block deletions) finish

    result["after_worker"] = snapshot(client, args.bucket, args.container, args.data_dir, "after_worker")

    if not reclaimed(result["before_rule"], result["after_worker"]):
        print("du/list/count did not all drop after one worker cycle -- running `garage repair --yes blocks` once, per the brief's falsifier", flush=True)
        subprocess.run(["docker", "exec", args.container, "/garage", "repair", "--yes", "blocks"], capture_output=True)
        time.sleep(60)  # generous: manual investigation during harness development waited 2.5+
        # minutes past this point with `garage stats` still showing GcTodo=200 on object/
        # version/block_ref and zero change in `du` -- this isn't "just needs a bit longer".
        result["after_repair_blocks"] = snapshot(client, args.bucket, args.container, args.data_dir, "after_repair_blocks")
        final = result["after_repair_blocks"]
    else:
        final = result["after_worker"]

    result["reclaimed"] = reclaimed(result["before_rule"], final)
    result["verdict"] = "RECLAIMED" if result["reclaimed"] else "NOT-RECLAIMED"
    print(f"SUMMARY test=h4-lifecycle-expiration verdict={result['verdict']}")

    with open(args.out, "w") as f:
        json.dump(result, f, indent=2)


if __name__ == "__main__":
    main()
