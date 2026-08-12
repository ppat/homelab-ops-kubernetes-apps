#!/usr/bin/env bash
# H5 steps 3-8: writer pod -> configure BackupTarget -> backup -> DELETE VOLUME -> restore
# -> byte-diff. NOT EXECUTED. Longhorn itself never became operational on sandbox-talos
# (see NOTES.md: longhorn-manager crash-loops with "failed to check environment... make
# sure you have iscsiadm/open-iscsi installed on the host" -- the node's Talos image lacks
# the siderolabs/iscsi-tools system extension, and there is no way to add it without a
# `talosctl upgrade` + full node reboot, which this session declined to do unilaterally on
# a sandbox actively shared with other tenants -- see NOTES.md for the full reasoning).
#
# CONFIDENCE LEVEL, so a future reader knows what to double-check before trusting this:
#   - garage bootstrap, BackupTarget Setting + credentials Secret shape, writer pod: high
#     confidence (Setting/Secret shape is stable, documented Longhorn API; writer pod
#     command was smoke-tested for real against local-path, see writer-pod.yaml).
#   - `garage layout status`-style "did the backup finish" polling: high confidence (same
#     `garage` CLI shape used elsewhere in this harness).
#   - triggering an on-demand backup (step marked TRIGGER-BACKUP below) and the restore
#     Volume CR's exact field names (step marked RESTORE-VOLUME below): recalled from
#     memory, NOT verified against a running Longhorn -- run `kubectl explain
#     backups.longhorn.io --recursive` and `kubectl explain volumes.longhorn.io --recursive`
#     against a working Longhorn install to confirm field names before relying on this.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX=sandbox-talos
GARAGE_NS=h5-garage
LH_NS=longhorn-system
PVC=h5-data
POD=h5-writer
OUT="$HERE/../results/h5-longhorn-restore.json"
mkdir -p "$(dirname "$OUT")"

# shellcheck disable=SC1091
source "$HERE/creds.env" # from garage-setup.sh: GARAGE_BUCKET, GARAGE_REGION, GARAGE_ACCESS_KEY, GARAGE_SECRET_KEY, GARAGE_S3_ENDPOINT_INCLUSTER

echo "=== 1: writer pod (real, checksummable data) ==="
kubectl --context "$CTX" create configmap h5-checksum-verify -n "$GARAGE_NS" \
  --from-file=checksum_verify.py="$HERE/checksum_verify.py" \
  --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
kubectl --context "$CTX" apply -f "$HERE/writer-pod.yaml"
kubectl --context "$CTX" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$POD" -n "$GARAGE_NS" --timeout=120s
kubectl --context "$CTX" cp "$GARAGE_NS/$POD:/data/manifest.json" "$HERE/../results/h5-pre-backup-manifest.json"
echo "recorded pre-backup manifest at results/h5-pre-backup-manifest.json"

echo "=== 2: configure BackupTarget (region must exactly match GARAGE_REGION=$GARAGE_REGION) ==="
kubectl --context "$CTX" create secret generic garage-backup-credentials -n "$LH_NS" \
  --from-literal=AWS_ACCESS_KEY_ID="$GARAGE_ACCESS_KEY" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$GARAGE_SECRET_KEY" \
  --from-literal=AWS_ENDPOINTS="$GARAGE_S3_ENDPOINT_INCLUSTER" \
  --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
kubectl --context "$CTX" -n "$LH_NS" patch settings.longhorn.io backup-target-credential-secret \
  --type=merge -p '{"value":"garage-backup-credentials"}'
kubectl --context "$CTX" -n "$LH_NS" patch settings.longhorn.io backup-target \
  --type=merge -p "{\"value\":\"s3://${GARAGE_BUCKET}@${GARAGE_REGION}/\"}"
echo "backup-target set to s3://${GARAGE_BUCKET}@${GARAGE_REGION}/ (exact-match region per brief)"
# Verify Longhorn can actually reach it (this IS the GetBucketLocation / API-compat check
# the brief calls out by name) before trusting anything past this point:
kubectl --context "$CTX" -n "$LH_NS" get settings.longhorn.io backup-target -o jsonpath='{.status}'
echo
echo "^ inspect for backupTargetError / lastBackupTargetSyncedAt fields going healthy before proceeding"

