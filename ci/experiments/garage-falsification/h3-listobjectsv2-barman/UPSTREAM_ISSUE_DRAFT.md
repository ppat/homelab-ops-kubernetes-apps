# Draft upstream issue for deuxfleurs-org/garage

**Title**: `ListObjectsV2` with a `Prefix` containing `//` returns HTTP 200 with an empty
list instead of an error or a correct listing

## Summary

MinIO rejects `ListObjectsV2(Prefix="db//")`-style prefixes (containing a doubled slash)
with `XMinioInvalidObjectName` / "Object name contains unsupported characters" (HTTP 400).
This is a known compatibility trap for `barman-cloud` (pgbarman/barman#912 and related), which
constructs `db//<wal-file>`-shaped prefixes when a configured path ends up with a doubled
separator.

Garage v2.3.0 instead returns **HTTP 200 with `KeyCount=0` and an empty `Contents`**, even
though objects matching the corresponding single-slash prefix exist in the bucket.

This is arguably worse than MinIO's behavior for any tool (barman-cloud, retention/pruning
jobs) that treats "0 results" as "nothing to do" rather than as an error: the operation
looks like it succeeded, and a retention/deletion job driven by such a listing would
silently no-op forever with no error surfaced anywhere.

## Reproduction

```python
import boto3
from botocore.config import Config

client = boto3.client("s3", endpoint_url="http://<garage>:3900",
    aws_access_key_id="...", aws_secret_access_key="...",
    config=Config(s3={"addressing_style": "path"}), region_name="garage")

client.put_object(Bucket="b", Key="db/base/000000010000000000000001", Body=b"x")

client.list_objects_v2(Bucket="b", Prefix="db/")   # -> KeyCount=1, as expected
client.list_objects_v2(Bucket="b", Prefix="db//")  # -> KeyCount=0, Contents=[] (!)
```

Expected (matching either the correct S3 behavior of listing nothing under a genuinely
different, `//`-containing prefix path -- OR matching MinIO's explicit rejection): one of
those two, not a silent empty success that's indistinguishable from "correctly found
nothing here."

## Environment

- Garage v2.3.0 (`dxflrs/garage:v2.3.0`), single node, `lmdb` engine, `replication_factor=1`
- Reproduced via `repro.py` in this directory (`ci/experiments/garage-falsification/h3-listobjectsv2-barman/`)

## Why this matters

barman-cloud's WAL retention/pruning path lists objects under a server-scoped prefix before
deleting old WAL segments. If that prefix construction can produce a doubled slash (as
documented for barman-cloud against S3-compatible backends), a retention job against Garage
would not error -- it would just never delete anything, and nothing in the job's own status
would indicate a problem. This is the failure mode this repo's H3 test is specifically
designed to catch (see `../README.md`).

---
*Not filed yet -- drafted as part of a pre-adoption falsification exercise on the
homelab-ops-kubernetes-apps repo. File at
[github.com/deuxfleurs-org/garage/issues](https://github.com/deuxfleurs-org/garage/issues)
if the finding is confirmed against the latest release.*
