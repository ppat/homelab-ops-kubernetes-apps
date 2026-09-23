#!/bin/sh
# Runs on the chainsaw runner. Prints, as one JSON object, the live values the in-cluster
# probe (e2e-probe.sh) must observe, so the probe compares what a client sees against what
# the controllers actually hold rather than against constants copied from the fixtures.
# Exits non-zero naming the first value that is empty: a probe bound to an empty
# expectation could only ever fail, and would fail with a misleading message.
set -eu

svc_ip() { kubectl -n "$1" get service "$2" -o jsonpath='{.status.loadBalancer.ingress[0].ip}'; }

traefik_ip=$(svc_ip traefik traefik)
dns_server=$(svc_ip dns pihole-dns-udp)
lb_ip=$(svc_ip e2e-app e2e-app-lb)
backend_pod=$(kubectl -n e2e-app get pod -l app.kubernetes.io/name=e2e-app \
  --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}')
ca_b64=$(kubectl -n traefik get secret default-tls-cert -o jsonpath='{.data.ca\.crt}')

for name in traefik_ip dns_server lb_ip backend_pod ca_b64; do
  eval "value=\${$name}"
  # shellcheck disable=SC2154 # assigned by the eval above
  [ -n "$value" ] || { echo "e2e-expectations: $name is empty" >&2; exit 1; }
done
case "$backend_pod" in
  *" "*) echo "e2e-expectations: expected one e2e-app pod, got: $backend_pod" >&2; exit 1 ;;
esac

printf '{"traefik_ip":"%s","dns_server":"%s","lb_ip":"%s","backend_pod":"%s","ca_b64":"%s"}\n' \
  "$traefik_ip" "$dns_server" "$lb_ip" "$backend_pod" "$ca_b64"