echo "=== 3: TRIGGER-BACKUP (best-effort, see confidence note above) ==="
VOLUME=$(kubectl --context "$CTX" -n "$GARAGE_NS" get pvc "$PVC" -o jsonpath='{.spec.volumeName}')
LH_VOLUME=$(kubectl --context "$CTX" -n "$LH_NS" get pv "$VOLUME" -o jsonpath='{.spec.csi.volumeHandle}')
echo "longhorn volume name: $LH_VOLUME"
SNAP_NAME="h5-backup-snap-$(date +%s)"
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: $SNAP_NAME
  namespace: $LH_NS
spec:
  volume: $LH_VOLUME
  createSnapshot: true
EOF
kubectl --context "$CTX" -n "$LH_NS" wait --for=jsonpath='{.status.readyToUse}'=true "snapshot/$SNAP_NAME" --timeout=60s
BACKUP_NAME="h5-backup-$(date +%s)"
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: $BACKUP_NAME
  namespace: $LH_NS
spec:
  snapshotName: $SNAP_NAME
EOF
kubectl --context "$CTX" -n "$LH_NS" wait --for=jsonpath='{.status.state}'=Completed "backup/$BACKUP_NAME" --timeout=300s
BACKUP_URL=$(kubectl --context "$CTX" -n "$LH_NS" get "backup/$BACKUP_NAME" -o jsonpath='{.status.url}')
echo "backup completed: $BACKUP_URL"

echo "=== 4: DELETE THE VOLUME (the real disaster-recovery test, not just the pod) ==="
kubectl --context "$CTX" delete pod "$POD" -n "$GARAGE_NS"
kubectl --context "$CTX" delete pvc "$PVC" -n "$GARAGE_NS" --wait=true
kubectl --context "$CTX" -n "$LH_NS" wait --for=delete "volume/$LH_VOLUME" --timeout=120s || true
echo "volume $LH_VOLUME deleted (confirm above it's actually gone, not just the pod/pvc)"

echo "=== 5: RESTORE-VOLUME (best-effort, see confidence note above) ==="
RESTORE_VOLUME="h5-restored-$(date +%s)"
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: $RESTORE_VOLUME
  namespace: $LH_NS
spec:
  size: "536870912"
  numberOfReplicas: 1
  fromBackup: "$BACKUP_URL"
  frontend: blockdev
EOF
kubectl --context "$CTX" -n "$LH_NS" wait --for=jsonpath='{.status.restoreStatus[0].state}'=complete "volume/$RESTORE_VOLUME" --timeout=300s || \
  echo "WARNING: restore completion condition not observed as expected -- inspect volume status manually before trusting this"

# static PV/PVC binding to the restored Longhorn volume (standard Longhorn restore pattern)
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $RESTORE_VOLUME
spec:
  capacity:
    storage: 512Mi
  accessModes: ["ReadWriteOnce"]
  csi:
    driver: driver.longhorn.io
    volumeHandle: $RESTORE_VOLUME
  persistentVolumeReclaimPolicy: Delete
  volumeMode: Filesystem
  storageClassName: longhorn-static
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: h5-restored
  namespace: $GARAGE_NS
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: longhorn-static
  volumeName: $RESTORE_VOLUME
  resources:
    requests:
      storage: 512Mi
EOF

echo "=== 6: mount restored volume, byte-diff against pre-backup manifest ==="
cat <<EOF | kubectl --context "$CTX" apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: h5-reader
  namespace: $GARAGE_NS
spec:
  restartPolicy: Never
  containers:
  - name: reader
    image: python:3.13-slim
    command: ["sleep", "300"]
    volumeMounts:
    - {name: data, mountPath: /data}
    - {name: scripts, mountPath: /scripts}
  volumes:
  - {name: data, persistentVolumeClaim: {claimName: h5-restored}}
  - {name: scripts, configMap: {name: h5-checksum-verify}}
EOF
kubectl --context "$CTX" wait --for=condition=Ready pod/h5-reader -n "$GARAGE_NS" --timeout=120s
kubectl --context "$CTX" cp "$HERE/../results/h5-pre-backup-manifest.json" "$GARAGE_NS/h5-reader:/data/pre-backup-manifest.json"
kubectl --context "$CTX" exec -n "$GARAGE_NS" h5-reader -- \
  python3 /scripts/checksum_verify.py --verify --dir /data --manifest /data/pre-backup-manifest.json \
  | tee "$OUT.raw"

if grep -q "^MATCH:" "$OUT.raw"; then
  VERDICT=PASS
else
  VERDICT=FAIL
fi
echo "SUMMARY test=h5-longhorn-restore verdict=$VERDICT reason=restore-byte-diff"
