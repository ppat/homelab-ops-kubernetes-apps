#!/usr/bin/env python3
"""H4-B: adjudication retest for the H4 'du never dropped' finding.

Fixes three defects in the original H4:
  1. Original PUT 200 copies of ONE random body -> Garage is content-addressed, so all 200
     objects deduplicated to a SINGLE 1 MiB block. du was 1,048,677 B for 200 MiB of PUTs.
     Here every object gets its own os.urandom body, so du must track bytes written.
  2. Original had NO positive control: the "fail-first" only checked du > 0 before the rule,
     which is true by construction and proves nothing about whether the du probe can ever
     register a DROP. Here arm A deletes objects with plain DeleteObject and watches du.
  3. Original waited ~3.5 min. Garage v2.3.0 hardcodes BLOCK_GC_DELAY = 600 s and schedules
     the deleting resync at now + 610 s (src/block/manager.rs:44, :490). Here we poll to 20 min.

Arms, run sequentially so each du movement is unambiguously attributable:
  A (control)   : N objects under del-me/, removed by explicit S3 DeleteObject.
                  A1 negative control: du at +30 s MUST be unchanged (reproduces the original
                                       H4 reading, i.e. within-GC-delay looks identical to
                                       'never reclaims').
                  A2 positive control: du MUST drop by ~N MiB by +20 min. If it does not, the
                                       du probe or Garage itself is broken and arm B is void.
  B (treatment) : N objects under expire-me/, removed by an S3 Expiration lifecycle rule dated
                  yesterday, worker forced by clearing lifecycle_worker_state + restart.
                  Same poll. This is the actual H4 claim.
"""
import argparse, datetime, json, os, subprocess, sys, time

import boto3
from botocore.config import Config

MIB = 1024 * 1024


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def du_bytes(path):
    return int(sh(["sudo", "du", "-sb", path], check=True).stdout.split()[0])


def obj_count(container, bucket):
    out = sh(["docker", "exec", container, "/garage", "bucket", "info", bucket], check=True).stdout
    for line in out.splitlines():
        if line.strip().startswith("Objects:"):
            return int(line.split(":")[1].strip())
    return None


def snap(client, bucket, container, data_dir, label, t0):
    s = {"label": label, "t_rel_s": round(time.time() - t0, 1),
         "list_key_count": client.list_objects_v2(Bucket=bucket).get("KeyCount", 0),
         "bucket_object_count": obj_count(container, bucket),
         "du_bytes": du_bytes(data_dir)}
    print(f"SNAPSHOT[{label}] t+{s['t_rel_s']}s list={s['list_key_count']} "
          f"objects={s['bucket_object_count']} du={s['du_bytes']} ({s['du_bytes']/MIB:.1f} MiB)", flush=True)
    return s


def poll_until_drop(client, bucket, container, data_dir, baseline, label, t0, max_s, interval=30):
    """Poll du until it drops materially below baseline (>25%) or max_s elapses."""
    series = []
    deadline = time.time() + max_s
    while True:
        s = snap(client, bucket, container, data_dir, f"{label}-poll", t0)
        series.append({"t_rel_s": s["t_rel_s"], "du_bytes": s["du_bytes"]})
        if s["du_bytes"] < baseline * 0.75:
            return series, True
        if time.time() >= deadline:
            return series, False
        time.sleep(interval)


def put_distinct(client, bucket, prefix, n, mib):
    for i in range(n):
        client.put_object(Bucket=bucket, Key=f"{prefix}{i:05d}", Body=os.urandom(mib * MIB))


