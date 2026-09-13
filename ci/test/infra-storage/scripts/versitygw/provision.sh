#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${HERE}/../lib"

export PROVISION_NAMESPACE="versitygw"
DEADLINE=300

PROVISION_REGION="$(kubectl get deployment -n "$PROVISION_NAMESPACE" versitygw \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="VGW_REGION")].value}')"
if [ -z "$PROVISION_REGION" ]; then
  echo "FAIL: could not read VGW_REGION off deployment/versitygw" >&2
  exit 1
fi
export PROVISION_REGION

kubectl create configmap versitygw-provision-scripts -n "$PROVISION_NAMESPACE" \
  --from-file=provision-plan.py="${HERE}/python/provision-plan.py" \
  --from-file=provision-store.sh="${HERE}/shell/provision-store.sh" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

run_provision() {
  export PROVISION_JOB="$1"
  kubectl delete job -n "$PROVISION_NAMESPACE" "$PROVISION_JOB" --ignore-not-found --wait=true >/dev/null
  "${LIB}/render-manifests.sh" "${HERE}/manifests/provision" | kubectl apply -f - >/dev/null

  local deadline succeeded failed
  deadline=$(( $(date +%s) + DEADLINE ))
  while :; do
    succeeded="$(kubectl get job -n "$PROVISION_NAMESPACE" "$PROVISION_JOB" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(kubectl get job -n "$PROVISION_NAMESPACE" "$PROVISION_JOB" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
    [ "${succeeded:-0}" -ge 1 ] 2>/dev/null && break
    if [ "${failed:-0}" -ge 3 ] 2>/dev/null; then
      echo "FAIL: job/${PROVISION_JOB} failed" >&2
      kubectl logs -n "$PROVISION_NAMESPACE" "job/${PROVISION_JOB}" --all-containers --tail=60 >&2 || true
      exit 1
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "FAIL: job/${PROVISION_JOB} did not complete within ${DEADLINE}s" >&2
      kubectl describe job -n "$PROVISION_NAMESPACE" "$PROVISION_JOB" >&2 || true
      kubectl logs -n "$PROVISION_NAMESPACE" "job/${PROVISION_JOB}" --all-containers --tail=60 >&2 || true
      exit 1
    fi
    sleep 3
  done
  kubectl logs -n "$PROVISION_NAMESPACE" "job/${PROVISION_JOB}" --all-containers
}

echo "=== provisioning from the full document ===" >&2
run_provision versitygw-provision-full

document() { kubectl get secret -n "$PROVISION_NAMESPACE" versitygw-provisioning -o jsonpath='{.data.provisioning\.yaml}' | base64 -d; }
plan() { document | python3 "${HERE}/python/provision-plan.py" 2>/dev/null; }

document > /tmp/versitygw-document-full.yaml

# Two assertions follow, not one: asserting the account's removal alone passes
# equally against logic that deleted the bucket too.
DROPPED_BUCKET="$(plan | awk -F'\t' '$1 == "bucket" { print $2 }' | tail -1)"
DROPPED_ACCOUNT="$(plan | awk -F'\t' -v b="$DROPPED_BUCKET" '$1 == "bucket" && $2 == b { print $3 }')"
if [ -z "$DROPPED_ACCOUNT" ] || [ -z "$DROPPED_BUCKET" ]; then
  echo "FAIL: could not pick an account with a bucket to drop from the document" >&2
  exit 1
fi
echo "ok: will drop account ${DROPPED_ACCOUNT}, which owns bucket ${DROPPED_BUCKET}" >&2

document \
  | python3 -c "
import sys, yaml
doc = yaml.safe_load(sys.stdin.read())
dropped = '${DROPPED_ACCOUNT}'
doc['accounts'] = [a for a in doc['accounts'] if a['access'] != dropped]
doc['buckets'] = [b for b in doc['buckets'] if b['owner'] != dropped]
sys.stdout.write(yaml.safe_dump(doc, sort_keys=False))
" >/tmp/versitygw-reduced.yaml
kubectl create secret generic versitygw-provisioning -n "$PROVISION_NAMESPACE" \
  --from-file=provisioning.yaml=/tmp/versitygw-reduced.yaml \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "=== re-provisioning from the reduced document ===" >&2
run_provision versitygw-provision-reduced

reduced="$(kubectl logs -n "$PROVISION_NAMESPACE" job/versitygw-provision-reduced --all-containers 2>/dev/null || true)"

if ! echo "$reduced" | grep -q "removed account ${DROPPED_ACCOUNT}"; then
  echo "FAIL: the reduced document dropped account ${DROPPED_ACCOUNT}, but provisioning did not" >&2
  echo "      remove it. A consumer that should no longer have access still holds a live key." >&2
  exit 1
fi
echo "ok: the account removed from the document was removed from the gateway" >&2

listing="$(echo "$reduced" | awk '/--- buckets the gateway holds after this run ---/,0')"
if [ -z "$listing" ]; then
  echo "FAIL: the provisioning run printed no bucket listing, so bucket survival cannot be checked" >&2
  exit 1
fi
if ! echo "$listing" | grep -qw "$DROPPED_BUCKET"; then
  echo "FAIL: bucket ${DROPPED_BUCKET} is gone. Its owner was removed from the document, which" >&2
  echo "      must never remove the bucket: deleting a credential is reversible and deleting a" >&2
  echo "      bucket is not, and this store holds the only copy of every backup in the estate." >&2
  echo "$listing" >&2
  exit 1
fi
echo "ok: the bucket owned by the removed account still exists -- removal is scoped to accounts" >&2

kubectl create secret generic versitygw-provisioning -n "$PROVISION_NAMESPACE" \
  --from-file=provisioning.yaml=/tmp/versitygw-document-full.yaml \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

echo "=== restoring the full document ===" >&2
restored="$(run_provision versitygw-provision-restored)"
echo "$restored"
if ! echo "$restored" | grep -q "created account ${DROPPED_ACCOUNT}"; then
  echo "FAIL: restoring the document did not recreate account ${DROPPED_ACCOUNT}" >&2
  exit 1
fi
if ! echo "$restored" | grep -qE "(created|reassigned|already owned) .*${DROPPED_BUCKET}|bucket ${DROPPED_BUCKET} already owned by"; then
  echo "FAIL: restoring the document did not reattach bucket ${DROPPED_BUCKET} to an owner" >&2
  exit 1
fi
echo "ok: the removed account was recreated and its surviving bucket reattached" >&2
