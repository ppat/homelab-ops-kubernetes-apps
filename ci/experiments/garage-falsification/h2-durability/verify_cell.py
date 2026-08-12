#!/usr/bin/env python3
"""H2 per-cell per-iteration verdict. Implements the four assertions from the H2 brief and
the three-way classification the brief's wording implies (it explicitly says "corruption is
(a) or (d)" and calls out (c)-only failure as the DISTINCT, expected-under-fsync=false
"loss of un-acknowledged writes" case -- except (c) here is about ACKNOWLEDGED writes, so a
(c) failure with (a)/(b)/(d) clean is real but is a different failure mode than corruption
and must not be reported as if it were the same thing):

  (a) the process starts                         -> failure here = CORRUPT
  (b) `garage repair --yes tables` reports no errors -> failure here = CORRUPT (the industry
      meaning of "repair found errors" on a DB engine IS corruption; the brief's opening
      paragraph frames this whole test around Garage's own "corrupted LMDB database files"
      language, which is exactly what a failing repair would mean)
  (c) every acknowledged PUT (per the host-side fsynced manifest -- see cell_iteration.py) is
      readable -> failure here alone (a,b,d clean) = DATA-LOSS, not CORRUPT: the engine is
      healthy but silently dropped writes it had 200'd, which is exactly what
      metadata_fsync=false predicts and is a materially different finding from file-level
      corruption
  (d) no object returns wrong bytes -> failure here = CORRUPT (silent integrity violation)

Verdict precedence: CORRUPT > DATA-LOSS > CLEAN.

Also runnable as the fail-first detector (--expect-corrupt): asserts the verdict IS CORRUPT
and exits non-zero if it is not, so a fail-first run that reports CLEAN or DATA-LOSS is loud
about the detector being broken rather than silently passing.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time

_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
# garage's tracing output is "<ts>Z  <LEVEL> <module>: message" once ANSI color codes
# (used to highlight the level -- green for INFO, presumably red/yellow for ERROR/WARN) are
# stripped. Matching the LEVEL FIELD specifically (not a substring search across the whole
# line) matters: an early version of this matched the bare word "error" anywhere in the line
# and false-positived on garage's own benign shutdown message "S3 API server exited without
# error." -- which would have silently mislabeled every clean iteration as CORRUPT.
_LEVEL_RE = re.compile(r"^\S+\s+(ERROR|PANIC)\b")

import boto3
from botocore.config import Config


def sh(cmd, timeout=30, check=False):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=check)


def assertion_a_process_starts(container, s3_port, timeout_s):
    sh(["docker", "start", container])  # idempotent
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        state = sh(["docker", "inspect", "-f", "{{.State.Status}}", container]).stdout.strip()
        if state == "running":
            try:
                r = sh(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "1", f"http://127.0.0.1:{s3_port}"])
                if r.stdout.strip():
                    return True, f"container running, S3 port responsive (http {r.stdout.strip()})"
            except Exception:  # noqa: BLE001
                pass
        elif state in ("exited", "dead"):
            code = sh(["docker", "inspect", "-f", "{{.State.ExitCode}}", container]).stdout.strip()
            return False, f"container state={state} exit_code={code}"
        time.sleep(1)
    return False, f"S3 port never became responsive within {timeout_s}s (container state={state})"


def assertion_b_repair_clean(container, wait_s):
    r = sh(["docker", "exec", container, "/garage", "repair", "--yes", "tables"], timeout=30)
    if r.returncode != 0:
        return False, f"`garage repair --yes tables` exited {r.returncode}: {r.stderr.strip()[:300]}"
    time.sleep(wait_s)
    logs = sh(["docker", "logs", "--since", f"{wait_s + 2}s", container], timeout=15).stderr
    bad_lines = []
    for raw in logs.splitlines():
        line = _ANSI_RE.sub("", raw)
        if _LEVEL_RE.match(line) or "panicked at" in line:
            bad_lines.append(line)
    if bad_lines:
        return False, f"repair launched but logs show {len(bad_lines)} ERROR/PANIC line(s), e.g.: {bad_lines[0][:300]}"
    return True, "repair launched cleanly, no ERROR/PANIC level log lines since"


def assertions_cd_manifest(endpoint, access_key, secret_key, bucket, manifest_path):
    client = boto3.client(
        "s3", endpoint_url=endpoint, aws_access_key_id=access_key, aws_secret_access_key=secret_key,
        config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 2}), region_name="garage",
    )
    missing, wrong_bytes, ok = [], [], []
    try:
        entries = [json.loads(line) for line in open(manifest_path) if line.strip()]
    except FileNotFoundError:
        entries = []
    for entry in entries:
        try:
            body = client.get_object(Bucket=bucket, Key=entry["key"])["Body"].read()
        except Exception as e:  # noqa: BLE001
            missing.append({"key": entry["key"], "reason": str(e)[:200]})
            continue
        digest = hashlib.sha256(body).hexdigest()
        if digest != entry["sha256"] or len(body) != entry["size"]:
            wrong_bytes.append({"key": entry["key"], "expected_sha256": entry["sha256"], "got_sha256": digest, "expected_size": entry["size"], "got_size": len(body)})
        else:
            ok.append(entry["key"])
    return {"total_acknowledged": len(entries), "ok": len(ok), "missing": missing, "wrong_bytes": wrong_bytes}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--container", required=True)
    ap.add_argument("--s3-port", required=True, type=int)
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--cell-name", required=True)
    ap.add_argument("--iteration", required=True)
    ap.add_argument("--mechanic", required=True, choices=["failfirst", "kill9", "hardreset"])
    ap.add_argument("--start-timeout-s", type=float, default=30.0)
    ap.add_argument("--repair-wait-s", type=float, default=5.0)
    ap.add_argument("--expect-corrupt", action="store_true", help="fail-first mode: exit non-zero unless verdict is CORRUPT")
    args = ap.parse_args()

    a_ok, a_detail = assertion_a_process_starts(args.container, args.s3_port, args.start_timeout_s)
    b_ok, b_detail = (False, "skipped: process did not start") if not a_ok else assertion_b_repair_clean(args.container, args.repair_wait_s)
    if a_ok:
        cd = assertions_cd_manifest(args.endpoint, args.access_key, args.secret_key, args.bucket, args.manifest)
    else:
        cd = {"total_acknowledged": 0, "ok": 0, "missing": [], "wrong_bytes": []}
    c_ok = len(cd["missing"]) == 0
    d_ok = len(cd["wrong_bytes"]) == 0

    if not a_ok or not b_ok or not d_ok:
        verdict = "CORRUPT"
    elif not c_ok:
        verdict = "DATA-LOSS"
    else:
        verdict = "CLEAN"

    record = {
        "cell": args.cell_name, "iteration": args.iteration, "mechanic": args.mechanic,
        "verdict": verdict,
        "a_process_starts": {"ok": a_ok, "detail": a_detail},
        "b_repair_clean": {"ok": b_ok, "detail": b_detail},
        "c_acknowledged_readable": {"ok": c_ok, "missing_count": len(cd["missing"]), "missing": cd["missing"][:5]},
        "d_correct_bytes": {"ok": d_ok, "wrong_count": len(cd["wrong_bytes"]), "wrong_bytes": cd["wrong_bytes"][:5]},
        "total_acknowledged_checked": cd["total_acknowledged"],
    }
    print(json.dumps(record))

    if args.expect_corrupt:
        if verdict != "CORRUPT":
            print(f"DETECTOR-BROKEN: fail-first expected CORRUPT, got {verdict}. Every result from this cell's detector is VOID until this is fixed.", file=sys.stderr)
            sys.exit(1)
        print("DETECTOR-OK: fail-first correctly reported CORRUPT.", file=sys.stderr)
        sys.exit(0)

    sys.exit(0 if verdict == "CLEAN" else 0)  # non-failfirst runs always exit 0 -- the verdict is data, not a shell failure


if __name__ == "__main__":
    main()
