#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${HERE}/../lib"

export SWEEP_NAMESPACE="versitygw"
JOB="versitygw-sweep-chainsaw"
DEADLINE=240

SWEEP_BUCKET="$("${HERE}/plan.sh" | awk -F'\t' '$1 == "bucket" { print $2 }' | sed -n 1p)"
SWEEP_CLAIM="$(kubectl get cronjob -n "$SWEEP_NAMESPACE" versitygw-sweep \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}')"
SWEEP_AGE_MINUTES="$(kubectl get cronjob -n "$SWEEP_NAMESPACE" versitygw-sweep \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="VERSITYGW_SWEEP_AGE_MINUTES")].value}')"
if [ -z "$SWEEP_BUCKET" ] || [ -z "$SWEEP_CLAIM" ] || [ -z "$SWEEP_AGE_MINUTES" ]; then
  echo "FAIL: could not derive bucket/claim/age from the sweep CronJob" >&2
  exit 1
fi
export SWEEP_BUCKET SWEEP_CLAIM SWEEP_AGE_MINUTES
echo "ok: sweep is configured with age_minutes=${SWEEP_AGE_MINUTES} over claim ${SWEEP_CLAIM}" >&2

kubectl create configmap versitygw-sweep-fixture -n "$SWEEP_NAMESPACE" \
  --from-file=fixture.py="${HERE}/python/sweep-fixture.py" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Both directions: a sweep that deletes nothing and one that deletes everything
# both leave a tree with no old residue, and only the second destroyed a backup.
run_fixture() {
  export SWEEP_MODE="$1"
  export SWEEP_POD="versitygw-sweep-${SWEEP_MODE}"
  kubectl delete pod -n "$SWEEP_NAMESPACE" "$SWEEP_POD" --ignore-not-found --wait=true >/dev/null
  "${LIB}/render-manifests.sh" "${HERE}/manifests/sweep-fixture" | kubectl apply -f - >/dev/null

  local phase
  phase="$("${LIB}/await-pod.sh" "$SWEEP_NAMESPACE" "$SWEEP_POD" "$DEADLINE")"
  kubectl logs -n "$SWEEP_NAMESPACE" "$SWEEP_POD"
  if [ "$phase" != "Succeeded" ]; then
    echo "FAIL: fixture ${SWEEP_MODE} reported failures" >&2
    exit 1
  fi
}

run_fixture seed

kubectl delete job -n "$SWEEP_NAMESPACE" "$JOB" --ignore-not-found --wait=true >/dev/null
kubectl create job -n "$SWEEP_NAMESPACE" "$JOB" --from="cronjob/versitygw-sweep" >/dev/null
echo "ok: created job/${JOB} from the sweep CronJob's own template" >&2

deadline=$(( $(date +%s) + DEADLINE ))
while :; do
  succeeded="$(kubectl get job -n "$SWEEP_NAMESPACE" "$JOB" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  failed="$(kubectl get job -n "$SWEEP_NAMESPACE" "$JOB" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
  [ "${succeeded:-0}" -ge 1 ] 2>/dev/null && break
  if [ "${failed:-0}" -ge 2 ] 2>/dev/null; then
    echo "FAIL: job/${JOB} failed" >&2
    kubectl logs -n "$SWEEP_NAMESPACE" "job/${JOB}" --tail=100 >&2 || true
    exit 1
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL: job/${JOB} did not complete within ${DEADLINE}s" >&2
    kubectl describe job -n "$SWEEP_NAMESPACE" "$JOB" >&2 || true
    kubectl logs -n "$SWEEP_NAMESPACE" "job/${JOB}" --tail=100 >&2 || true
    exit 1
  fi
  sleep 3
done

echo "--- sweep job output ---" >&2
kubectl logs -n "$SWEEP_NAMESPACE" "job/${JOB}"

run_fixture verify
