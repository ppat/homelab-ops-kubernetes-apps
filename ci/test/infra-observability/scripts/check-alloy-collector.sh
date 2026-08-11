#!/bin/bash
set -euo pipefail

# Everything in here exists because the failure modes found while building this component
# all produced a green, error-free Alloy that collected nothing or dropped a label. A
# Ready DaemonSet proves almost nothing about this workload, so these checks look at what
# the collector actually loaded and what its identity can actually reach.
#
# Checked here, in order:
#   1. the cluster-injected fragment landed in the ConfigMap byte-for-byte,
#   2. every collector pod loaded a non-empty component graph containing every component
#      the module and the fragment declare, in both directions across files,
#   3. every one of those components reports healthy,
#   4. the ServiceAccount can watch pods but cannot read secrets or configmaps.

NAMESPACE=logging
SERVICE_ACCOUNT=alloy
CONFIG_MAP=alloy-config
FRAGMENT_KEY=cluster-pvc-logs.alloy
FRAGMENT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pre-requisites/alloy/conf.d/${FRAGMENT_KEY}"

FAILED=0

fail() {
  echo "FAIL: $*" >&2
  FAILED=1
}

ok() {
  echo "ok: $*"
}

# ----------------------------------------------------------------------------------------
# 1. The seam fragment reached the ConfigMap unchanged.
# ----------------------------------------------------------------------------------------
check_fragment_injected() {
  local injected
  injected="$(kubectl get configmap "$CONFIG_MAP" -n "$NAMESPACE" -o "jsonpath={.data['${FRAGMENT_KEY//./\\.}']}")"
  if [ -z "$injected" ]; then
    fail "configmap/$CONFIG_MAP has no '$FRAGMENT_KEY' key - the cluster seam patch did not apply"
    return
  fi
  # Compared through command substitution on both sides, which strips trailing newlines:
  # the `patch: |-` block that carries the fragment into the ConfigMap drops the file's
  # final newline, and that difference is not one worth failing on.
  if [ "$injected" != "$(cat "$FRAGMENT_FILE")" ]; then
    fail "'$FRAGMENT_KEY' in configmap/$CONFIG_MAP differs from $FRAGMENT_FILE"
    diff -u "$FRAGMENT_FILE" <(printf '%s\n' "$injected") >&2 || true
    return
  fi
  ok "cluster fragment '$FRAGMENT_KEY' injected into configmap/$CONFIG_MAP unchanged"
}

# ----------------------------------------------------------------------------------------
# 2 + 3. The collector actually built a component graph from that directory.
#
# This is the check that catches the configuration mistake with no other symptom: pointing
# `alloy run` at a symlinked directory (e.g. key "..data" instead of ".") loads ZERO
# components, exits 0, logs neither an error nor a warning, and passes every readiness
# probe. Asserting on the component list is the only way to see it.
# ----------------------------------------------------------------------------------------
# Read through the API server's pod proxy rather than from a throwaway curl pod: no extra
# image, no attach race, and one call per pod so every node's collector is checked, not
# just whichever one a Service happened to route to.
fetch_components() {
  local pod="$1"
  kubectl get --raw "/api/v1/namespaces/${NAMESPACE}/pods/${pod}:12345/proxy/api/v0/web/components"
}

check_components() {
  local pods pod components expected_components component entry health

  expected_components=(
    # Declared by the module (conf.d/*.alloy).
    "discovery.kubernetes.pods"
    "discovery.relabel.pod_logs"
    "loki.source.file.pod_logs"
    "loki.process.pod_logs"
    "loki.relabel.journal"
    "loki.source.journal.journal"
    "loki.write.default"
    # Declared by the cluster-injected fragment; its presence proves directory mode
    # merged files from two different sources into one graph, and that its references to
    # discovery.kubernetes.pods and loki.write.default resolved across those files.
    "discovery.relabel.cluster_pvc_logs"
    "loki.source.file.cluster_pvc_logs"
    "loki.process.cluster_pvc_logs"
  )

  pods="$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=alloy \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"
  if [ -z "$pods" ]; then
    fail "no alloy pods found in namespace $NAMESPACE"
    return
  fi

  for pod in $pods; do
    if ! components="$(fetch_components "$pod")"; then
      fail "could not reach the component API of pod/$pod"
      continue
    fi

    # One component object per line so localID and its own health can be read together.
    # shellcheck disable=SC2001  # bash parameter expansion cannot insert a newline here
    components="$(echo "$components" | sed 's/{"name":"/\n{"name":"/g')"

    for component in "${expected_components[@]}"; do
      entry="$(echo "$components" | grep -F "\"localID\":\"${component}\"" | head -1 || true)"
      if [ -z "$entry" ]; then
        fail "pod/$pod has not loaded component $component - it is running with an incomplete graph"
        continue
      fi
      # An unhealthy loki.write or loki.source.file means logs are being dropped while the
      # DaemonSet stays Ready, so health is asserted for every component including the
      # journal reader (which reports healthy even on a node with no systemd at all - it
      # simply returns nothing, which is why the pod's own health proves so little here).
      health="$(echo "$entry" | grep -o '"state":"[a-z]*"' | head -1 || true)"
      if [ "$health" != '"state":"healthy"' ]; then
        fail "pod/$pod component $component is not healthy: ${health:-<no health reported>}"
      else
        ok "pod/$pod component $component loaded and healthy"
      fi
    done
  done
}

# ----------------------------------------------------------------------------------------
# 4. RBAC posture.
#
# The chart's default rules grant cluster-wide get/list/watch on secrets and configmaps
# for `remote.kubernetes.*` components this module does not use; promtail granted nothing
# comparable. The module narrows them, and the narrowing is split across rbac.rules and
# rbac.clusterRules because the chart renders invalid YAML if either list is empty - so
# `watch` is asserted too: it lives in the half that a chart change could silently drop.
# ----------------------------------------------------------------------------------------
# Subresources MUST be passed as --subresource=x, never as "resource/x": kubectl splits
# that shorthand into resource + resource NAME, so "get pods/log" asks whether the identity
# can get a Pod literally named "log" - which the pods grant allows, silently turning the
# check into a pass.
#
# can_i <verb> <resource> <expected: yes|no> [extra kubectl-auth-can-i args...]
can_i() {
  local verb="$1" resource="$2" expected="$3"
  shift 3
  local identity="system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
  local result
  if kubectl auth can-i "$verb" "$resource" --as="$identity" --all-namespaces "$@" >/dev/null 2>&1; then
    result=yes
  else
    result=no
  fi
  if [ "$result" != "$expected" ]; then
    fail "--as=$identity can-i $verb $resource $* => got '$result', expected '$expected'"
  else
    ok "--as=$identity can-i $verb $resource $* => $result"
  fi
}

check_rbac() {
  # Needed by discovery.kubernetes with role=pod, and nothing else.
  can_i list pods yes
  can_i watch pods yes
  can_i get pods yes
  # Granted by the chart's default rules; must not be granted here.
  can_i list secrets no
  can_i get secrets no
  can_i list configmaps no
  can_i list events no
  can_i list namespaces no
  can_i get pods no --subresource=log
  can_i list nodes no
}

check_fragment_injected
check_components
check_rbac

if [ "$FAILED" -ne 0 ]; then
  echo "alloy collector checks failed" >&2
  exit 1
fi
echo "all alloy collector checks passed"
