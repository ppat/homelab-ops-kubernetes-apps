#!/bin/bash
set -euo pipefail

# Judges the ReadWriteOnce round trip: the capability almost every longhorn consumer in the
# estate depends on. The pods in test-resources/ only report what they observed; every
# expected value here is read from live objects (the claim, its StorageClass, the PV, the
# longhorn Volume), never restated.
#
# One line per leg, `LONGHORN OK   [<leg>] ...` or `LONGHORN FAIL [<leg>] ...`, exit 1 on
# the first failure:
#   provision  the claim bound to a PV from the class's provisioner, backed by a longhorn
#              Volume carrying the class's replica count
#   attach     the writer's /data is the longhorn block device for that PV, formatted as the
#              class says -- not an emptyDir or overlay that happens to accept writes
#   write      random bytes written and synced
#   detach     the writer's attachment is gone and longhorn reports the volume detached, so
#              the next read cannot be served by the same attachment or page cache
#   expand     the detached volume grows when the claim does (every estate class sets
#              allowVolumeExpansion)
#   reattach   a new pod gets the same device back
#   persist    the bytes read back through the new attachment are the bytes written
#   resize     the filesystem the new pod sees was grown to match

NS="longhorn-probe"
PVC="test-pvc"
HERE="$(cd "$(dirname "$0")" && pwd)"
RESOURCES="${HERE}/../../test-resources"
EXPANDED="100Mi"
EXPANDED_BYTES=104857600
# Measured over 12 CI runs and the rig: writer done 14-19s after apply (provisioning
# included), reader 14-17s, detach 2-13s, expansion under 1s. POD_BUDGET_S is not sized from those alone: an
# attach that cannot succeed produces its first FailedAttachVolume event only after one to
# three minutes, and that event is what the timeout message reports.
POD_BUDGET_S=180
DETACH_BUDGET_S=60
EXPAND_BUDGET_S=60

T0=$(date +%s)
elapsed() { echo $(( $(date +%s) - T0 )); }
ok() { echo "LONGHORN OK   [$1] $2 (t+$(elapsed)s)"; }
fail() {
  echo "LONGHORN FAIL [$1] $2 (t+$(elapsed)s)"
  exit 1
}

lh_volume() { kubectl get volumes.longhorn.io -n longhorn-system "$1" -o jsonpath="$2" 2>/dev/null || true; }

# Waits for a pod to finish either way and requires Succeeded. On a timeout the pod's own
# Warning events carry the cause (FailedAttachVolume, FailedMount), so they are the message.
run_pod() {
  local pod="$1" leg="$2" end phase
  end=$(( $(date +%s) + POD_BUDGET_S ))
  while :; do
    phase="$(kubectl get pod -n "$NS" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
    Succeeded) return 0 ;;
    Failed) fail "$leg" "pod/${pod} failed: $(kubectl logs -n "$NS" "$pod" 2>&1 | tr '\n' '|')" ;;
    esac
    if [ "$(date +%s)" -ge "$end" ]; then
      fail "$leg" "pod/${pod} not finished after ${POD_BUDGET_S}s (phase=${phase:-none}); last warning: $(
        kubectl get events -n "$NS" --field-selector "involvedObject.name=${pod},type=Warning" \
          --sort-by=.lastTimestamp -o jsonpath='{range .items[-1:]}{.reason}: {.message}{end}' 2>/dev/null
      ); longhorn volume state: '$(lh_volume "$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.spec.volumeName}')" '{.status.state}')'"
    fi
    sleep 2
  done
}

# `report <pod> <KEY>` prints the fields after KEY on the pod's `KEY ...` line.
report() { kubectl logs -n "$NS" "$1" | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }'; }

# ---- provision + attach + write ------------------------------------------------------------
run_pod rwo-writer attach

sc="$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.spec.storageClassName}')"
provisioner="$(kubectl get storageclass "$sc" -o jsonpath='{.provisioner}')"
fs_type="$(kubectl get storageclass "$sc" -o jsonpath='{.parameters.fsType}')"
replicas="$(kubectl get storageclass "$sc" -o jsonpath='{.parameters.numberOfReplicas}')"
pv="$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.spec.volumeName}')"
[ -n "$pv" ] || fail provision "pvc/${PVC} has no volumeName"
driver="$(kubectl get pv "$pv" -o jsonpath='{.spec.csi.driver}')"
[ "$driver" = "$provisioner" ] \
  || fail provision "pv/${pv} came from csi driver '${driver}', class ${sc} names '${provisioner}'"
