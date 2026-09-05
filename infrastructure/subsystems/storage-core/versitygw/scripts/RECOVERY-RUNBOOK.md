# versitygw object store — local recovery runbook

The procedure for reading the backup object store when the cluster that normally serves it is gone.
It is written to be usable from a copy of this file on the volume itself, by someone with a browser
that cannot reach this repository, a host with no registry and no internet, and nothing else.

`recovery-check.sh`, beside this file in the kit, is the instrument set. This is the procedure. It
carries the values the instruments ask for and the steps no script performs.

## Before you start: what has to be filled in

Two facts cannot be derived at recovery time and must be recorded here, in this repository, when the
store is prepared. **A blank slot is not a missing detail — it disarms a check.**

| Slot | Fill with | Recorded when | Used for |
| --- | --- | --- | --- |
| `EXPECT_STORE_ID` | The 32 lowercase hex characters the store-preparation job printed as `store_id` | Store preparation, once, from the job's log | Answers *is this the store*. Without it the identity check degrades to `IDENTITY NOT CONFIRMED — nothing was compared`, and an old clone of a different LUN looks identical |
| Original LUN WWID | Every `/dev/disk/by-id/scsi-*` link that resolves to the LUN's kernel device, read on the host while the store is mounted normally | Volume preparation, on the host | Answers *is this the original or a copy*. Its only use is the inverse: a device whose WWID **matches** this one is production, and you must stop |
| Bucket names | The buckets the store holds | Cluster provisioning | The set-equality check in phase 2, which is what catches a gateway rooted one level wrong |

Recording the WWID:

```sh
DEV=/dev/sdX                       # the kernel node iscsiadm reported
KDEV=$(lsblk -ndo KNAME "$DEV") || { echo "cannot resolve $DEV" >&2; exit 1; }
found=""
for link in /dev/disk/by-id/scsi-*; do
  [ -e "$link" ] || continue
  [ "$(readlink -f "$link")" = "/dev/$KDEV" ] && found="$found $link"
done
[ -n "$found" ] && { for l in $found; do echo "wwid: $l"; done; } || {
  echo "FAILED: no scsi-* link resolves to /dev/$KDEV -- a failed lookup, not a device" >&2
  exit 1
}
```

Resolve by where each symlink **points**, never by matching the device's name: under device-mapper
the mounted device is `/dev/mapper/<x>` while every `by-id/scsi-*` link points at the kernel node
underneath it, so a name match finds nothing and prints nothing — and "no WWID" then reads as a fact
about the device rather than as a lookup that did not work. That exact bug has already happened once
in this project.

Recorded values:

<!-- markdownlint-disable MD034 -->

| | |
| --- | --- |
| `EXPECT_STORE_ID` | *(record at store preparation)* |
| Original LUN WWID | *(record at volume preparation)* |
| Buckets | *(record at cluster provisioning)* |

<!-- markdownlint-enable MD034 -->

## Step 1 — clone the LUN on DSM

Clone, never reattach. The original LUN is then never touched, so the recovery environment cannot
damage what is being recovered from, and there is no question about whether the old VM has released
it.

1. DSM → SAN Manager → LUN → select the store's LUN → **Create Clone**.
2. Map the clone to an iSCSI target the recovery host is allowed to log in to. Give the target its
   own name; do not reuse the production target's ACL.
3. Note the clone's **mapping index** (LUN number) — the login step reports it.

**Do not try to look at the production LUN read-only instead.** `mount -o ro` on an ext4 filesystem
with an unreplayed journal **writes to the device**: the kernel prints `write access will be enabled
during recovery` and replays anyway. (`-o ro,noload` avoids the write only by skipping recovery,
which presents a filesystem state that never existed.) There is no safe read-only look. Clone it.

## Step 2 — attach and mount the clone

```sh
iscsiadm -m discovery -t sendtargets -p <portal>
iscsiadm -m node -T <clone-target-iqn> -p <portal> --login
iscsiadm -m session -P 3 | grep -E 'Target:|Lun:|Attached scsi disk'
```

The last line gives the `/dev/sdX` for the clone.

**Select the device by WWID, never by filesystem label or UUID.** A clone carries the *same* label
(`versitygw-store`) and the *same* UUID as the original, because both live inside the copied blocks —
so with both visible to the host, `mount -L versitygw-store` mounts one of the two with nothing
determining which, and it can mount production at exactly the moment the whole point is not to touch
it. The WWID is the one thing DSM assigns per LUN and is therefore the only device-level
discriminator.

Confirm against the recorded WWID above: it must **differ**. A match means you are on production —
unmount and go back to step 1.

```sh
mkdir -p /mnt/clone
mount /dev/sdX /mnt/clone
```

## Step 3 — check the volume before trusting it

```sh
VOLUME=/mnt/clone PHASE=volume EXPECT_STORE_ID=<from the table above> \
  /mnt/clone/recovery/recovery-check.sh
```

What it establishes, and what each failure means:

