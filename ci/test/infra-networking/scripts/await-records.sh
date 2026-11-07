#!/bin/sh
# Runs on the chainsaw runner. Waits until the fake UniFi API holds (`present`) or no longer
# holds (`absent`) BOTH records external-dns owns for service/e2e-app/e2e-app-lb:
#   A    e2e-app-lb.cluster.example.com -> the Service's LoadBalancer address
#   TXT  the txt registry's ownership record naming owner k8s (the module's default
#        txtOwnerId) and resource service/e2e-app/e2e-app-lb
# `absent` requires both gone, because `policy: sync` deletes the ownership record with the
# record it owns; a TXT left behind would make the next owner's claim a conflict.
# Prints the store and exits non-zero when the budget runs out.
set -eu
want=$1
budget=${2:-150}
host=e2e-app-lb.cluster.example.com
ip=${3:-}

records() { kubectl get --raw /api/v1/namespaces/nodes/services/https:unifi:443/proxy/records; }
has_a() {
  if [ -n "$ip" ]; then printf '%s\n' "$1" | grep -qx "A_RECORD $host $ip"
  else printf '%s\n' "$1" | grep -q "^A_RECORD $host "; fi
}
has_txt() {
  printf '%s\n' "$1" | grep '^TXT_RECORD ' | grep 'external-dns/owner=k8s,' \
    | grep -Eq 'external-dns/resource=service/e2e-app/e2e-app-lb("|,|$)'
}

end=$(( $(date +%s) + budget ))
while :; do
  store=$(records || true)
  a=no txt=no
  has_a "$store" && a=yes
  has_txt "$store" && txt=yes
  case "$want:$a:$txt" in
    present:yes:yes | absent:no:no)
      echo "records for $host $want (A=$a TXT=$txt)"
      exit 0 ;;
  esac
  if [ "$(date +%s)" -ge "$end" ]; then
    echo "records for $host not $want after ${budget}s (A=$a TXT=$txt); store:" >&2
    printf '%s\n' "$store" >&2
    exit 1
  fi
  sleep 5
done
