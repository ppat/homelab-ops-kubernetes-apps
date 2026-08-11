#!/bin/bash
set -euo pipefail

# Everything in here exists because the failure modes found while building this component
# all produced a green, error-free Alloy that collected nothing or dropped a label. A
# Ready DaemonSet proves almost nothing about this workload, so these checks look at what
# the collector actually loaded and what its identity can actually reach.
#
# Checked here, in order:
#   1. the cluster-injected fragment landed in the ConfigMap byte-for-byte,
#   2. the running collector loaded a non-empty component graph containing every
#      component the module and the fragment declare, in both directions across files,
#   3. those components are healthy,
#   4. the ServiceAccount can watch pods but cannot read secrets or configmaps.

NAMESPACE=logging
DAEMONSET=alloy
SERVICE_ACCOUNT=alloy
CONFIG_MAP=alloy-config
FRAGMENT_KEY=cluster-pvc-logs.alloy
FRAGMENT_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pre-requisites/alloy/conf.d/${FRAGMENT_KEY}"
# Pinned to the same digest the module's own initContainer uses.
BUSYBOX_IMAGE="busybox@sha256:dc2d74b28e4cf8984fa52af1f39bc7c3d9c73760b41a74d629f5d11b1ab28616"

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
  if ! diff -u "$FRAGMENT_FILE" <(printf '%s' "$injected") >/dev/null; then
    fail "'$FRAGMENT_KEY' in configmap/$CONFIG_MAP differs from $FRAGMENT_FILE"
    diff -u "$FRAGMENT_FILE" <(printf '%s' "$injected") >&2 || true
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
fetch_components() {
  local endpoint="http://${DAEMONSET}.${NAMESPACE}.svc.cluster.local:12345/api/v0/web/components"
  kubectl run "alloy-component-probe-$$" \
    --namespace "$NAMESPACE" \
    --image "$BUSYBOX_IMAGE" \
    --restart Never \
    --rm \
    --attach \
    --quiet \
    --command -- wget -q -O - "$endpoint"
}

check_components() {
  local components expected_components component health
  if ! components="$(fetch_components)"; then
    fail "could not reach the alloy component API"
    return
  fi

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

  for component in "${expected_components[@]}"; do
    if echo "$components" | grep -q "\"localID\":\"${component}\""; then
      ok "component $component loaded"
    else
      fail "component $component is not loaded - the collector is running with an incomplete graph"
    fi
  done

  # loki.source.journal is exempt: kind nodes run no systemd, so the journal reader has
  # nothing to open. Every other component must be healthy - an unhealthy loki.write or
  # loki.source.file means logs are being dropped while the pod stays Ready.
  for component in "${expected_components[@]}"; do
    [ "$component" = "loki.source.journal.journal" ] && continue
    health="$(echo "$components" | tr '}' '\n' | grep "\"localID\":\"${component}\"" | grep -o '"health":"[a-z]*"' | head -1 || true)"
    if [ -n "$health" ] && [ "$health" != '"health":"healthy"' ]; then
      fail "component $component is ${health}"
    fi
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
