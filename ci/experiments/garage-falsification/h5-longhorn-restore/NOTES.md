# H5 — Longhorn backup restore round-trip

## Verdict

```
SUMMARY test=h5-longhorn-restore verdict=SKIPPED reason=longhorn-manager cannot start on sandbox-talos: node's Talos image lacks the siderolabs/iscsi-tools system extension (iscsiadm not present on host), and fixing it requires a talosctl upgrade + full node reboot that would disrupt other tenants concurrently using the shared sandbox -- not performed unilaterally
```

This is a genuine infrastructure blocker, not a weaker substitute test standing in for the
real one. Per the task's own explicit escalation path, it's reported as SKIPPED with full
reasoning below rather than silently downgraded to something else and called a pass.

## What actually ran vs. what didn't

| Step | Status |
| --- | --- |
| Garage instance + bucket + key, region "garage" | **Ran for real** (`garage-setup.sh`, idempotent, verified with 2 back-to-back runs) |
| Garage region exact-match enforcement (the brief's core S3-compat warning) | **Ran for real** (`garage-region-check.py`, real boto3 traffic through a port-forward) |
| Byte-diff checker + its fail-first proof | **Ran for real, independent of Longhorn** (`checksum_verify.py` + `fixture-fail-first.sh`) |
| Writer-pod's write/checksum command | **Smoke-tested for real** against a throwaway local-path PVC (not Longhorn, which never scheduled) |
| Longhorn install | **Ran for real, failed for real** (see below) |
| Backup, volume delete, restore, final byte-diff | **NOT executed** -- blocked on Longhorn (`backup-restore-driver.sh` is a best-effort, unexecuted sketch; see its own header for exactly which parts are high vs. low confidence) |

## Region: "garage", confirmed matching

Both Garage's `s3_region` (in `garage.yaml`'s ConfigMap) and the region baked into every S3
call in this test use the literal string `garage` -- the same convention h2/h4 already
established elsewhere in this harness. `garage-setup.sh` writes it to `creds.env` as
`GARAGE_REGION=garage`, and `backup-restore-driver.sh` step 2 constructs the Longhorn
BackupTarget as `s3://<bucket>@garage/` using that exact same variable, so there's no
opportunity for the value to drift between what Garage enforces and what Longhorn would be
told, by construction.

## S3-compat finding: Garage's exact-region-match, confirmed with real traffic

Ran `garage-region-check.py` against the live Garage instance through a port-forward
(`kubectl --context sandbox-talos port-forward -n h5-garage svc/garage 13900:3900`):

- **Correct region ("garage")**: PutObject/GetObject round-trip succeeded cleanly.
- **Mismatched region ("us-east-1")**: rejected outright. Raw response body captured via
  botocore debug logging:

  ```
  <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code>
  <Message>Authorization header malformed, unexpected scope:
  '20260812/us-east-1/s3/aws4_request', expected: '20260812/garage/s3/aws4_request'
  </Message><Resource>/h5-longhorn-backup/region-check/wrong.txt</Resource>
  <Region>garage</Region></Error>
  ```

  This is exactly the `AuthorizationHeaderMalformed` behavior the brief warned about, and it
  is why the driver script threads `GARAGE_REGION` through to the BackupTarget rather than
  hardcoding a region string in two places.
- **Caveat found while confirming this**: `GetBucketLocation` specifically does NOT enforce
  the match -- Garage answers it (200, returns the real region) regardless of what region
  the client signed with. This isn't a Garage bug: `GetBucketLocation` is the standard S3
  call clients use to *discover* the correct region before signing anything else, and real
  AWS S3 behaves the same way. It does mean that if Longhorn's own reachability check is
  just a `GetBucketLocation` probe (the brief names this call specifically), a misconfigured
  region could pass that probe and still fail on the actual backup PUT -- worth remembering
  if a future run of this test sees Longhorn's BackupTarget status go green on a region that
  turns out to be wrong.
- **Caveat #2 (client-library-specific, not a Garage behavior)**: boto3/botocore
  transparently retries a request that failed with a region-scope error, using the region
  Garage reported back, so a *deliberately* wrong-region PutObject with a plain boto3 client
  can silently "heal" and succeed on attempt 2. Confirmed this doesn't apply to the actual
  falsifier by checking object existence with a fresh client rather than trusting the
  original call's own success/failure, and by reading the raw HTTP transcript (see above) --
  attempt 1 genuinely was rejected. Longhorn's own Go S3 client has no reason to share
  botocore's specific retry-on-region-error behavior, so getting the configured region right
  still matters for the real disaster-recovery path; this is flagged in
  `garage-region-check.py`'s own docstring so it isn't mistaken for "the mismatch doesn't
  matter."

## The blocker, in full

`ci/experiments/garage-falsification/h5-longhorn-restore/longhorn-values.yaml` installs
Longhorn chart 1.12.0 (same version as
`infrastructure/subsystems/storage-core/longhorn/helm-release-longhorn.yaml`) via Helm onto
sandbox-talos, single Talos v1.13.8 node. `longhorn-manager`'s pod crash-loops immediately:

```
time="2026-08-12T03:25:02.121782834Z" level=fatal msg="Error starting manager: failed to
check environment, please make sure you have iscsiadm/open-iscsi installed on the host:
failed to execute: /usr/bin/nsenter [nsenter --mount=/host/proc/186858/ns/mnt
--net=/host/proc/186858/ns/net iscsiadm --version], output , stderr nsenter: failed to
execute iscsiadm: No such file or directory: exit status 127"
func=main.main.DaemonCmd.func3 file="daemon.go:111"
```

