#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${HERE}/../lib"

export GUARD_NAMESPACE="versitygw"
export GUARD_POD="versitygw-xattr-guard"
DEADLINE=180

GUARD_CLAIM="$(kubectl get cronjob -n "$GUARD_NAMESPACE" versitygw-sweep \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}')"
if [ -z "$GUARD_CLAIM" ]; then
  echo "FAIL: could not derive the data claim name" >&2
  exit 1
fi
export GUARD_CLAIM

kubectl delete pod -n "$GUARD_NAMESPACE" "$GUARD_POD" --ignore-not-found --wait=true >/dev/null
"${LIB}/render-manifests.sh" "${HERE}/manifests/xattr-guard" | kubectl apply -f - >/dev/null

phase="$("${LIB}/await-pod.sh" "$GUARD_NAMESPACE" "$GUARD_POD" "$DEADLINE")"
output="$(kubectl logs -n "$GUARD_NAMESPACE" "$GUARD_POD" 2>&1 || true)"
echo "--- guard output against a read-only mount ---"
echo "$output"

if [ "$phase" = "Succeeded" ]; then
  echo "FAIL: the xattr guard PASSED against a read-only mount. It cannot fail, so a green" >&2
  echo "      init container is no evidence that the gateway root is writable." >&2
  exit 1
fi

if ! echo "$output" | grep -q "EROFS"; then
  echo "FAIL: the guard failed, but not with EROFS -- it did not detect the read-only mount," >&2
  echo "      it broke for some other reason, so this run is no evidence about the guard." >&2
  exit 1
fi
echo "ok: the xattr guard failed on a read-only mount and named EROFS as the reason"
