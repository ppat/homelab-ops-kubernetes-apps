#!/usr/bin/env python3
"""H3-B: adjudication probe for the H3 'Garage is worse than MinIO on db// prefixes' finding.

The original H3 repro seeded keys under `db/base/...` (SINGLE slash) and then listed with
Prefix="db//" (DOUBLE slash). In S3, keys are opaque byte strings with no path normalisation,
so `db//base/x` and `db/base/x` are different keys and a `db//` prefix genuinely matches
nothing. That probe therefore asked "what happens when I list a prefix no object has?" -- for
which HTTP 200 + empty list is the correct S3 answer, not a defect.

The REAL barman scenario is different and is what this probe tests: a trailing slash in
destinationPath makes barman-cloud both WRITE and LIST with the doubled separator. So the
question that actually decides whether retention pruning breaks is:

  If the objects are written with `//` in the key, does listing with the `//` prefix find them?

Cases per backend:
  1. write `db//base/*` (doubled, as barman would)      -> does the PUT succeed?
  2. list Prefix="db//"                                  -> are the doubled-slash keys found?
  3. list Prefix="db/"                                   -> does it also find them (prefix is a
                                                            substring, so it should)?
  4. write `db/base/*` (single) then list Prefix="db//"  -> the ORIGINAL H3 probe, for parity
  5. delete the doubled keys found in (2)                -> the outcome assertion the brief
                                                            demanded: can retention actually
                                                            prune what it listed?
"""
import argparse, json, sys

import boto3
from botocore.config import Config

DOUBLE = ["db//base/000000010000000000000001", "db//base/000000010000000000000002",
          "db//wals/00000001.history"]
SINGLE = ["db/base/000000010000000000000001", "db/base/000000010000000000000002",
          "db/wals/00000001.history"]


def attempt(fn):
    try:
        return {"outcome": "ok", "value": fn()}
    except Exception as e:  # noqa: BLE001
        return {"outcome": "exception", "type": type(e).__name__, "detail": str(e)[:250]}


def lst(client, bucket, prefix):
    def go():
        r = client.list_objects_v2(Bucket=bucket, Prefix=prefix)
        return {"key_count": r.get("KeyCount"), "keys": sorted(o["Key"] for o in r.get("Contents", []))}
    return attempt(go)


def main():
    ap = argparse.ArgumentParser()
    for a in ("endpoint", "access-key", "secret-key", "bucket", "label"):
        ap.add_argument(f"--{a}", required=True)
    ap.add_argument("--region", default="us-east-1")
    args = ap.parse_args()

    c = boto3.client("s3", endpoint_url=args.endpoint, aws_access_key_id=args.access_key,
                     aws_secret_access_key=args.secret_key,
                     config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 2}),
                     region_name=args.region)
    R = {"label": args.label}

    # 1. write the doubled-slash keys barman would actually create
    R["put_double"] = [attempt(lambda k=k: bool(c.put_object(Bucket=args.bucket, Key=k, Body=b"x"))) for k in DOUBLE]
    R["put_double_all_ok"] = all(p["outcome"] == "ok" for p in R["put_double"])

    # 2/3. can retention find them?
    R["list_double_prefix"] = lst(c, args.bucket, "db//")
    R["list_single_prefix"] = lst(c, args.bucket, "db/")

    # 5. outcome assertion: can it actually delete what it listed?
    found = R["list_double_prefix"].get("value", {}).get("keys", []) if R["list_double_prefix"]["outcome"] == "ok" else []
    R["delete_found"] = attempt(lambda: c.delete_objects(
        Bucket=args.bucket, Delete={"Objects": [{"Key": k} for k in found]})) if found else {"outcome": "skipped-nothing-listed"}
    R["list_double_after_delete"] = lst(c, args.bucket, "db//")

    # 4. the ORIGINAL H3 pairing: single-slash keys, double-slash prefix
    R["put_single"] = [attempt(lambda k=k: bool(c.put_object(Bucket=args.bucket, Key=k, Body=b"x"))) for k in SINGLE]
    R["original_h3_probe"] = lst(c, args.bucket, "db//")

    # classify
    if not R["put_double_all_ok"]:
        v = "WRITE-REJECTED (backend refuses doubled-slash keys outright)"
    elif R["list_double_prefix"]["outcome"] == "exception":
        v = "LIST-ERRORS (backend wrote the keys but cannot list them -- retention hard-fails, loudly)"
    elif len(found) == len(DOUBLE) and R["list_double_after_delete"].get("value", {}).get("key_count") == 0:
        v = "SELF-CONSISTENT (writes and lists doubled keys, and retention can prune them)"
    else:
        v = "SILENT-NO-OP (wrote the keys but listing them returns nothing -- retention silently prunes nothing)"
    R["verdict"] = v
    print(json.dumps(R, indent=2))
    print(f"SUMMARY test=h3b-doubleslash label={args.label} verdict={v}", file=sys.stderr)


if __name__ == "__main__":
    main()
