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
# It also refuses to run on a topology where it could not have failed - see the preflight
# below, which is the reason this script can be trusted at all.
#
# Contract with callers:
#   stdout - one line per node describing coverage.
#   exit 1 - desiredNumberScheduled does not equal the number of nodes, the DaemonSet does
#            not exist, or the cluster carries no control-plane taint for the check to bite
#            on. Before exiting it prints which nodes are uncovered and their taints,
#            because the answer is almost always a taint the pod does not tolerate.

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

# Preflight: refuse to pass on a topology where passing was the only possible outcome.
#
# The regression this exists for is a lost toleration, so it is only observable if some node
# repels a pod that does not tolerate it. On a cluster with no worker nodes kind runs
# `kubectl taint nodes --all node-role.kubernetes.io/control-plane-` as part of cluster
# creation, so the one node ends up with no taints at all.
#
# Measured on kind 0.32.0 with kindest/node:v1.36.1, the versions CI pins:
# `.github/kind-cluster-single-node.yaml` yields a node whose `.spec.taints` is absent, a
# DaemonSet with no tolerations reports desiredNumberScheduled 1 of 1 node, and this script
# printed "ok". On the 3-node config the same DaemonSet reports 2 of 3 and this script exits
# 1; a 2-node config behaves the same way at 1 of 2.
#
# The kind config cannot put the taint back, and both routes were tried. A
# `kubeadmConfigPatches` entry re-declaring the control-plane taint is removed anyway by the
# step above. Declaring a DIFFERENT taint key instead makes `kind create cluster` fail
# outright - the removal step is not conditional, so it errors with `taint
# "node-role.kubernetes.io/control-plane" not found` and the cluster never comes up. A
# worker node in the config is the only lever.
#
# So on a single-node cluster the comparison below is 1 == 1 by construction: it consumes a
# budget and reads as coverage while being incapable of going red, which this repo treats as
# worse than no assertion at all. Fail loudly at the moment a suite's topology changes rather
# than degrade into a green that means nothing.
tainted="$(kubectl get nodes \
  -o jsonpath='{.items[*].spec.taints[?(@.effect=="NoSchedule")].key}' \
  | tr ' ' '\n' | grep -c '^node-role.kubernetes.io/control-plane$' || true)"

if [ "$tainted" -eq 0 ]; then
  echo "FAIL: no node carries node-role.kubernetes.io/control-plane:NoSchedule, so nothing repels an untolerating pod and this check could only ever pass" >&2
  echo "this suite's kind config must keep at least one worker node - kind drops the control-plane taint on a cluster with none, and the kind config cannot re-add it" >&2
  kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints >&2
  exit 1
fi

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
