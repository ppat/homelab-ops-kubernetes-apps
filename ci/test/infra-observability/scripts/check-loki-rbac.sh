#!/bin/bash
set -euo pipefail

# Asserts the loki ServiceAccount's effective RBAC via `kubectl auth can-i --as`
# rather than reading the ClusterRole's `.rules` YAML - same "check()" pattern as
# ci/test/apps-ai/scripts/check-mcp-kubernetes-rbac.sh. This is what catches a
# postRenderers patch whose target silently stops matching (a no-op, not an error -
# `kubectl kustomize` exits 0 and leaves the ClusterRole untouched). See
# helm-release-loki.yaml's "Ruler recording rules" comment for the full RBAC rationale
# and how that patch narrows the chart's ClusterRole from ["configmaps", "secrets"]
# down to ["configmaps"] only.

FAILED=0

# check <verb> <resource> <expected: yes|no> [extra kubectl-auth-can-i args...]
check() {
  local verb="$1" resource="$2" expected="$3"
  shift 3
  local result
  if kubectl auth can-i "$verb" "$resource" --as="system:serviceaccount:logging:loki" "$@" >/dev/null 2>&1; then
    result="yes"
  else
    result="no"
  fi
  if [ "$result" != "$expected" ]; then
    echo "FAIL: --as=system:serviceaccount:logging:loki can-i $verb $resource $* => got '$result', expected '$expected'" >&2
    FAILED=1
  else
    echo "ok: --as=system:serviceaccount:logging:loki can-i $verb $resource $* => $result"
  fi
}

# Must be allowed: sidecar.rules.searchNamespace: ALL depends on this cluster-wide.
check get configmaps yes --all-namespaces
check watch configmaps yes --all-namespaces
check list configmaps yes --all-namespaces

# Must be denied: the postRenderers patch's entire point.
check get secrets no --all-namespaces
check watch secrets no --all-namespaces
check list secrets no --all-namespaces
check get secrets no -n kube-system

if [ "$FAILED" -ne 0 ]; then
  echo "one or more loki RBAC checks failed (see FAIL lines above)" >&2
  exit 1
fi
