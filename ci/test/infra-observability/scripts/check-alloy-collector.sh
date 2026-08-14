#!/bin/bash
set -euo pipefail

# Everything in here exists because the failure modes found while building this component
# all produced a green, error-free Alloy that collected nothing or dropped a label. A
# Ready DaemonSet proves almost nothing about this workload, so these checks look at what
# the collector actually loaded and what its identity can actually reach.
#
# There are TWO Alloy instances in this namespace and they are checked separately: the
# node-log DaemonSet (`alloy`) and the Kubernetes Event singleton (`alloy-events`). They
# exist as separate workloads precisely so that the DaemonSet's identity never gains
# cluster-wide Event read, so "the DaemonSet still cannot list events" is asserted here
# as forcefully as "the singleton can".
#
# Checked here, in order:
#   1. the cluster-injected fragment landed in the ConfigMap byte-for-byte,
#   2. the two workloads' pod sets are disjoint under app.kubernetes.io/name,
#   3. every pod of each instance loaded a non-empty component graph containing every
#      component that instance's config declares, in both directions across files,
#   4. every one of those components reports healthy,
#   5. the DaemonSet actually covers every node,
#   6. the DaemonSet's ServiceAccount can watch pods and STILL cannot read events,
#      secrets or configmaps,
#   7. the singleton's ServiceAccount can read events and nothing else.

NAMESPACE=logging
SERVICE_ACCOUNT=alloy
EVENTS_SERVICE_ACCOUNT=alloy-events
# `app.kubernetes.io/name` values, which differ only because the event singleton's
# HelmRelease sets `nameOverride` - the chart derives that label from the chart name, so
# without it both workloads would answer to `app.kubernetes.io/name=alloy`.
COLLECTOR_APP=alloy
EVENTS_APP=alloy-events
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
# 2. The two workloads are separable by label.
#
# Every selector in this suite, and every `kubectl -l app.kubernetes.io/name=alloy` an
# operator types, assumes that label names ONE workload. The chart derives it from the
# chart name, not the release name, so both instances would answer to it were it not for
# the event singleton's `nameOverride`. Losing that override does not break anything
# loudly - it silently widens every one of those selectors to include a pod running a
# completely different config.
# ----------------------------------------------------------------------------------------
check_workloads_disjoint() {
  local collector_pods events_pods overlap
  collector_pods="$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${COLLECTOR_APP}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)"
  events_pods="$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${EVENTS_APP}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)"

  if [ -z "$events_pods" ]; then
    fail "no pods carry app.kubernetes.io/name=${EVENTS_APP} - the event singleton is not running"
    return
  fi
  overlap="$(comm -12 <(echo "$collector_pods") <(echo "$events_pods") | paste -sd' ' -)"
  if [ -n "$overlap" ]; then
    fail "pods match BOTH app.kubernetes.io/name=${COLLECTOR_APP} and =${EVENTS_APP}: ${overlap}"
    return
  fi
  # The DaemonSet's own pods are the only thing =alloy may select. Compared against the
  # DaemonSet's controller reference rather than a count, so a stray pod fails too.
  local owned
  owned="$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${COLLECTOR_APP}" \
    -o jsonpath='{range .items[*]}{.metadata.ownerReferences[0].name}{"\n"}{end}' | sort -u | paste -sd' ' -)"
  if [ "$owned" != "$COLLECTOR_APP" ]; then
    fail "app.kubernetes.io/name=${COLLECTOR_APP} selects pods owned by '${owned}', expected only daemonset/${COLLECTOR_APP}"
    return
  fi
  ok "app.kubernetes.io/name selects the two alloy workloads separately"
}

# ----------------------------------------------------------------------------------------
# 3 + 4. Each instance actually built a component graph from its own directory.
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

# check_components <app.kubernetes.io/name> <component>...
check_components() {
  local app="$1"
  shift
  local expected_components=("$@")
  local pods pod components component entry health

  pods="$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=${app}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"
  if [ -z "$pods" ]; then
    fail "no ${app} pods found in namespace $NAMESPACE"
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
# 5. Node coverage.
#
# A DaemonSet reports Ready when every pod it *scheduled* is ready, so a node it never
# scheduled onto at all is invisible: the alloy chart's tolerations default to [], which
# silently left CI's tainted control-plane node uncollected while the DaemonSet showed
# green.
# ----------------------------------------------------------------------------------------
check_node_coverage() {
  local nodes desired
  nodes="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
  desired="$(kubectl get daemonset alloy -n "$NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}')"
  if [ "$desired" != "$nodes" ]; then
    fail "daemonset/alloy is scheduled onto $desired of $nodes nodes - the rest are collecting nothing"
  else
    ok "daemonset/alloy is scheduled onto all $nodes nodes"
  fi
}

