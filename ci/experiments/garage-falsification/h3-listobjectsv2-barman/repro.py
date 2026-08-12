#!/usr/bin/env python3
"""H3: reproduce the documented ListObjectsV2(Prefix="db//") failure against MinIO first
(the brief requires this -- a test that only ever runs green against Garage cannot
demonstrate it is capable of detecting the bug at all), then run the identical call against
Garage and classify the outcome.

This is the S3 client-library-level probe, not the CloudNativePG+barman-cloud-plugin
end-to-end assertion (that's h3-listobjectsv2-barman/cnpg-cluster.yaml + verify_retention.sh)
-- it exists to isolate whether the raw S3 API behaves differently before adding CNPG's own
retry/error-handling on top, which could otherwise mask or launder the difference.
"""
import argparse
import json
import sys

import boto3
from botocore.config import Config


def probe(client, bucket, label):
    out = {"label": label}
    for prefix, key in [("db//", "double_slash"), ("db/", "single_slash")]:
        try:
            resp = client.list_objects_v2(Bucket=bucket, Prefix=prefix)
            contents = [o["Key"] for o in resp.get("Contents", [])]
            out[key] = {"outcome": "http_200", "key_count": resp.get("KeyCount"), "keys": contents}
        except Exception as e:  # noqa: BLE001
            out[key] = {"outcome": "exception", "type": type(e).__name__, "detail": str(e)[:300]}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--region", default="us-east-1")
    ap.add_argument("--label", required=True)
    ap.add_argument("--seed-keys", action="store_true", help="PUT a small barman-shaped db/ hierarchy before probing")
    args = ap.parse_args()

    client = boto3.client(
        "s3", endpoint_url=args.endpoint, aws_access_key_id=args.access_key, aws_secret_access_key=args.secret_key,
        config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 2}), region_name=args.region,
    )

    if args.seed_keys:
        for k in ["db/base/000000010000000000000001", "db/base/000000010000000000000002", "db/wals/00000001.history"]:
            client.put_object(Bucket=args.bucket, Key=k, Body=b"x")

    result = probe(client, args.bucket, args.label)
    print(json.dumps(result))

    dd = result["double_slash"]["outcome"]
    ds = result["single_slash"]["outcome"]
    if dd == "exception":
        classification = "ERROR (matches the documented MinIO/Barman failure mode)"
    elif dd == "http_200" and result["double_slash"]["key_count"] == 0 and ds == "http_200" and result["single_slash"]["key_count"] > 0:
        classification = "HTTP-200-EMPTY (worse than MinIO: silently no-ops instead of erroring)"
    elif dd == "http_200" and result["double_slash"]["key_count"] == result["single_slash"].get("key_count"):
        classification = "CORRECT-LISTING (strictly better than MinIO)"
    else:
        classification = "UNCLASSIFIED -- inspect manually"
    print(f"CLASSIFICATION[{args.label}]: {classification}", file=sys.stderr)


if __name__ == "__main__":
    main()
