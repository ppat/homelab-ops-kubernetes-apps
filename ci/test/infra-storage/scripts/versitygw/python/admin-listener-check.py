#!/usr/bin/env python3
"""Assert the admin API is NOT reachable on the listener the backup clients use.

Signed with the ROOT credential, and paired with a positive control on the admin
port: an unsigned or wrong-key request is refused by authentication before
routing, so it would pass against a gateway serving admin routes everywhere.
"""

import hashlib
import os
import sys
import urllib.error
import urllib.request

from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials

creds = Credentials(os.environ["ROOT_ACCESS"], os.environ["ROOT_SECRET"])
region = os.environ["S3_REGION"]
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()

def signed_admin_status(port):
    url = "http://%s:%s/list-buckets" % (os.environ["FORWARD_HOST"], port)
    request = AWSRequest(method="PATCH", url=url, data=b"")
    request.headers["X-Amz-Content-Sha256"] = EMPTY_SHA256
    SigV4Auth(creds, "s3", region).add_auth(request)
    prepared = urllib.request.Request(url, data=b"", method="PATCH",
                                      headers=dict(request.headers))
    try:
        with urllib.request.urlopen(prepared, timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code

control = signed_admin_status(os.environ["ADMIN_LOCAL_PORT"])
if control != 200:
    print("FAIL: the signed admin request got HTTP %s on the ADMIN port. The positive control "
          "failed, so nothing can be concluded from the S3-port result below." % control,
          file=sys.stderr)
    sys.exit(1)
print("ok: positive control -- the signed admin request works on the admin port (200)",
      file=sys.stderr)

on_s3 = signed_admin_status(os.environ["S3_LOCAL_PORT"])
if on_s3 == 200:
    print("FAIL: the same signed admin request also succeeded on the S3 listener (200) -- the "
          "admin API is mounted on the port the backup producers use.", file=sys.stderr)
    sys.exit(1)
print("ok: the admin route is not served on the S3 listener (HTTP %s to an identically "
      "signed request that returns 200 on the admin port)" % on_s3, file=sys.stderr)