| Check | A failure means |
| --- | --- |
| 1. store-identity sentinel present | Not a prepared store, or not this one. **Do not create the file** — creating it is exactly how a silently reformatted volume gets accepted, which is the failure the sentinel exists to catch |
| 2. `store_id` equals the recorded one | A different store. Stop and work out which LUN you cloned |
| 3. `data/`, `iam/`, `recovery/` present, and buckets under `data/` | An empty or wrong-shaped tree |
| 4. every tarball in `recovery/` matches its recorded sha256 | The kit is damaged. This does **not** end the recovery — see step 5 |
| 5. no zero-length object carrying a complete multipart ETag, none missing its stored ETag | Crash-window damage: the gateway acknowledges a write before the journal commits, so a snapshot can capture a completed object as a zero-length file whose ETag is entirely correct. Size is the whole of the signal |

The pass does **not** read object bytes, so a partially corrupt object is invisible to it. Verify the
object you actually restore, at the moment you restore it, with the producer's own checksum — for
S3, a GET with `AWS_RESPONSE_CHECKSUM_VALIDATION=when_supported` from a client carrying `awscrt`
validates the stored CRC64NVME.

## Step 4 — load the kit's images

The kit is `recovery/` on the volume: the image tarballs, `MANIFEST` recording each one's sha256,
`recovery-check.sh`, and this file. Nothing here needs a registry or the internet.

```sh
cat /mnt/clone/recovery/MANIFEST                    # the sha256s and the layout facts
sha256sum /mnt/clone/recovery/*.tar                 # compare by eye, or rely on check 4 above
docker load -i /mnt/clone/recovery/versitygw-<version>.tar
docker load -i /mnt/clone/recovery/aws-cli-<version>.tar
```

**Check the sha256 before loading, not after.** `docker load` exits 0 on a tarball with a corrupt
layer, prints `Loaded image`, and the image then runs — measured, not assumed. The sha256 is the only
check there is.

If a tarball will not verify, the recovery is not over. The stored form is ordinary files: the key is
the path beneath the bucket directory, unencoded and 1:1, and per-object metadata is in `user.*`
extended attributes on the inode. Copy the files off the mount, or serve the tree with any versitygw
build you can obtain.

The tarballs are `linux/amd64`. On another architecture they are the wrong images — and the tree is
still ordinary files.

## Step 5 — serve the tree

```sh
docker run --rm --network host \
  -v /mnt/clone:/mnt/clone \
  ghcr.io/versity/versitygw:<version> \
  --port :7070 --access RECOVERY --secret RECOVERYSECRET \
  posix /mnt/clone/data
```

Three things about this invocation:

- **`/mnt/clone/data`, not `/mnt/clone`.** Serving the volume root exits 0 and works — and then lists
  `data`, `iam` and `recovery` as buckets, which makes `iam/users.json`, holding every account secret
  in cleartext, readable as an ordinary S3 object. Check 6 below is what catches this; heed it.
- **The access key and secret are invented here and now.** They are supplied at container start and
  never checked against the tree, so there is no production credential to go looking for on this
  path. If a listing is refused, it is not a credential problem.
- **No `--iam-dir`.** This gateway serves the tree; it is not reproducing the account model.

## Step 6 — check the gateway, then restore

```sh
AWSRUN="docker run --rm --network host -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION amazon/aws-cli:<version>"

VOLUME=/mnt/clone PHASE=gateway ENDPOINT=http://127.0.0.1:7070 \
  AK=RECOVERY SK=RECOVERYSECRET \
  BUCKETS="<bucket> <bucket>" \
  AWS="$AWSRUN" \
  /mnt/clone/recovery/recovery-check.sh
```

`AWS` is how to invoke the client. It must be set on this path: the S3 client arrives as a docker
image, not as a binary on `PATH`, so a bare `aws` exits `command not found` — which the script would
otherwise report as the gateway refusing the request, sending you after a credential problem that
cannot exist here.

| Check | A failure means |
| --- | --- |
| 6. the listed buckets are exactly the expected set | The gateway is not rooted on the object tree. If `data`, `iam` or `recovery` appear, it is rooted on the **volume root** — stop it now, `iam/users.json` is being served. If a bucket's own key prefix appears as a bucket, it is rooted one level too deep |
| 7. per bucket, the S3 object count equals the file count on disk | The gateway is not serving what is on disk |

Then restore normally, over S3, against `http://127.0.0.1:7070` — CloudNativePG's `barman-cloud`
restore, Longhorn's backupstore restore, or a plain `aws s3 cp`. For a single file, skip the gateway
entirely and read it off the mounted tree.

## Afterwards

```sh
umount /mnt/clone
iscsiadm -m node -T <clone-target-iqn> -p <portal> --logout
```

Then delete the clone on DSM, and unmap its target. A clone left mapped is a second full-size copy of
the store consuming array capacity, and a second device whose WWID nobody has recorded.

## The other scenario: the site is gone

The off-site copy is the same stored form, so the procedure is the same one over a different mount —
versitygw over the replicated tree, or over a snapshot mounted via SMB, and restore over S3, or read
single files straight off the tree. One difference matters: the off-site tree carries **no extended
attributes**, so there are no stored ETags to check and step 3's check 5 cannot run. Integrity on
that path rests entirely on the producers' own verification during restore.