lh_replicas="$(lh_volume "$pv" '{.spec.numberOfReplicas}')"
[ "$lh_replicas" = "$replicas" ] \
  || fail provision "longhorn volume ${pv} has numberOfReplicas '${lh_replicas}', class ${sc} asks for '${replicas}'"
ok provision "pvc/${PVC} -> pv/${pv} via ${driver}, ${lh_replicas} replica(s)"

device="/dev/longhorn/${pv}"
read -r w_src w_fs w_opts <<<"$(report rwo-writer MOUNT)"
[ "${w_src:-}" = "$device" ] || fail attach "writer's /data is '${w_src:-not a mount}', want ${device}"
[ "${w_fs:-}" = "$fs_type" ] || fail attach "writer's /data is ${w_fs:-?}, class ${sc} says ${fs_type}"
case "${w_opts:-}" in rw,* | rw) ;; *) fail attach "writer's /data is mounted '${w_opts:-}', not rw" ;; esac
ok attach "writer mounted ${device} as ${w_fs} (${w_opts%%,*})"

w_sha="$(report rwo-writer SHA)"
w_kb="$(report rwo-writer SIZE_KB)"
[[ "$w_sha" =~ ^[0-9a-f]{64}$ ]] || fail write "writer reported no checksum: '${w_sha}'"
ok write "8 MiB written, sha256 ${w_sha:0:16}..., filesystem ${w_kb} KiB"

# ---- detach ---------------------------------------------------------------------------------
end=$(( $(date +%s) + DETACH_BUDGET_S ))
while :; do
  attachments="$(kubectl get volumeattachments \
    -o jsonpath="{range .items[?(@.spec.source.persistentVolumeName=='${pv}')]}{.metadata.name} {end}")"
  state="$(lh_volume "$pv" '{.status.state}')"
  [ -z "$attachments" ] && [ "$state" = "detached" ] && break
  [ "$(date +%s)" -lt "$end" ] \
    || fail detach "after ${DETACH_BUDGET_S}s: volumeattachments='${attachments}' longhorn state='${state}'"
  sleep 2
done
ok detach "no VolumeAttachment for ${pv}; longhorn reports it detached"

# ---- expand while detached ------------------------------------------------------------------
kubectl patch pvc -n "$NS" "$PVC" --type merge -p "{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"${EXPANDED}\"}}}}" >/dev/null
end=$(( $(date +%s) + EXPAND_BUDGET_S ))
until [ "$(lh_volume "$pv" '{.spec.size}')" = "$EXPANDED_BYTES" ]; do
  [ "$(date +%s)" -lt "$end" ] \
    || fail expand "longhorn volume ${pv} size is '$(lh_volume "$pv" '{.spec.size}')' after ${EXPAND_BUDGET_S}s, want ${EXPANDED_BYTES}"
  sleep 2
done
ok expand "longhorn volume ${pv} grown to ${EXPANDED} while detached"

# ---- reattach + persist + resize ------------------------------------------------------------
kubectl apply -f "${RESOURCES}/longhorn-reader.yaml" >/dev/null
run_pod rwo-reader reattach
read -r r_src r_fs _ <<<"$(report rwo-reader MOUNT)"
[ "${r_src:-}" = "$device" ] || fail reattach "reader's /data is '${r_src:-not a mount}', want ${device}"
[ "${r_fs:-}" = "$fs_type" ] || fail reattach "reader's /data is ${r_fs:-?}, want ${fs_type}"
ok reattach "a new pod mounted ${device} again"

r_sha="$(report rwo-reader SHA)"
[ "$r_sha" = "$w_sha" ] || fail persist "read back sha256 '${r_sha}', wrote ${w_sha}"
ok persist "sha256 matches across detach and re-attach"

r_kb="$(report rwo-reader SIZE_KB)"
# More than 1.5x what the writer saw: ext4 overhead keeps it below the full 2x.
[ "${r_kb:-0}" -gt $(( w_kb * 3 / 2 )) ] || fail resize "filesystem is ${r_kb:-?} KiB after expansion, was ${w_kb} KiB"
# The claim's status trails the filesystem: kubelet grows the filesystem at mount, and the
# resize controller records the new capacity on the claim afterwards.
end=$(( $(date +%s) + 30 ))
until [ "$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.status.capacity.storage}')" = "$EXPANDED" ]; do
  [ "$(date +%s)" -lt "$end" ] || fail resize "pvc/${PVC} reports capacity '$(
    kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.status.capacity.storage}')' 30s after the resize, want ${EXPANDED}"
  sleep 1
done
capacity="$EXPANDED"
ok resize "filesystem ${w_kb} -> ${r_kb} KiB; pvc/${PVC} capacity ${capacity}"
