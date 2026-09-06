#!/usr/bin/env bash
# Instruments for the local disaster-recovery path. Runs on the recovery host
# against a mounted clone of the object volume, outside Kubernetes.
#
#   VOLUME=/mnt/clone PHASE=volume EXPECT_STORE_ID=<from the runbook> \
#     ./recovery-check.sh
#   VOLUME=/mnt/clone PHASE=gateway ENDPOINT=http://127.0.0.1:7070 \
#     AK=<invented root key> SK=<invented root secret> \
#     BUCKETS="<bucket> <bucket>" AWS=<how to invoke the CLI> ./recovery-check.sh
#
# RECOVERY-RUNBOOK.md, beside this script in the kit, is where the values come
# from -- the expected store_id, the bucket names, and the `docker run` form for
# AWS. This script is instruments; the runbook is the procedure.
set -uo pipefail

VOLUME="${VOLUME:?set VOLUME to the mount point of the clone}"
PHASE="${PHASE:-volume}"
FAILURES=0

ok()   { printf '  PASS  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
note() { printf '        %s\n' "$*"; }

check_volume() {
  local sentinel="$VOLUME/.versitygw-store-identity"

  echo "== 1. is this volume a prepared store at all? =="
  if [ -f "$sentinel" ]; then
    ok "store-identity sentinel present"
    sed 's/^/        /' "$sentinel"
  else
    bad "store-identity sentinel ABSENT -- not a prepared store, or not this one"
    note "volume root holds: $(find "$VOLUME" -mindepth 1 -maxdepth 1 -printf '%f ' 2>/dev/null)"
    # Creating the sentinel on demand would pass every silently reformatted
    # volume, which is the whole failure it exists to catch.
    note "Do NOT create it. Only the store-preparation job writes it."
    return
  fi

  echo "== 2. is it THE store you meant to recover? =="
  # Asserts the TREE, not the device: recovery mounts a clone, so any
  # device-level assertion is red on the sanctioned path and gets bypassed.
  # Which COPY of the tree this is -- clone or production LUN -- is a different
  # question, and it is answered in the runbook against the recorded WWID rather
  # than here. A device check that has never been executed against a real DSM
  # clone is not an instrument; it is an assumption with a PASS printed next to
  # it, and this one had a false-pass path on a partitioned LUN.
  local store_id
  store_id="$(sed -n -e 's/^store_id=//p' -e 's/^store-id=//p' "$sentinel" 2>/dev/null | head -n1)"
  if [ -z "$store_id" ]; then
    # An absent field must not read as a satisfied comparison.
    bad "this sentinel carries no store_id, so it identifies a store but not WHICH store"
    note "Confirm by hand from the tree before restoring from it."
  elif [ -z "${EXPECT_STORE_ID:-}" ]; then
    note "store_id: $store_id"
    note "IDENTITY NOT CONFIRMED -- nothing was compared. Pass EXPECT_STORE_ID"
    note "from the runbook; an old clone of a different LUN looks like this too."
  elif [ "$store_id" = "$EXPECT_STORE_ID" ]; then
    ok "store_id matches the store you are recovering ($store_id)"
  else
    bad "store_id MISMATCH -- this is a different store"
    note "sentinel: $store_id / expected: $EXPECT_STORE_ID"
  fi

  # Unconditional, because it is the one finding here that can damage the thing
  # being recovered, and the operator on the sanctioned path is exactly the one
  # who would never see it if it were printed only on a mismatch.
  note "Mounting the ORIGINAL LUN read-only is NOT a safe alternative to cloning:"
  note "ext4 replays an unreplayed journal and writes to the device. Confirm from"
  note "the runbook's recorded WWID that this is the clone before going further."

  echo "== 3. is the layout the one this procedure assumes? =="
  local dir count
  for dir in data iam recovery; do
    if [ -d "$VOLUME/$dir" ]; then ok "$dir/ present"; else bad "$dir/ missing"; fi
  done
  count=$(find "$VOLUME/data" -mindepth 1 -maxdepth 1 -type d ! -name '.sgwtmp' 2>/dev/null | wc -l)
  if [ "$count" -gt 0 ]; then
    ok "gateway root holds $count bucket directories"
  else
    bad "gateway root holds no buckets -- an empty store"
  fi

  echo "== 4. the recovery kit, verified before it is trusted =="
  local manifest="$VOLUME/recovery/MANIFEST"
  if [ ! -f "$manifest" ]; then
    bad "no recovery/MANIFEST"
  else
    ok "MANIFEST present, generated $(sed -n 's/^generated=//p' "$manifest")"
    local line key tarball want got file
    while IFS= read -r line; do
      key="${line%%_tarball=*}"
      tarball="${line#*=}"
      file="$VOLUME/recovery/$tarball"
      want="$(sed -n "s/^${key}_sha256=//p" "$manifest")"
      if [ ! -f "$file" ]; then
        bad "$tarball is named in MANIFEST but missing"
        continue
      fi
      got="$(sha256sum "$file" | cut -d' ' -f1)"
      if [ "$want" = "$got" ]; then
        ok "$tarball sha256 matches"
      else
        bad "$tarball sha256 MISMATCH (manifest $want, actual $got)"
      fi
    done < <(grep -E '_tarball=' "$manifest")
    # `docker load` exits 0 on a tarball with a corrupt layer, so the sha256
    # above is the check and a successful load is not.
    note "An unusable tarball does not end the recovery: the tree is ordinary"
    note "files. Copy them, or serve them with any versitygw build."
  fi

  echo "== 5. crash-window damage on the clone =="
  # Metadata only, over EVERY object. The gateway does not fsync, so a completed
  # object can be captured by a snapshot as a zero-length file carrying its
  # complete and correct multipart ETag -- the ETag is right, so size is the
  # whole of the signal, and this pass is what reads it.
  #
  # It deliberately does NOT read object bytes. A sampled md5 sweep answers
  # "is systematic damage present", which is the array's redundancy and scrub's
  # question, not this procedure's; it cannot answer the question an operator
  # actually has -- "is the object I am about to restore intact" -- and the
  # producer's own checksum answers that one at the moment of restore, which is
  # the moment that matters.
  local work residue total multipart single zero noetag started elapsed
  started=$(date +%s)
  work=$(mktemp -d) || { bad "cannot create a working directory"; return; }
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN

  residue=$(find "$VOLUME/data" -path '*/.sgwtmp/*' -type f 2>/dev/null | wc -l)
  note ".sgwtmp part files: $residue -- upload parts, not objects"

  # --- Pass A: whole population, metadata only ---
  # Two invocations rather than three per file. Splitting on the FIRST tab is
  # what keeps a key containing spaces intact.
  getfattr -R -h --absolute-names -n user.etag -e text "$VOLUME/data" 2>/dev/null > "$work/etags"
  find "$VOLUME/data" -mindepth 2 -type f ! -path '*/.sgwtmp/*' -printf '%s\t%p\n' 2>/dev/null > "$work/sizes"
  # No stored ETags at all is a distinct condition and must be named as one. It
  # is the OFF-SITE tree (which carries no extended attributes, so this check
  # cannot run there) or a host without `attr` installed -- neither of which is
  # "the store is empty", which is what the object loop would otherwise conclude.
  if [ ! -s "$work/etags" ] && [ -s "$work/sizes" ]; then
    bad "no stored ETags found anywhere under the gateway root"
    note "Either this tree carries no extended attributes -- the off-site copy does"
    note "not, and this check cannot run against it -- or getfattr is missing or"
    note "was refused. It is NOT evidence about the objects themselves."
    return
  fi
  # Discriminate the two inputs by FILENAME, not by `FNR == NR`: with an empty
  # first file that idiom is true for every record of the SECOND one, which
  # silently consumes the entire object list and reports an empty store.
  awk -v etagfile="$work/etags" '
    FILENAME == etagfile {
      if (substr($0, 1, 8) == "# file: ") { path = substr($0, 9); next }
      if (substr($0, 1, 11) == "user.etag=\"") {
        value = substr($0, 12, length($0) - 12)
        gsub(/\\"/, "", value)
        etag[path] = value
      }
      next
    }
    {
      tab = index($0, "\t")
      size = substr($0, 1, tab - 1) + 0
      file = substr($0, tab + 1)
      total++
      if (!(file in etag)) { noetag++; print "NOETAG\t" file; next }
      if (index(etag[file], "-") > 0) {
        multipart++
        if (size == 0) { zero++; print "ZERO\t" file }
      } else {
        single++
      }
    }
    END { print "TOTALS\t" total+0 "\t" multipart+0 "\t" single+0 "\t" zero+0 "\t" noetag+0 }
  ' "$work/etags" "$work/sizes" > "$work/records"

  IFS=$'\t' read -r _ total multipart single zero noetag < <(grep '^TOTALS' "$work/records")
  while IFS=$'\t' read -r _ file; do
    bad "zero-byte multipart object: ${file#"$VOLUME"/data/}"
  done < <(grep '^ZERO' "$work/records")
  while IFS=$'\t' read -r _ file; do
    bad "object carries no stored ETag: ${file#"$VOLUME"/data/}"
  done < <(grep '^NOETAG' "$work/records")

  if [ "$total" -eq 0 ]; then
    bad "no objects under the gateway root -- nothing to check and nothing to recover"
    return
  fi
  if [ "$((zero + noetag))" -eq 0 ]; then
    ok "WHOLE population: $total objects ($multipart multipart, $single single-part)"
  fi

  elapsed=$(( $(date +%s) - started ))
  note "sweep took ${elapsed}s over $total objects"
  # Say what this pass cannot see, here rather than only in the runbook: a
  # partially corrupt object keeps a correct ETag and a correct size. Only a GET
  # with AWS_RESPONSE_CHECKSUM_VALIDATION=when_supported, by a client carrying
  # awscrt, validates the stored CRC64NVME and catches it -- and that is a check
  # to run on the object being restored, not on the store.
  note "Object BYTES were not read. A partially corrupt object is invisible here;"
  note "verify the object you restore, at the moment you restore it."
}

check_gateway() {
  : "${ENDPOINT:?}" "${AK:?}" "${SK:?}" "${BUCKETS:?}"
  # The S3 client arrives in this kit as a DOCKER IMAGE, not as a binary on
  # PATH, because the host this runs on has no registry and no internet -- which
  # is the whole premise. A bare `aws` here would exit `command not found`, and
  # with `set -uo pipefail` and no `-e` that surfaces below as "the gateway
  # refused the request": a misdiagnosis pointing at credentials on the one path
  # that is guaranteed to have none. AWS is therefore how to INVOKE the client,
  # and the runbook supplies the `docker run` form.
  AWS="${AWS:-aws}"
  s3() {
    AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" \
    AWS_DEFAULT_REGION="${REGION:-us-east-1}" $AWS --endpoint-url "$ENDPOINT" "$@"
  }

  echo "== 6. is the gateway serving the object tree, or the volume root? =="
  # Set equality, not a denylist of known-bad names: rooted one level deeper the
  # gateway lists a bucket's own key prefixes, which no fixed list covers.
  # stderr is kept apart from stdout so a client error is not word-split into
  # imaginary bucket names -- a refused listing and an empty one are different
  # findings.
  local listed bucket errors rc
  errors=$(mktemp) || { bad "cannot create a temporary file"; return; }
  # shellcheck disable=SC2064
  trap "rm -f '$errors'" RETURN
  listed=" $(s3 s3api list-buckets --query 'Buckets[].Name' --output text 2>"$errors" | tr '\t\n' '  ') "
  rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "list-buckets FAILED (exit $rc) -- the gateway refused the request; it did not return an empty store"
    sed 's/^/        /' "$errors" | head -4
    note "The root key is INVENTED at container start; there is no production"
    note "credential to go looking for on this path."
    return
  fi
  note "list-buckets:$listed"
  for bucket in $BUCKETS; do
    if [[ "$listed" == *" $bucket "* ]]; then
      ok "expected bucket '$bucket' present"
    else
      bad "expected bucket '$bucket' MISSING"
    fi
  done
  for bucket in $listed; do
    case " $BUCKETS " in
      *" $bucket "*) ;;
      *) bad "UNEXPECTED bucket '$bucket' -- the gateway is not rooted on the object tree" ;;
    esac
  done
  for bucket in data iam recovery lost+found; do
    if [[ "$listed" == *" $bucket "* ]]; then
      note "DIAGNOSIS: rooted on the VOLUME root, not <volume>/data. Stop it now --"
      note "iam/users.json is readable as an ordinary S3 object while it runs."
      break
    fi
  done

  echo "== 7. does S3 agree with the filesystem, per bucket? =="
  local s3n fsn
  for bucket in $BUCKETS; do
    s3n=$(s3 s3api list-objects-v2 --bucket "$bucket" --query 'length(Contents)' --output text 2>/dev/null)
    fsn=$(find "$VOLUME/data/$bucket" -type f ! -path '*/.sgwtmp/*' 2>/dev/null | wc -l)
    if [ "$s3n" = "$fsn" ]; then
      ok "$bucket: S3=$s3n FS=$fsn"
    else
      bad "$bucket: S3=$s3n FS=$fsn -- the gateway is not serving what is on disk"
    fi
  done
}

case "$PHASE" in
  volume)  check_volume ;;
  gateway) check_gateway ;;
  *)       echo "PHASE must be 'volume' or 'gateway'" >&2; exit 2 ;;
esac

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "ALL CHECKS PASSED ($PHASE)"
  exit 0
fi
echo "$FAILURES CHECK(S) FAILED ($PHASE) -- STOP"
exit 1