Confirmed root cause directly on the node (not inferred):

```
$ talosctl get extensions
NODE       NAMESPACE   TYPE              ID   VERSION   NAME        VERSION
talos-vm   runtime     ExtensionStatus   0    1         schematic   376567988ad...

$ talosctl read /proc/modules | grep -i iscsi   # no output -- module not loaded
$ talosctl list /usr/local/lib                  # only "kubelet" -- no extension-provided binaries
```

The node's boot image (schematic `376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba`)
does not include the `siderolabs/iscsi-tools` system extension that Longhorn's v1 (iSCSI)
data engine requires on every node. Talos is immutable and has no runtime package manager --
`nsenter`s into the host mount namespace looking for a binary that genuinely does not exist
there, and there is no way to add it without changing the node's installed image (via
`talosctl upgrade` to an image built with that extension) and rebooting.

**Why that fix was not attempted**: sandbox-talos is a single-node cluster, so a
`talosctl upgrade` reboots the only node -- full cluster outage for the duration, affecting
every namespace, not just this test's own. When this test started, sandbox-talos already had
an actively-reconciling Flux Kustomization (`infra-storage-object-core`, tracking GitRepository
`ppat/homelab-ops-kubernetes-apps@storage-object-core/chainsaw-tests`, i.e. a real chainsaw
test run for the production Garage module being developed elsewhere) plus long-running,
clearly unrelated workloads (`litellm-audit` 30h old, `mise-poc` 2d20h old) -- none of which
existed when this task's brief described the sandbox as having "no storage classes/PVs
currently defined," meaning the sandbox picked up concurrent tenants after the brief was
written. Rebooting the node would disrupt that concurrent work with no way to coordinate with
whoever owns it. This is exactly the kind of expensive/hard-to-reverse-for-others action that
warrants stopping and asking rather than guessing, and the task's own instructions
pre-authorize SKIPPED as the correct outcome for precisely this situation.

**What would actually fix it**: `talosctl upgrade` to an installer image whose schematic
includes `siderolabs/iscsi-tools` (built via <https://factory.talos.dev>), then reboot; or run
this test against a dedicated (non-shared) Talos/K8s node so the reboot has no blast radius
beyond this test.

## Fail-first proof (byte-diff checker)

Run independent of Longhorn/Kubernetes entirely -- pure local filesystem
(`fixture-fail-first.sh`), so the checker is proven correct before it's ever trusted against
a real restore:

1. Generated 3 real files (~17 MiB: two `/dev/urandom` binaries + one 20,000-line text file)
   under a temp dir, ran `checksum_verify.py --generate` to record a sha256 manifest.
2. Copied the tree, ran `--verify` against the untouched copy: `MATCH: all 3 files
   byte-identical` (exit 0).
3. Flipped exactly one byte (offset 1234567) in one 10 MiB file in the copy, ran `--verify
   --expect-mismatch`:

   ```
   CONTENT MISMATCH (1/3): ['fixture-b.bin']
   MISMATCH: 1/3 files differ
   FAIL-FIRST OK: checker correctly reported MISMATCH on deliberately-broken input
   ```

   Exit 0 (in `--expect-mismatch` mode, detecting the mismatch IS success). Confirms the
   checker's hashing and comparison logic actually distinguishes correct from corrupted
   bytes, per the harness's standing rule (mirrors H1's tmpfs ENOSPC proof and H2's
   deliberately-corrupted-metadata-store proof).

Had step 3 instead reported `MATCH`, that would mean the checker is broken and the real
restore result would be void regardless of what it said -- did not reach that state; the
detector is trustworthy.

## Files

- `garage.yaml` -- Garage Deployment/Service/ConfigMap, its own namespace (`h5-garage`),
  region `garage`. Deliberately separate from the `garage`/`garage-operator-system`
  namespaces already on sandbox-talos (see blocker section) -- those belong to unrelated,
  concurrently-running infra and must not be touched.
- `garage-setup.sh` -- idempotent bootstrap (layout, bucket, key), writes `creds.env`. Ran
  for real, twice, to confirm idempotency (including fixing two real bugs found by running
  it twice: a short-vs-full node-ID mismatch in the layout-already-applied check, and
  `garage key create` not being idempotent by name -- both documented inline in the script).
- `garage-region-check.py` -- ran for real; see S3-compat finding above.
- `checksum_verify.py` -- the byte-diff checker, `--generate`/`--verify`/`--expect-mismatch`.
- `fixture-fail-first.sh` -- the checker's fail-first proof; ran for real, see above.
- `longhorn-values.yaml` -- Helm values for chart 1.12.0, deviations from
  `infrastructure/subsystems/storage-core/longhorn/helm-release-longhorn.yaml` documented in
  its own header (replica count 2->1 for the single-node sandbox; ServiceMonitor disabled,
  no prometheus-operator CRDs here).
- `writer-pod.yaml` -- PVC + pod writing real checksummable data; write/checksum command
  smoke-tested for real against local-path (not Longhorn).
- `backup-restore-driver.sh` -- the full steps 3-8 driver (BackupTarget config, backup
  trigger, volume delete, restore, final byte-diff). **Not executed.** Its own header marks
  which parts are high-confidence (BackupTarget Setting/Secret shape, volume deletion) vs.
  recalled-from-memory-and-unverified (the exact `Backup`/`Volume` CRD field names for
  triggering a backup and restoring one) -- confirm those against `kubectl explain
  backups.longhorn.io --recursive` / `volumes.longhorn.io --recursive` on a working Longhorn
  before relying on them.
