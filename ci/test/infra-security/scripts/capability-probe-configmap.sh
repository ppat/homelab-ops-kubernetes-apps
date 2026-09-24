#!/bin/sh
# Runs on the chainsaw runner. Builds configmap/capability-probe for the in-cluster probe:
# the probe script, and the trust bundle copied byte for byte from the ConfigMap
# trust-manager writes into the external-secrets namespace -- the one every cluster's
# Bitwarden ClusterSecretStore names as its caProvider.
#
# The bundle travels as a file, not an env var: a Bundle that includes the default CAs is
# ~200KB, past the exec argument limit, and the pod would die before the probe could say why.
# `create`, not `apply`: the last-applied annotation cannot hold a bundle that size.
set -eu
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
kubectl -n external-secrets get configmap bitwarden-ca-cert -o jsonpath='{.data.ca\.crt}' \
  >"$dir/bundle.pem"
[ -s "$dir/bundle.pem" ] || {
  echo "capability-probe-configmap: external-secrets/bitwarden-ca-cert has no ca.crt" >&2
  exit 1
}
kubectl -n security-probe create configmap capability-probe \
  --from-file=probe.sh="$(dirname "$0")/capability-probe.sh" \
  --from-file=bundle.pem="$dir/bundle.pem"