# ----------------------------------------------------------------------------------------
# 6 + 7. RBAC posture, per identity.
#
# The chart's default rules grant cluster-wide get/list/watch on secrets and configmaps
# for `remote.kubernetes.*` components this module does not use. The module narrows them, and the narrowing is split across rbac.rules and
# rbac.clusterRules because the chart renders invalid YAML if either list is empty - so
# `watch` is asserted too: it lives in the half that a chart change could silently drop.
#
# The two identities are asserted as mirror images. Kubernetes Event export could have
# been done by adding `events` to the DaemonSet's ClusterRole - issue #3608 assumed that
# is what would happen - which would have put cluster-wide Event read on an identity that
# runs on every node. It was instead given to a separate singleton, so `can-i list events`
# must remain NO for `alloy` and YES for `alloy-events`; a future change that widens the
# DaemonSet fails here rather than passing quietly because event export still works.
# ----------------------------------------------------------------------------------------
# Subresources MUST be passed as --subresource=x, never as "resource/x": kubectl splits
# that shorthand into resource + resource NAME, so "get pods/log" asks whether the identity
# can get a Pod literally named "log" - which the pods grant allows, silently turning the
# check into a pass.
#
# can_i <service account> <verb> <resource> <expected: yes|no> [extra kubectl-auth-can-i args...]
can_i() {
  local service_account="$1" verb="$2" resource="$3" expected="$4"
  shift 4
  local identity="system:serviceaccount:${NAMESPACE}:${service_account}"
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

check_collector_rbac() {
  # Needed by discovery.kubernetes with role=pod, and nothing else.
  can_i "$SERVICE_ACCOUNT" list pods yes
  can_i "$SERVICE_ACCOUNT" watch pods yes
  can_i "$SERVICE_ACCOUNT" get pods yes
  # Granted by the chart's default rules; must not be granted here.
  can_i "$SERVICE_ACCOUNT" list secrets no
  can_i "$SERVICE_ACCOUNT" get secrets no
  can_i "$SERVICE_ACCOUNT" list configmaps no
  # Load-bearing: restoring event export must not widen THIS identity.
  can_i "$SERVICE_ACCOUNT" get events no
  can_i "$SERVICE_ACCOUNT" list events no
  can_i "$SERVICE_ACCOUNT" watch events no
  can_i "$SERVICE_ACCOUNT" list namespaces no
  can_i "$SERVICE_ACCOUNT" get pods no --subresource=log
  can_i "$SERVICE_ACCOUNT" list nodes no
}

check_events_rbac() {
  # Exactly what loki.source.kubernetes_events needs, on the core API group.
  can_i "$EVENTS_SERVICE_ACCOUNT" get events yes
  can_i "$EVENTS_SERVICE_ACCOUNT" list events yes
  can_i "$EVENTS_SERVICE_ACCOUNT" watch events yes
  # Everything the chart's default rules would have granted, and the pod-log grant the
  # node collector holds. This identity reads Events and nothing else.
  can_i "$EVENTS_SERVICE_ACCOUNT" list pods no
  can_i "$EVENTS_SERVICE_ACCOUNT" get pods no
  can_i "$EVENTS_SERVICE_ACCOUNT" watch pods no
  can_i "$EVENTS_SERVICE_ACCOUNT" get pods no --subresource=log
  can_i "$EVENTS_SERVICE_ACCOUNT" list secrets no
  can_i "$EVENTS_SERVICE_ACCOUNT" get secrets no
  can_i "$EVENTS_SERVICE_ACCOUNT" list configmaps no
  can_i "$EVENTS_SERVICE_ACCOUNT" get configmaps no
  can_i "$EVENTS_SERVICE_ACCOUNT" list namespaces no
  can_i "$EVENTS_SERVICE_ACCOUNT" list nodes no
}

check_fragment_injected
check_workloads_disjoint

# Declared by the module (conf.d/*.alloy), plus - from "discovery.relabel.cluster_pvc_logs"
# on - by the cluster-injected fragment. The fragment's presence proves directory mode
# merged files from two different sources into one graph, and that its references to
# discovery.kubernetes.pods and loki.write.default resolved across those files.
check_components "$COLLECTOR_APP" \
  "discovery.kubernetes.pods" \
  "discovery.relabel.pod_logs" \
  "loki.source.file.pod_logs" \
  "loki.process.pod_logs" \
  "loki.relabel.journal" \
  "loki.source.journal.journal" \
  "loki.write.default" \
  "discovery.relabel.cluster_pvc_logs" \
  "loki.source.file.cluster_pvc_logs" \
  "loki.process.cluster_pvc_logs"

# Declared by events.d/events.alloy. This proves the components were DECLARED AND
# INSTANTIATED from this instance's own config directory - the symlinked-config-path trap
# above would leave the list empty.
#
# It does NOT prove the informer established a watch, and the health check does not
# either: `loki.source.kubernetes_events` implements component.Component,
# component.DebugComponent and cluster.Component, but not HealthComponent, and nothing on
# its path calls OnStateChange/UpdateHealth. Given an RBAC denial it blocks in
# configureInformers' GetInformer until the 10-minute informerSyncTimeout, then logs
# "event watcher exited with error" while still reporting state "healthy" (verified
# against alloy v1.18.1). The only thing
# that distinguishes a working event watch from a broken one is the end-to-end Loki query
# - chainsaw-test.yaml's "Validate kubernetes event collection" step and
# check-event-stream-contract.sh. See the module README's note on that gap.
check_components "$EVENTS_APP" \
  "loki.source.kubernetes_events.events" \
  "loki.process.events" \
  "loki.write.default"

check_node_coverage
check_collector_rbac
check_events_rbac

if [ "$FAILED" -ne 0 ]; then
  echo "alloy collector checks failed" >&2
  exit 1
fi
echo "all alloy collector checks passed"
