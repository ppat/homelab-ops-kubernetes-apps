#!/usr/bin/env python3
"""Exercise the S3 API and assert the isolation the design depends on.

Every check is chosen because it can come back negative. Bucket scoping is
asserted IN THE FAILING DIRECTION: a gateway with no access control at all
passes "the consumer can reach its own bucket", so the denials are the evidence.
"""

import os
import sys

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

endpoint = os.environ["S3_ENDPOINT"]
region = os.environ["S3_REGION"]
one_bucket = os.environ["BUCKET_ONE"]
two_bucket = os.environ["BUCKET_TWO"]

def client(access, secret):
    return boto3.client("s3", endpoint_url=endpoint, aws_access_key_id=access,
                        aws_secret_access_key=secret, region_name=region,
                        config=Config(signature_version="s3v4", retries={"max_attempts": 1}))

one = client(os.environ["CLIENT1_ACCESS"], os.environ["CLIENT1_SECRET"])
root = client(os.environ["ROOT_ACCESS"], os.environ["ROOT_SECRET"])

def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    sys.exit(1)

def denied(label, call):
    try:
        call()
    except ClientError as exc:
        status = exc.response["ResponseMetadata"]["HTTPStatusCode"]
        code = exc.response["Error"]["Code"]
        if status != 403:
            fail("%s returned HTTP %s (%s), expected 403" % (label, status, code))
        print("ok: %s correctly denied (HTTP 403 %s)" % (label, code), file=sys.stderr)
        return
    fail("%s succeeded -- bucket isolation is not being enforced" % label)

key = "wal/000000010000000000000001"
body = b"chainsaw wal segment"
one.put_object(Bucket=one_bucket, Key=key, Body=body, ContentType="application/octet-stream")
got = one.get_object(Bucket=one_bucket, Key=key)["Body"].read()
if got != body:
    fail("round-trip mismatch: put %r, got %r" % (body, got))
print("ok: put/get round-trip matched", file=sys.stderr)

denied("consumer one writing into consumer two's bucket",
       lambda: one.put_object(Bucket=two_bucket, Key="intruder", Body=b"x"))
denied("consumer one reading from consumer two's bucket",
       lambda: one.get_object(Bucket=two_bucket, Key=key))
denied("consumer one listing consumer two's bucket",
       lambda: one.list_objects_v2(Bucket=two_bucket))

visible = sorted(b["Name"] for b in one.list_buckets()["Buckets"])
if visible != [one_bucket]:
    fail("consumer one's ListBuckets returned %r, expected only [%r]" % (visible, one_bucket))
print("ok: consumer one sees only its own bucket", file=sys.stderr)

mpu = one.create_multipart_upload(Bucket=one_bucket, Key="base/backup/data.tar")
one.upload_part(Bucket=one_bucket, Key="base/backup/data.tar",
                UploadId=mpu["UploadId"], PartNumber=1, Body=b"abandoned part payload")
pending = one.list_multipart_uploads(Bucket=one_bucket).get("Uploads", [])
if not any(u["UploadId"] == mpu["UploadId"] for u in pending):
    fail("the abandoned upload %s is not listed by ListMultipartUploads -- it was not created, "
         "so the sweep fixture has nothing real to discover" % mpu["UploadId"])
print("ok: left a real abandoned multipart upload (%s) for the sweep fixture" % mpu["UploadId"],
      file=sys.stderr)

wrong = client(os.environ["CLIENT1_ACCESS"], "wrongwrongwrongwrongwrongwrongwrongwrong")
denied("a request signed with the wrong secret key",
       lambda: wrong.get_object(Bucket=one_bucket, Key=key))

root_buckets = sorted(b["Name"] for b in root.list_buckets()["Buckets"])
if root_buckets != sorted([one_bucket, two_bucket]):
    fail("root's ListBuckets returned %r, expected exactly %r -- anything extra is a "
         "directory inside the gateway root being served as a bucket, and `iam` in "
         "particular would mean users.json is readable as an object"
         % (root_buckets, sorted([one_bucket, two_bucket])))
print("ok: root sees exactly the provisioned buckets, no IAM directory among them", file=sys.stderr)

try:
    root.get_object(Bucket="iam", Key="users.json")
    fail("users.json is readable as an S3 object -- the IAM directory is inside the gateway root")
except ClientError as exc:
    print("ok: s3://iam/users.json is not retrievable (%s)"
          % exc.response["Error"]["Code"], file=sys.stderr)
