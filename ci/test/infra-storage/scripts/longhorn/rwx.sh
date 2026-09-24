#!/bin/bash
set -euo pipefail

# Judges the ReadWriteMany path, which longhorn serves differently from RWO: a share-manager
# pod attaches the block volume and exports it over NFS, and each consumer mounts that
# export. Expected values come from live objects, as in rwo.sh.
#
#   provision  the claim bound to a PV from the class's provisioner, backed by an rwx
#              longhorn Volume
#   mount      both pods' /data is the NFS export of that volume's share-manager Service,
#              mounted with every option the class's nfsOptions asks for
#   share      a token written by one pod was read by the other and acknowledged back while
#              the first still had the volume mounted -- two pods using it at once, which is
#              the property RWX exists for

NS="longhorn-probe"
PVC="test-pvc-rwx"
POD_BUDGET_S=180

T0=$(date +%s)
elapsed() { echo $(( $(date +%s) - T0 )); }
ok() { echo "LONGHORN OK   [rwx-$1] $2 (t+$(elapsed)s)"; }
fail() {
  echo "LONGHORN FAIL [rwx-$1] $2 (t+$(elapsed)s)"
  exit 1
}

run_pod() {
  local pod="$1" end phase
  end=$(( $(date +%s) + POD_BUDGET_S ))
  while :; do
    phase="$(kubectl get pod -n "$NS" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
    Succeeded) return 0 ;;
    Failed) fail share "pod/${pod} failed: $(kubectl logs -n "$NS" "$pod" 2>&1 | tr '\n' '|')" ;;
    esac
    if [ "$(date +%s)" -ge "$end" ]; then
      fail mount "pod/${pod} not finished after ${POD_BUDGET_S}s (phase=${phase:-none}); last warning: $(
        kubectl get events -n "$NS" --field-selector "involvedObject.name=${pod},type=Warning" \
          --sort-by=.lastTimestamp -o jsonpath='{range .items[-1:]}{.reason}: {.message}{end}' 2>/dev/null)"
    fi
    sleep 2
  done
}
report() { kubectl logs -n "$NS" "$1" | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }'; }

run_pod rwx-a
run_pod rwx-b

sc="$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.spec.storageClassName}')"
provisioner="$(kubectl get storageclass "$sc" -o jsonpath='{.provisioner}')"
nfs_options="$(kubectl get storageclass "$sc" -o jsonpath='{.parameters.nfsOptions}')"
pv="$(kubectl get pvc -n "$NS" "$PVC" -o jsonpath='{.spec.volumeName}')"
[ -n "$pv" ] || fail provision "pvc/${PVC} has no volumeName"
driver="$(kubectl get pv "$pv" -o jsonpath='{.spec.csi.driver}')"
[ "$driver" = "$provisioner" ] \
  || fail provision "pv/${pv} came from csi driver '${driver}', class ${sc} names '${provisioner}'"
access_mode="$(kubectl get volumes.longhorn.io -n longhorn-system "$pv" -o jsonpath='{.spec.accessMode}')"
[ "$access_mode" = "rwx" ] || fail provision "longhorn volume ${pv} has accessMode '${access_mode}', want rwx"
ok provision "pvc/${PVC} -> pv/${pv} via ${driver}, longhorn accessMode ${access_mode}"

export_ip="$(kubectl get service -n longhorn-system "$pv" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
[ -n "$export_ip" ] || fail mount "no share-manager service/${pv} in longhorn-system"
want_src="${export_ip}:/${pv}"
for pod in rwx-a rwx-b; do
  read -r src fs opts <<<"$(report "$pod" MOUNT)"
  [ "${src:-}" = "$want_src" ] || fail mount "${pod}'s /data is '${src:-not a mount}', want ${want_src}"
  [ "${fs:-}" = "nfs4" ] || fail mount "${pod}'s /data is ${fs:-?}, want nfs4"
  IFS=',' read -r -a wanted <<<"$nfs_options"
  for opt in "${wanted[@]}"; do
    case ",${opts}," in *",${opt},"*) ;; *) fail mount "${pod}'s mount lacks '${opt}' from nfsOptions: ${opts}" ;; esac
  done
done
ok mount "rwx-a and rwx-b both mounted ${want_src} with ${nfs_options}"

token="$(report rwx-a TOKEN)"
[[ "$token" =~ ^[0-9a-f]{32}$ ]] || fail share "rwx-a reported no token: '${token}'"
[ "$(report rwx-b SAW)" = "$token" ] || fail share "rwx-b read '$(report rwx-b SAW)', rwx-a wrote ${token}"
[ "$(report rwx-a ACK)" = "$token" ] || fail share "rwx-a never saw rwx-b's acknowledgement"
ok share "token ${token:0:8}... crossed from rwx-a to rwx-b and back while both were mounted"
