#!/bin/sh
# Runs INSIDE the e2e-probe Job pod (curlimages/curl: busybox awk + curl), not on the
# chainsaw runner. validate-e2e.yaml mounts it as a ConfigMap and binds every expected value
# into the environment from live cluster state.
#
# One line per leg: `E2E OK   [<leg>] ...` or `E2E FAIL [<leg>] ...`, then exit 1 on the
# first failure. A leg is a single hop a client depends on:
#   dns           the DNS provider (the fake UniFi API) holds an A record for the name, with
#                 the address the ingress controller or the LoadBalancer Service actually holds
#   https         Traefik routes the Ingress host to the app, presenting a certificate
#                 that verifies against the default-tls-cert CA
#   loadbalancer  the app's own LoadBalancer address reaches the app
set -u
T0=$(date +%s)
elapsed() { echo $(( $(date +%s) - T0 )); }
fail() { echo "E2E FAIL [$1] $2 (t+$(elapsed)s)"; exit 1; }

# Read from the records external-dns wrote, never the pod's resolv.conf: cluster DNS would
# answer from somewhere other than the provider. -k because the fake's certificate is not
# what is under test; the https leg below is where verification matters.
resolve() {
  end=$(( $(date +%s) + DNS_BUDGET_S )); got=
  while :; do
    got=$(curl -sk --max-time 5 "$RECORDS_URL" 2>/dev/null \
      | awk -v name="$1" '$1 == "A_RECORD" && $2 == name {print $3; exit}')
    [ "$got" = "$2" ] && break
    [ "$(date +%s)" -ge "$end" ] && fail dns "$1 in $RECORDS_URL is '${got:-absent}', want $2"
    sleep 5
  done
  echo "E2E OK   [dns] $1 -> $got in $RECORDS_URL (t+$(elapsed)s)"
}

# --fail makes a Traefik 404/503 an error; anything curl rejects (routing, TLS
# verification, refused connection) retries until the budget, then reports the
# last error verbatim.
fetch() {
  leg=$1; shift
  end=$(( $(date +%s) + CONNECT_BUDGET_S ))
  until curl -sS --fail --max-time 10 -o /tmp/body "$@" 2>/tmp/err; do
    [ "$(date +%s)" -ge "$end" ] && fail "$leg" "$(tr '\n' ' ' </tmp/err)"
    sleep 3
  done
  # whoami answers with its own pod name; a 200 from any other backend is not a pass.
  grep -qx "Hostname: $BACKEND_POD" /tmp/body \
    || fail "$leg" "backend is not $BACKEND_POD; body: $(tr '\n' '|' </tmp/body)"
  echo "E2E OK   [$leg] served by $BACKEND_POD (t+$(elapsed)s)"
}

echo "$CA_B64" | base64 -d >/tmp/ca.pem || fail setup "cannot decode default-tls-cert ca.crt"

resolve "$INGRESS_HOST" "$TRAEFIK_IP"
# --cacert, never -k: verification is what proves the default wildcard certificate
# is the one served for an Ingress with `tls: []`.
fetch https --cacert /tmp/ca.pem \
  --resolve "$INGRESS_HOST:443:$TRAEFIK_IP" "https://$INGRESS_HOST/"

resolve "$LB_HOST" "$LB_IP"
fetch loadbalancer --resolve "$LB_HOST:80:$LB_IP" "http://$LB_HOST/"
