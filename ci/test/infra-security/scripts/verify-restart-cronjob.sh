#!/bin/bash
set -euo pipefail

NAMESPACE="external-secrets"
SERVICE_ACCOUNT="external-secrets-restart"
CRONJOB="external-secrets-restart"

FAILED=0

# check <verb> <resource> <expected: yes|no> [extra kubectl-auth-can-i args...]
#
# Ground truth for "RBAC scoped as tightly as it can be" -- asserting the Role's own
# `rules` only proves the object was written as intended, not that the RoleBinding
# actually attaches it to this ServiceAccount and nothing broader also does. can-i
# evaluates the live authorizer, so it also catches a RoleBinding typo or an unrelated
# grant elsewhere covering the same identity.
check() {
  local verb="$1" resource="$2" expected="$3"
  shift 3
  local result
  if kubectl auth can-i "$verb" "$resource" \
    --as="system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}" \
    -n "$NAMESPACE" "$@" >/dev/null 2>&1; then
    result="yes"
  else
    result="no"
  fi
  if [ "$result" != "$expected" ]; then
    echo "FAIL: can-i $verb $resource $* => got '$result', expected '$expected'" >&2
    FAILED=1
  else
    echo "ok: can-i $verb $resource $* => $result"
  fi
}

check_rbac() {
  # Must be allowed: exactly what `kubectl rollout restart deployment -n external-secrets`
  # (no resource name) does -- list to enumerate every Deployment, get + patch to restart
  # each one.
  check list deployments.apps yes
  check get deployments.apps yes
  check patch deployments.apps yes

  # Must be denied: nothing else, on Deployments or otherwise. In particular no
  # create/delete/update on Deployments (rollout restart never calls them) and no access
  # to a different resource in the same namespace -- proves the grant is scoped to
  # Deployments specifically, not to "everything in this namespace".
  check create deployments.apps no
  check delete deployments.apps no
  check update deployments.apps no
  check get secrets no
  check list pods no

  if [ "$FAILED" -ne 0 ]; then
    echo "external-secrets-restart RBAC check failed (see FAIL lines above)" >&2
    exit 1
  fi
}

# Drives one real Job from the CronJob's own jobTemplate and asserts the necessary
# consequence of a working restart: `kubectl.kubernetes.io/restartedAt` appears on every
# Deployment's pod template. This is the one thing "the CronJob object exists with the
# right schedule" cannot prove -- that the ServiceAccount/Role/RoleBinding triple actually
# lets the container do the restart when it runs.
trigger_and_verify() {
  local job_name="verify-external-secrets-restart"

  kubectl create job "$job_name" \
    --from="cronjob/${CRONJOB}" \
    -n "$NAMESPACE"

  if ! kubectl wait "job/${job_name}" -n "$NAMESPACE" \
    --for=condition=complete --timeout=2m; then
    echo "FAIL: job/${job_name} did not reach condition=complete within 2m" >&2
    kubectl describe "job/${job_name}" -n "$NAMESPACE" >&2 || true
    kubectl logs "job/${job_name}" -n "$NAMESPACE" --all-containers >&2 || true
    exit 1
  fi

  local deployments
  deployments="$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')"
  if [ -z "$deployments" ]; then
    echo "FAIL: no Deployments found in ${NAMESPACE} -- nothing for the restart to have acted on" >&2
    exit 1
  fi

  local name restarted_at
  for name in $deployments; do
    restarted_at="$(kubectl get "deployment/${name}" -n "$NAMESPACE" \
      -o jsonpath='{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}')"
    if [ -z "$restarted_at" ]; then
      echo "FAIL: deployment/${name} carries no kubectl.kubernetes.io/restartedAt annotation after the Job ran" >&2
      FAILED=1
    else
      echo "ok: deployment/${name} restartedAt=${restarted_at}"
    fi
  done

  if [ "$FAILED" -ne 0 ]; then
    echo "external-secrets-restart Job ran but did not restart every Deployment (see FAIL lines above)" >&2
    exit 1
  fi
}

case "${1:-}" in
  --rbac)
    check_rbac
    ;;
  --trigger)
    trigger_and_verify
    ;;
  *)
    echo "usage: verify-restart-cronjob.sh --rbac|--trigger" >&2
    exit 1
    ;;
esac
