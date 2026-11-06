#!/bin/sh
# Runs on the chainsaw runner. Waits for the external-secrets controller to log the
# ClusterSecretStore refusing the ExternalSecret in security-probe-denied, and prints the
# matching line so a green step shows what it matched. Exits non-zero if none appears.
set -eu

for _ in $(seq 1 16); do
  if line=$(kubectl -n external-secrets logs deploy/external-secrets --since=10m \
      | grep 'security-probe-denied' | grep -m 1 'denied by spec.condition'); then
    echo "$line"
    exit 0
  fi
  sleep 5
done

echo "no 'denied by spec.condition' error for namespace security-probe-denied in the controller log" >&2
exit 1
