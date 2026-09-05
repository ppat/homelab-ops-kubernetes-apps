#!/bin/sh
# Exports the local-recovery kit -- image tarballs, a manifest of their sha256s,
# the operator check script and the runbook -- into a `recovery` subpath of the
# object volume, so a storage-side clone carries everything the disaster-recovery
# path needs and that path needs no registry.
#
# The location is load-bearing: a sibling of the gateway root, so the kit is
# neither enumerable as a bucket nor deletable over S3.
#
# Runs once per gateway version and never again: the Job that carries it is
# recreated by Flux exactly when its image pins change, and is an ordinary no-op
# otherwise -- see job-recovery-export.yaml. This script therefore does no
# freshness reasoning of its own; it exports what it was told to,
# unconditionally.
#
# Every file it writes is staged under a temporary name and renamed into place,
# so a kill at any point leaves whole files rather than torn ones. The MANIFEST
# is renamed LAST, which makes the one inconsistency that remains a loud one: a
# kill between a tarball landing and the MANIFEST moving leaves recovery-check's
# sha256 comparison reporting a mismatch or a missing file, never a tarball that
# verifies against a stale digest.
set -eu

RECOVERY_DIR="${RECOVERY_DIR:?RECOVERY_DIR is not set}"
CHECK_SCRIPT="${CHECK_SCRIPT:-/scripts/recovery-check.sh}"
RUNBOOK="${RUNBOOK:-/scripts/RECOVERY-RUNBOOK.md}"
: "${RECOVERY_VERSITYGW_VERSION:?RECOVERY_VERSITYGW_VERSION is not set}"
: "${RECOVERY_AWSCLI_VERSION:?RECOVERY_AWSCLI_VERSION is not set}"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

# Version strings may carry `@sha256:...`; the tag is what names the tarball and
# what the Job's name has to agree with.
versitygw_tag="${RECOVERY_VERSITYGW_VERSION%@*}"
awscli_tag="${RECOVERY_AWSCLI_VERSION%@*}"

manifest="$RECOVERY_DIR/MANIFEST"
staging="$RECOVERY_DIR/.MANIFEST.tmp"
rm -f "$staging"

{
  echo "# versitygw local-recovery kit. Read RECOVERY-RUNBOOK.md beside this file."
  echo "#"
  echo "# Check the sha256 lines below before trusting a tarball: 'docker load'"
  echo "# exits 0 on a tarball with a corrupt layer, so a successful load is not"
  echo "# evidence. 'crane validate --tarball <file>' is an offline second"
  echo "# opinion, if a crane binary is to hand -- one is NOT in this kit."
  echo "#"
  echo "# A tarball that will not verify does not end the recovery. The stored"
  echo "# form is ordinary files: copy them off the mounted clone, or serve them"
  echo "# with any versitygw build."
  echo "#"
  echo "# The tarballs are linux/amd64. On any other architecture they are the"
  echo "# wrong images and the tree is still ordinary files."
  echo "#"
  echo "# gateway_root is a SUBDIRECTORY of the volume. Serving the volume root"
  echo "# instead exits 0, lists data/iam/recovery as buckets, and makes"
  echo "# iam/users.json readable as an ordinary S3 object."
  echo "generated=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "gateway_root=data"
  echo "iam_dir=iam"
  echo "sentinel=.versitygw-store-identity"
} > "$staging"

keep=""
export_image() {
  name="$1"
  ref="$2"
  tag="$3"
  tarball="${name}-${tag}.tar"
  path="$RECOVERY_DIR/$tarball"
  keep="$keep $tarball"

  log "pulling $ref"
  # By reference rather than by digest alone so the archive keeps a readable
  # tag: crane drops the tag when only a digest is present and the image loads
  # as ':i-was-a-digest'. `tag@digest` keeps both. Staged under .partial so an
  # interrupted run leaves no file that would later be trusted as complete.
  crane pull "$ref" "$path.partial"
  mv "$path.partial" "$path"

  {
    echo "${name}_ref=$ref"
    echo "${name}_tarball=$tarball"
    echo "${name}_sha256=$(sha256sum "$path" | cut -d' ' -f1)"
    echo "${name}_bytes=$(stat -c %s "$path")"
  } >> "$staging"
}

export_image versitygw "ghcr.io/versity/versitygw:${RECOVERY_VERSITYGW_VERSION}" "$versitygw_tag"
export_image aws-cli "amazon/aws-cli:${RECOVERY_AWSCLI_VERSION}" "$awscli_tag"

# The instruments and the procedure travel with the images: both encode this
# volume's layout, so they rot against the same changes the tarballs do. Copied
# through a temporary name so a reader during the write never sees a half file.
copy_in() {
  src="$1"
  dst="$RECOVERY_DIR/$2"
  if [ ! -f "$src" ]; then
    log "WARNING: $src not present, $2 not exported"
    return
  fi
  cp "$src" "$dst.tmp"
  mv "$dst.tmp" "$dst"
  echo "$3=$(sha256sum "$dst" | cut -d' ' -f1)" >> "$staging"
  keep="$keep $2"
}

copy_in "$CHECK_SCRIPT" recovery-check.sh recovery_check_sha256
copy_in "$RUNBOOK" RECOVERY-RUNBOOK.md runbook_sha256

# Everything in this directory is named by the MANIFEST, and that is the whole
# retention policy. Keeping a superseded tarball sounds prudent and is not: the
# MANIFEST is rewritten from scratch each run, so a retained file has no recorded
# sha256, cannot be verified, and can be identified only by loading it -- which
# this kit's own doctrine forbids before a sha256 check. A file you may not trust
# and cannot name is worse than an absent one.
for old in "$RECOVERY_DIR"/*.tar "$RECOVERY_DIR"/*.tar.partial; do
  [ -e "$old" ] || continue
  base=$(basename "$old")
  case " $keep " in *" $base "*) continue ;; esac
  log "removing $base -- not named by this MANIFEST"
  rm -f "$old"
done

mv "$staging" "$manifest"
log "MANIFEST written"
cat "$manifest"
