#!/usr/bin/env python3
"""Assert what the S3 round-trip must have LEFT BEHIND on disk.

An S3 round-trip passes identically against a store that encodes keys or shards
them across a content-addressed layout, so only the on-disk form can establish
that a named object is readable given the storage alone.
"""

import os
import sys

pvc = "/pvc"
root = os.path.join(pvc, "data")
bucket = os.environ["BUCKET_ONE"]
owner = os.environ["CLIENT1_ACCESS"]
key = "wal/000000010000000000000001"
expected_body = b"chainsaw wal segment"

failures = []

def check(condition, message):
    if condition:
        print("ok: " + message)
    else:
        print("FAIL: " + message)
        failures.append(message)

obj = os.path.join(root, bucket, *key.split("/"))
check(os.path.isfile(obj), "the object is one ordinary file at the 1:1 unencoded path %s" % obj)
if os.path.isfile(obj):
    with open(obj, "rb") as handle:
        body = handle.read()
    check(body == expected_body,
          "the file holds exactly the bytes that were PUT (%d bytes)" % len(expected_body))

    attrs = set(os.listxattr(obj))
    for attr in ("user.etag", "user.checksums", "user.content-type"):
        check(attr in attrs, "the object carries %s" % attr)
    if "user.etag" in attrs:
        print("     user.etag = %s" % os.getxattr(obj, "user.etag").decode())
    if "user.checksums" in attrs:
        print("     user.checksums = %s" % os.getxattr(obj, "user.checksums").decode()[:120])

bucket_dir = os.path.join(root, bucket)
battrs = set(os.listxattr(bucket_dir)) if os.path.isdir(bucket_dir) else set()
check("user.acl" in battrs, "the bucket directory carries user.acl")
check("user.ownership" in battrs, "the bucket directory carries user.ownership")
if "user.acl" in battrs:
    acl = os.getxattr(bucket_dir, "user.acl").decode()
    print("     user.acl = %s" % acl)
    check('"Owner":"%s"' % owner in acl,
          "the recorded bucket owner is the consumer account %s" % owner)

rattrs = [a for a in os.listxattr(root) if a.startswith("user.")]
check(not rattrs,
      "the gateway root carries no user.* attributes (found %r)" % rattrs)

check(os.path.isfile(os.path.join(pvc, "iam", "users.json")),
      "the IAM store is a sibling of the gateway root at %s/iam/users.json" % pvc)
check(not os.path.exists(os.path.join(root, "iam")),
      "no IAM directory exists inside the gateway root")

print("---")
if failures:
    print("%d stored-form assertion(s) failed" % len(failures))
    sys.exit(1)
print("stored form verified")
