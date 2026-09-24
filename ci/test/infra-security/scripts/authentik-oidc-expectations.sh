#!/bin/sh
# Runs on the chainsaw runner. Prints, as one JSON object, the live values the OIDC probe
# (authentik-oidc-probe.py) and the relying party must be bound to, so they are compared
# against what the cluster actually holds rather than constants copied from the fixtures:
#   issuer_host   the authentik Ingress host -- the host consumers put in their issuer URL
#   authentik_ip  the authentik-server Service, which issuer_host resolves to in-pod
#   cert_b64      the cert-manager signing certificate (authentik-signing-cert tls.crt)
# It also creates secret/authentik-oidc-e2e holding this run's random credentials and the
# bootstrap token authentik-server actually runs with, none of which are printed.
# Exits non-zero naming the first value that is empty: a probe bound to an empty
# expectation could only ever fail, and would fail with a misleading message.
set -eu

ns=authentik-oidc-e2e

issuer_host=$(kubectl -n authentik get ingress authentik-server -o jsonpath='{.spec.rules[0].host}')
authentik_ip=$(kubectl -n authentik get service authentik-server -o jsonpath='{.spec.clusterIP}')
cert_b64=$(kubectl -n authentik get secret authentik-signing-cert -o jsonpath='{.data.tls\.crt}')
admin_token=$(kubectl -n authentik get deployment authentik-server \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="AUTHENTIK_BOOTSTRAP_TOKEN")].value}')

for name in issuer_host authentik_ip cert_b64 admin_token; do
  eval "value=\${$name}"
  # shellcheck disable=SC2154 # assigned by the eval above
  [ -n "$value" ] || { echo "authentik-oidc-expectations: $name is empty" >&2; exit 1; }
done

rand() { head -c 24 /dev/urandom | base64 | tr -d '/+='; }
kubectl -n "$ns" create secret generic authentik-oidc-e2e \
  --from-literal=admin_token="$admin_token" \
  --from-literal=user_password="$(rand)" \
  --from-literal=client_id="$(rand)" \
  --from-literal=client_secret="$(rand)$(rand)" \
  --dry-run=client -o yaml | kubectl apply -f - >&2

printf '{"issuer_host":"%s","authentik_ip":"%s","cert_b64":"%s"}\n' \
  "$issuer_host" "$authentik_ip" "$cert_b64"
