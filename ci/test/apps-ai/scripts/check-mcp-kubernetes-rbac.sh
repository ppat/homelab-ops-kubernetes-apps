#!/bin/bash
set -euo pipefail

# Makes pre-requisites/mcp-kubernetes-rbac.yaml (a hand-synced copy of the ClusterRole
# the clusters repo actually binds -- see that file's header comment) load-bearing:
# nothing else in this suite asserts what the mcp-kubernetes-homelab / mcp-kubernetes-nas
# identities can actually reach, so a fixture that silently drifted permissive would
# still pass CI. This runs "kubectl auth can-i --as=<identity>" checks against both and
# fails on any mismatch.

FAILED=0

# Subresources MUST be passed as --subresource=x, never as "resource/x": kubectl splits
# that shorthand into resource + resource NAME, so "get nodes/proxy" asks whether the
# identity can get a Node object literally named "proxy" -- which the blanket nodes grant
# allows, making the check silently pass or fail for reasons unrelated to the subresource.
#
# check <identity> <verb> <resource> <expected: yes|no> [extra kubectl-auth-can-i args...]
check() {
  local identity="$1" verb="$2" resource="$3" expected="$4"
  shift 4
  local result
  if kubectl auth can-i "$verb" "$resource" --as="$identity" "$@" >/dev/null 2>&1; then
    result="yes"
  else
    result="no"
  fi
  if [ "$result" != "$expected" ]; then
    echo "FAIL: --as=$identity can-i $verb $resource $* => got '$result', expected '$expected'" >&2
    FAILED=1
  else
    echo "ok: --as=$identity can-i $verb $resource $* => $result"
  fi
}

check_identity() {
  local identity="$1"

  # Must be denied: Secrets, exec/delete/patch write paths, RBAC/token escalation
  # oracles, and nodes/proxy (the kubelet-proxy grant dropped for being exec-equivalent
  # -- GET routes it exposes include /exec, /attach, /portForward).
  check "$identity" get secrets no --all-namespaces
  check "$identity" list secrets no -n ai
  check "$identity" create pods no --subresource=exec --all-namespaces
  check "$identity" delete pods no --all-namespaces
  check "$identity" create subjectaccessreviews no
  check "$identity" create tokenreviews no
  check "$identity" patch deployments no --all-namespaces
  check "$identity" get nodes no --subresource=proxy
  # generators.external-secrets.io is granted as an explicit kind list rather than "*"
  # precisely to keep these two out: fakes.spec.data is literal plaintext key/value
  # pairs and webhooks.spec.headers can carry an inline API key. A regression to "*"
  # would silently re-grant both, so assert them individually.
  check "$identity" get fakes.generators.external-secrets.io no --all-namespaces
  check "$identity" get webhooks.generators.external-secrets.io no --all-namespaces

  # Must be allowed: the read-only surface the MCP tools actually rely on.
  check "$identity" list nodes yes
  check "$identity" get pods yes --subresource=log --all-namespaces
  check "$identity" list customresourcedefinitions yes
  check "$identity" list persistentvolumes yes
  check "$identity" list storageclasses yes
  check "$identity" create selfsubjectaccessreviews yes
}

check_identity "system:serviceaccount:ai:mcp-kubernetes-homelab"
check_identity "system:serviceaccount:mcp-access:mcp-kubernetes-nas"

if [ "$FAILED" -ne 0 ]; then
  echo "one or more mcp-kubernetes-readonly RBAC checks failed (see FAIL lines above)" >&2
  exit 1
fi
