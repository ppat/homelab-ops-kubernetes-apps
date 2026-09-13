#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${HERE}/../lib"

export STORED_FORM_NAMESPACE="versitygw"
export STORED_FORM_POD="versitygw-stored-form"
DEADLINE=180

PLAN="$("${HERE}/plan.sh")"
STORED_FORM_BUCKET="$(echo "$PLAN" | awk -F'\t' '$1 == "bucket" { print $2 }' | sed -n 1p)"
STORED_FORM_CLAIM="$(kubectl get cronjob -n "$STORED_FORM_NAMESPACE" versitygw-sweep \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}')"
STORED_FORM_OWNER="$(echo "$PLAN" | awk -F'\t' -v b="$STORED_FORM_BUCKET" '$1 == "bucket" && $2 == b { print $3 }')"
if [ -z "$STORED_FORM_BUCKET" ] || [ -z "$STORED_FORM_CLAIM" ] || [ -z "$STORED_FORM_OWNER" ]; then
  echo "FAIL: could not derive bucket/claim/access-key from live objects" >&2
  exit 1
fi
export STORED_FORM_BUCKET STORED_FORM_CLAIM STORED_FORM_OWNER

kubectl delete pod -n "$STORED_FORM_NAMESPACE" "$STORED_FORM_POD" --ignore-not-found --wait=true >/dev/null

kubectl create configmap versitygw-stored-form -n "$STORED_FORM_NAMESPACE" \
  --from-file=inspect.py="${HERE}/python/stored-form-inspect.py" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

"${LIB}/render-manifests.sh" "${HERE}/manifests/stored-form" | kubectl apply -f - >/dev/null

phase="$("${LIB}/await-pod.sh" "$STORED_FORM_NAMESPACE" "$STORED_FORM_POD" "$DEADLINE")"
kubectl logs -n "$STORED_FORM_NAMESPACE" "$STORED_FORM_POD"
if [ "$phase" != "Succeeded" ]; then
  echo "FAIL: the stored-form inspection reported failures" >&2
  exit 1
fi
