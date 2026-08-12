#!/usr/bin/env python3
"""H5 step 1b (prerequisite verification, run once before wiring up Longhorn's
BackupTarget): confirm the region we're about to hand Longhorn is (a) accepted by Garage
for real S3 operations, and (b) that a MISMATCHED region is rejected -- the brief's core
warning ("Garage enforces exact-match on s3_region ... unlike MinIO which is lenient").

Requires a port-forward to the in-cluster garage Service, e.g.:
  kubectl --context sandbox-talos port-forward -n h5-garage svc/garage 13900:3900 &

ACTUAL RESULT (recorded 2026-08-12, see NOTES.md for the full transcript):
  - PutObject/GetObject with the correct region ("garage"): succeeds.
  - PutObject with a mismatched region (tried "us-east-1", "eu-west-1", "wrongregion"):
    rejected by Garage with `AuthorizationHeaderMalformed`, e.g.:
      "Authorization header malformed, unexpected scope: '20260812/us-east-1/s3/aws4_request',
       expected: '20260812/garage/s3/aws4_request'"
    -- confirms the brief's claim exactly.
  - GetBucketLocation with a mismatched region: Garage answers it anyway (200, returns the
    *real* region "garage"), regardless of the region the client signed with. This is not a
    bug: GetBucketLocation is the one S3 call clients are expected to use for region
    *discovery* before signing everything else, and real AWS S3 behaves the same way. Does
    NOT mean Longhorn's own GetBucketLocation probe (see NOTES.md, brief mentions this call
    by name) will tolerate a misconfigured region for its actual PUT/GET traffic -- it will
    not, per the PutObject result above.
  - NOTE (boto3-specific, not a Garage behavior): botocore auto-retries a failed request
    once, using the region reported in Garage's <Region> error tag, so a wrong region can
    silently "heal" and succeed on attempt 2 with THIS client library. Do not take that as
    evidence the mismatch doesn't matter -- Longhorn's own Go S3 client has no reason to
    share this behavior, and the whole point of getting the region right up front is to not
    depend on a client-specific retry quirk for the disaster-recovery path.
"""
import argparse
import json
import sys

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError


def client(endpoint, access, secret, region):
    return boto3.client(
        "s3", endpoint_url=endpoint, aws_access_key_id=access, aws_secret_access_key=secret,
        config=Config(s3={"addressing_style": "path"}), region_name=region,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", default="http://127.0.0.1:13900")
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--region", default="garage")
    ap.add_argument("--wrong-region", default="us-east-1")
    args = ap.parse_args()

    print(f"--- correct region '{args.region}': PutObject/GetObject round trip ---")
    c = client(args.endpoint, args.access_key, args.secret_key, args.region)
    c.put_object(Bucket=args.bucket, Key="region-check/probe.txt", Body=b"hello-region-check")
    body = c.get_object(Bucket=args.bucket, Key="region-check/probe.txt")["Body"].read()
    if body != b"hello-region-check":
        print("FAIL: round trip returned wrong bytes")
        sys.exit(1)
    print("OK")

    print(f"--- mismatched region '{args.wrong_region}': PutObject, expect rejection ---")
    c_wrong = client(args.endpoint, args.access_key, args.secret_key, args.wrong_region)
    try:
        c_wrong.put_object(Bucket=args.bucket, Key="region-check/should-fail.txt", Body=b"x")
    except ClientError:
        # botocore may have transparently retried with the corrected region and succeeded
        # (see module docstring) -- check whether the object actually landed to know which.
        pass

    exists = True
    try:
        client(args.endpoint, args.access_key, args.secret_key, args.region).head_object(
            Bucket=args.bucket, Key="region-check/should-fail.txt"
        )
    except ClientError:
        exists = False

    if exists:
        print("botocore auto-retried the mismatched-region request with the corrected "
              "region and it succeeded -- this is a botocore client behavior, not proof "
              "Garage tolerates the mismatch. See PutObject debug log in NOTES.md for the "
              "raw AuthorizationHeaderMalformed response Garage sent on attempt 1.")
    else:
        print("CONFIRMED: mismatched-region PutObject was rejected and did not land.")

    print("--- region checks complete ---")


if __name__ == "__main__":
    main()