def main():
    ap = argparse.ArgumentParser()
    for a in ("endpoint", "access-key", "secret-key", "bucket", "container", "data-dir", "meta-dir", "out"):
        ap.add_argument(f"--{a}", required=True)
    ap.add_argument("--n-objects", type=int, default=50)
    ap.add_argument("--object-mib", type=int, default=1)
    ap.add_argument("--max-wait-s", type=int, default=1200)
    args = ap.parse_args()

    client = boto3.client("s3", endpoint_url=args.endpoint, aws_access_key_id=args.access_key,
                          aws_secret_access_key=args.secret_key,
                          config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 3}),
                          region_name="garage")
    t0 = time.time()
    R = {"config": {"n_objects": args.n_objects, "object_mib": args.object_mib,
                    "max_wait_s": args.max_wait_s, "garage_image": "dxflrs/garage:v2.3.0"},
         "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat()}

    expect = args.n_objects * args.object_mib * MIB

    # ---------------- ARM A : explicit DeleteObject ----------------
    print("=== ARM A (control): PUT distinct objects under del-me/ ===", flush=True)
    R["A_empty"] = snap(client, args.bucket, args.container, args.data_dir, "A-empty", t0)
    put_distinct(client, args.bucket, "del-me/", args.n_objects, args.object_mib)
    R["A_after_put"] = snap(client, args.bucket, args.container, args.data_dir, "A-after-put", t0)

    # Dedup guard: du must reflect the bytes actually written. If it does not, the probe is
    # measuring the wrong thing (this is exactly what invalidated the original H4).
    grew = R["A_after_put"]["du_bytes"] - R["A_empty"]["du_bytes"]
    R["dedup_guard_ok"] = grew > expect * 0.8
    print(f"DEDUP-GUARD: du grew {grew} B for {expect} B written -> "
          f"{'OK' if R['dedup_guard_ok'] else 'BROKEN (du is not tracking written bytes)'}", flush=True)

    print("=== ARM A: DeleteObject on all del-me/ keys ===", flush=True)
    keys = []
    p = client.get_paginator("list_objects_v2")
    for page in p.paginate(Bucket=args.bucket, Prefix="del-me/"):
        keys += [{"Key": o["Key"]} for o in page.get("Contents", [])]
    for i in range(0, len(keys), 100):
        client.delete_objects(Bucket=args.bucket, Delete={"Objects": keys[i:i + 100]})
    t_del = time.time()
    R["A_delete_issued_t_rel_s"] = round(t_del - t0, 1)

    time.sleep(30)
    # A1 NEGATIVE CONTROL: within the GC delay, du must still be unchanged. This reproduces
    # the original H4's reading and proves the two worlds are indistinguishable at 30 s.
    R["A_t30"] = snap(client, args.bucket, args.container, args.data_dir, "A-t+30s", t0)
    R["A1_negative_control_ok"] = R["A_t30"]["du_bytes"] >= R["A_after_put"]["du_bytes"] * 0.95 \
        and R["A_t30"]["list_key_count"] == 0
    print(f"A1 NEGATIVE CONTROL (index dropped, du has NOT yet): "
          f"{'OK' if R['A1_negative_control_ok'] else 'UNEXPECTED'}", flush=True)

    # The brief's falsifier included one `garage repair blocks` pass; run it so this retest
    # covers the same ground, and record that it changes nothing either way.
    rb = sh(["docker", "exec", args.container, "/garage", "repair", "--yes", "blocks"])
    R["A_repair_blocks_rc"] = rb.returncode
    R["A_after_repair"] = snap(client, args.bucket, args.container, args.data_dir, "A-after-repair", t0)

    print("=== ARM A: polling du for the block GC delay (expect drop ~610 s after delete) ===", flush=True)
    series, dropped = poll_until_drop(client, args.bucket, args.container, args.data_dir,
                                      R["A_after_put"]["du_bytes"], "A", t0,
                                      args.max_wait_s - (time.time() - t_del))
    R["A_poll"] = series
    R["A_dropped"] = dropped
    R["A_drop_latency_s"] = round(series[-1]["t_rel_s"] - R["A_delete_issued_t_rel_s"], 1) if dropped else None
    R["A_final"] = snap(client, args.bucket, args.container, args.data_dir, "A-final", t0)
    print(f"ARM A (positive control) verdict: {'RECLAIMED' if dropped else 'NOT-RECLAIMED'} "
          f"latency={R['A_drop_latency_s']}s", flush=True)

    # ---------------- ARM B : lifecycle Expiration ----------------
    print("=== ARM B (treatment): PUT distinct objects under expire-me/ ===", flush=True)
    put_distinct(client, args.bucket, "expire-me/", args.n_objects, args.object_mib)
    R["B_after_put"] = snap(client, args.bucket, args.container, args.data_dir, "B-after-put", t0)

    yesterday = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)) \
        .strftime("%Y-%m-%dT00:00:00.000Z")
    client.put_bucket_lifecycle_configuration(
        Bucket=args.bucket,
        LifecycleConfiguration={"Rules": [{"ID": "expire-me-yesterday", "Status": "Enabled",
                                           "Filter": {"Prefix": "expire-me/"},
                                           "Expiration": {"Date": yesterday}}]})
    R["B_rule_date"] = yesterday
    print(f"lifecycle rule applied: Expiration.Date={yesterday}", flush=True)

    sh(["docker", "stop", args.container], check=True)
    sh(["sudo", "rm", "-f", os.path.join(args.meta_dir, "lifecycle_worker_state")])
    log_mark = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    sh(["docker", "start", args.container], check=True)
    for _ in range(60):
        if sh(["docker", "exec", args.container, "/garage", "status"]).returncode == 0:
            break
        time.sleep(1)
    time.sleep(15)
    t_exp = time.time()
    R["B_expire_t_rel_s"] = round(t_exp - t0, 1)

    # Assertion 4 from the adjudication brief: prove the worker actually ran.
    logs = sh(["docker", "logs", "--since", log_mark, args.container]).stdout + \
        sh(["docker", "logs", "--since", log_mark, args.container]).stderr
    R["B_worker_loglines"] = [l for l in logs.splitlines()
                              if "ifecycle" in l or "xpir" in l][:40]
    R["B_worker_ran"] = bool(R["B_worker_loglines"])
    R["B_worker_last_completed"] = sh(["docker", "exec", args.container, "/garage", "worker",
                                       "get", "lifecycle-last-completed"]).stdout.strip()
    print(f"B lifecycle worker ran: {R['B_worker_ran']} "
          f"(lifecycle-last-completed={R['B_worker_last_completed']!r})", flush=True)
    for l in R["B_worker_loglines"][:10]:
        print("  LOG| " + l, flush=True)

    R["B_after_worker"] = snap(client, args.bucket, args.container, args.data_dir, "B-after-worker", t0)
    rb = sh(["docker", "exec", args.container, "/garage", "repair", "--yes", "blocks"])
    R["B_repair_blocks_rc"] = rb.returncode
    time.sleep(60)
    R["B_after_repair"] = snap(client, args.bucket, args.container, args.data_dir, "B-after-repair", t0)
    # This is the original H4's exact stopping point. Record its verdict verbatim.
    R["B_original_h4_window_verdict"] = (
        "RECLAIMED" if R["B_after_repair"]["du_bytes"] < R["B_after_put"]["du_bytes"] * 0.75
        else "NOT-RECLAIMED")
    print(f"B verdict AT THE ORIGINAL H4 STOPPING POINT (worker + repair blocks + 60 s): "
          f"{R['B_original_h4_window_verdict']}", flush=True)

    print("=== ARM B: polling du past the block GC delay ===", flush=True)
    series, dropped = poll_until_drop(client, args.bucket, args.container, args.data_dir,
                                      R["B_after_put"]["du_bytes"], "B", t0,
                                      args.max_wait_s - (time.time() - t_exp))
    R["B_poll"] = series
    R["B_dropped"] = dropped
    R["B_drop_latency_s"] = round(series[-1]["t_rel_s"] - R["B_expire_t_rel_s"], 1) if dropped else None
    R["B_final"] = snap(client, args.bucket, args.container, args.data_dir, "B-final", t0)
    R["B_stats_tail"] = sh(["docker", "exec", args.container, "/garage", "stats"]).stdout[-2500:]

    R["verdict"] = ("RECLAIMED" if (R["A_dropped"] and R["B_dropped"]) else
                    "CONTROL-FAILED-RESULT-VOID" if not R["A_dropped"] else "NOT-RECLAIMED")
    print(f"SUMMARY test=h4b-lifecycle-expiration-retest verdict={R['verdict']} "
          f"control_arm={'RECLAIMED' if R['A_dropped'] else 'NOT-RECLAIMED'} "
          f"treatment_arm={'RECLAIMED' if R['B_dropped'] else 'NOT-RECLAIMED'} "
          f"original_window_verdict={R['B_original_h4_window_verdict']}", flush=True)
    with open(args.out, "w") as f:
        json.dump(R, f, indent=2)


if __name__ == "__main__":
    main()
