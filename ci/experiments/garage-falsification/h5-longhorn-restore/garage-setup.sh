#!/usr/bin/env bash
# H5 step 1: stand up the Garage instance (garage.yaml) on sandbox-talos and bootstrap its
# single-node RF1 layout, backup bucket, and access key. Mirrors the `docker exec /garage
# ...` bootstrap sequence h2/h4 use against their docker-based Garage containers, adapted to
# `kubectl exec` since this cell runs as a Kubernetes Deployment instead.
#
# Deliberately its own namespace (h5-garage): sandbox-talos already had `garage` and
# `garage-operator-system` namespaces in use by an unrelated, actively-reconciling Flux
# Kustomization (infra-storage-object-core, a chainsaw test run for the real production
# module under separate development) when this test was built -- those must not be touched.
#
# Writes access/secret key + bucket + region to creds.env for garage-region-check.py and
# the (blocked, see NOTES.md) backup/restore driver to source.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX=sandbox-talos
NS=h5-garage
BUCKET=h5-longhorn-backup
KEY_NAME=h5-longhorn-key
REGION=garage # MUST exactly match the region given to Longhorn's BackupTarget -- see NOTES.md

kubectl --context "$CTX" apply -f "$HERE/garage.yaml"
kubectl --context "$CTX" rollout status deployment/garage -n "$NS" --timeout=90s

POD=$(kubectl --context "$CTX" get pods -n "$NS" -l app=garage -o jsonpath='{.items[0].metadata.name}')

# idempotent: layout assign/apply only makes sense once. `garage status` prints
# "NO ROLE ASSIGNED" in the node's row until a layout is applied -- that's the signal to
# check (status shows the node's SHORT id, so matching against the full id from `node id`
# doesn't work here).
NODE_ID=$(kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage node id -q | cut -d@ -f1)
if kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage status 2>&1 | grep -q "NO ROLE ASSIGNED"; then
  kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage layout assign -z dc1 -c 2G "$NODE_ID"
  kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage layout apply --version 1
fi

kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage bucket create "$BUCKET" 2>&1 | grep -v "already exists" || true
# `key create` is NOT idempotent by name (each call mints a fresh key, even if a key with
# the same --name already exists) -- confirmed the hard way: a naive unconditional
# `key create` here left two access keys both named h5-longhorn-key, and the next `key
# info` failed with "InvalidRequest: 2 matching keys". Only create if none exists yet.
if ! kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage key info "$KEY_NAME" >/dev/null 2>&1; then
  kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage key create "$KEY_NAME"
fi
kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage bucket allow --read --write --owner "$BUCKET" --key "$KEY_NAME"

INFO=$(kubectl --context "$CTX" exec -n "$NS" "$POD" -- /garage key info "$KEY_NAME" --show-secret)
ACCESS=$(echo "$INFO" | grep "Key ID:" | awk '{print $NF}')
SECRET=$(echo "$INFO" | grep "Secret key:" | awk '{print $NF}')

cat > "$HERE/creds.env" <<EOF
GARAGE_NS=$NS
GARAGE_BUCKET=$BUCKET
GARAGE_REGION=$REGION
GARAGE_ACCESS_KEY=$ACCESS
GARAGE_SECRET_KEY=$SECRET
GARAGE_S3_ENDPOINT_INCLUSTER=http://garage.$NS.svc.cluster.local:3900
EOF
echo "wrote $HERE/creds.env"
echo "bucket=$BUCKET region=$REGION access=$ACCESS"
