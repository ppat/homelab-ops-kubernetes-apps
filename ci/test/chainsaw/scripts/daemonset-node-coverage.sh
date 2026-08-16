#!/bin/bash
set -euo pipefail

# Fails if a DaemonSet is not scheduled onto every node in the cluster.
#
# This exists because `daemonset-ready.yaml` cannot make this check and cannot be made to.
# It asserts `numberReady == desiredNumberScheduled`, and `desiredNumberScheduled` is the
# controller's count of the nodes the DaemonSet CURRENTLY targets - so both sides move
# together when the target set shrinks. A chart bump that drops a toleration or adds a
# nodeSelector removes a node from the denominator and the assert stays green at 2 == 2
# with a whole node uncovered. That is not hypothetical: the alloy chart's default
# `tolerations: []` left CI's tainted control-plane node uncollected while the DaemonSet
# reported Ready, and Renovate auto-merges exactly that class of bump, so "review would
# catch it" is not a defence.
#
# Node count is not reachable from the DaemonSet object, which is why this is a script and
# not another expression in the assertion file.
#
# Apply it only where the DaemonSet's intent really is "every node". A DaemonSet that is
# deliberately confined to a subset (a nodeSelector the module sets on purpose) will fail
# here, correctly - use the assertion file alone for those.
#
# Contract with callers:
#   stdout - one line per node describing coverage.
#   exit 1 - desiredNumberScheduled does not equal the number of nodes, or the DaemonSet
#            does not exist. Before exiting it prints which nodes are uncovered and their
#            taints, because the answer is almost always a taint the pod does not tolerate.

NAMESPACE=""
DAEMONSET=""

for param in "$@"
do
  case $param in
    --namespace=*)
      NAMESPACE="${param#*=}"
      shift
      ;;
    --daemonset=*)
      DAEMONSET="${param#*=}"
      shift
      ;;
    *)
      echo "unknown argument: ${param}" >&2
      exit 1
      ;;
  esac
done

if [ -z "$NAMESPACE" ] || [ -z "$DAEMONSET" ]; then
  echo "usage: daemonset-node-coverage.sh --namespace=<ns> --daemonset=<name>" >&2
  exit 1
fi

nodes="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"

# Read with an explicit default: on a DaemonSet the controller has not yet reached,
# .status.desiredNumberScheduled is absent and jsonpath prints nothing.
desired="$(kubectl get daemonset "$DAEMONSET" -n "$NAMESPACE" \
  -o jsonpath='{.status.desiredNumberScheduled}')"
desired="${desired:-0}"

if [ "$desired" = "$nodes" ]; then
  echo "ok: daemonset/${DAEMONSET} is scheduled onto all ${nodes} nodes"
  exit 0
fi

echo "FAIL: daemonset/${DAEMONSET} is scheduled onto ${desired} of ${nodes} nodes - the rest run no collector" >&2
echo "nodes and their taints:" >&2
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints >&2
echo "pods currently scheduled:" >&2
kubectl get pods -n "$NAMESPACE" \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName \
  --field-selector "status.phase!=Succeeded" >&2 || true
echo "daemonset tolerations / nodeSelector:" >&2
kubectl get daemonset "$DAEMONSET" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.tolerations}{"\n"}{.spec.template.spec.nodeSelector}{"\n"}' >&2
exit 1
