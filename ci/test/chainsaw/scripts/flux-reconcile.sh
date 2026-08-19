#!/bin/bash
set -euo pipefail

RESOURCE_TYPE=""
RESOURCE_NAME=""
NAMESPACE="flux-system"
TIMEOUT="1m"

# Parse parameters
for param in "$@"
do
  case $param in
    --resource-type=*)
      RESOURCE_TYPE="${param#*=}"
      shift
      ;;
    --resource-name=*)
      RESOURCE_NAME="${param#*=}"
      shift
      ;;
    --namespace=*)
      NAMESPACE="${param#*=}"
      shift
      ;;
    --timeout=*)
      TIMEOUT="${param#*=}"
      shift
      ;;
    *)
      echo "Unknown parameter: $param"
      exit 1
      ;;
  esac
done

# Wait for the object to EXIST before reconciling it.
#
# `flux reconcile` does not wait -- it exits 1 immediately with `... "<name>" not found`. Most of
# these objects are created by a PARENT Kustomization applied moments earlier, so whether the
# child exists yet is a race rather than a precondition. It was previously masked: the bootstrap
# CRD bundle used to be part of the `pre-requisites` build, and that large slow apply padded the
# preceding step for long enough that the child was always there by the time this ran. Removing
# it (see apply-bootstrap-crds.sh) took the padding away and the race surfaced -- one suite in one
# of two otherwise identical fleet runs, which is what a race looks like.
#
# So this is not a workaround for that change; it is the missing wait that change revealed. The
# same budget bounds both phases, because "the object never appeared" and "the object never
# became ready" are the same failure from the caller's point of view.
case "${TIMEOUT}" in
  *h) timeout_s=$(( ${TIMEOUT%h} * 3600 )) ;;
  *m) timeout_s=$(( ${TIMEOUT%m} * 60 )) ;;
  *s) timeout_s=${TIMEOUT%s} ;;
  *)  timeout_s="${TIMEOUT}" ;;
esac

deadline=$(( $(date +%s) + timeout_s ))
until kubectl get "${RESOURCE_TYPE}" "${RESOURCE_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; do
  now=$(date +%s)
  if [ "${now}" -ge "${deadline}" ]; then
    # Say which of the two phases failed. A bare `not found` here would otherwise be read as
    # "the object is broken" when the truth is "nothing ever created it".
    echo "flux-reconcile: ${RESOURCE_TYPE}/${RESOURCE_NAME} in ${NAMESPACE} never appeared within ${TIMEOUT}" >&2
    kubectl get "${RESOURCE_TYPE}" -n "${NAMESPACE}" 2>&1 | head -20 >&2 || true
    exit 1
  fi
  # Liveness, not just a condition: a silent wait is indistinguishable from a hang.
  echo "flux-reconcile: waiting for ${RESOURCE_TYPE}/${RESOURCE_NAME} to appear ($(( deadline - now ))s left)" >&2
  sleep 5
done

flux reconcile $RESOURCE_TYPE $RESOURCE_NAME -n $NAMESPACE --timeout $TIMEOUT
