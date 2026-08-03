#!/bin/bash
set -euo pipefail

# Both mcp-kubernetes-nas and mcp-kubernetes-sandbox (apps/subsystems/ai) authenticate to
# a remote cluster via a mounted kubeconfig; in production each kubeconfig is assembled
# by hand (nas) or by a CronJob running inside the target cluster (sandbox) from a minted
# ServiceAccount token, and stored as "kubeconfig_nas_mcp" / "kubeconfig_sandbox_mcp"
# respectively. A static dummy kubeconfig can't stand in for either here: the server
# parses it at startup and crash-loops on anything invalid, and its /healthz readiness
# probe needs a reachable API server behind it. So this script does the same assembly CI
# does for each real remote cluster, but points it at this kind cluster's own in-cluster
# API endpoint (https://kubernetes.default.svc) -- reachable from pods in this cluster --
# using whichever ServiceAccount token pre-requisites/mcp-kubernetes-rbac.yaml minted for
# the caller's identity. This genuinely exercises the kubeconfig parsing, volume mount,
# and /healthz code paths, just against a stand-in "remote" that happens to be the same
# cluster both times, with two different identities (nas: scoped read-only; sandbox:
# cluster-admin, mirroring what provision-agent-admin-cronjob.yaml actually grants inside
# the real sandbox's own guest etcd -- see check-mcp-kubernetes-rbac.sh for why that
# split matters to the RBAC checks run against each).
#
# The apps-ai.yaml test Kustomization deletes each module's own *-secrets ExternalSecret
# via spec.patches (it would otherwise fight this script for ownership of the Secret), so
# this creates the target Secret directly instead of going through ESO. One invocation
# per remote cluster, from chainsaw-test.yaml, rather than one script per cluster: the
# assembly is identical, only the identity/target names differ.
#
# Usage: build-remote-cluster-kubeconfig.sh <sa-secret> <sa-namespace> <target-secret> \
#          <target-namespace> <context-name>

SA_SECRET="${1:?sa-secret name required}"
SA_NAMESPACE="${2:?sa-namespace required}"
TARGET_SECRET="${3:?target-secret name required}"
TARGET_NAMESPACE="${4:?target-namespace required}"
CONTEXT_NAME="${5:?context-name required}"

TOKEN=""
CA=""
for _ in $(seq 1 30); do
  TOKEN=$(kubectl get secret "$SA_SECRET" -n "$SA_NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null || true)
  CA=$(kubectl get secret "$SA_SECRET" -n "$SA_NAMESPACE" -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
  if [ -n "$TOKEN" ] && [ -n "$CA" ]; then
    break
  fi
  sleep 2
done

if [ -z "$TOKEN" ] || [ -z "$CA" ]; then
  echo "timed out waiting for secret/$SA_SECRET (-n $SA_NAMESPACE) to be populated by the token controller" >&2
  exit 1
fi

# Decoded into a variable (and checked) up front rather than inline in the heredoc below:
# a command substitution inside a heredoc doesn't propagate its exit status to the
# enclosing "VAR=$(cat <<EOF ...)" assignment, which takes cat's exit status instead --
# so set -e would not catch a base64 decode failure there, silently producing a
# kubeconfig with an empty token.
DECODED_TOKEN=$(echo "$TOKEN" | base64 -d)
if [ -z "$DECODED_TOKEN" ]; then
  echo "base64 decode of the token from secret/$SA_SECRET (-n $SA_NAMESPACE) produced an empty result" >&2
  exit 1
fi

KUBECONFIG_CONTENT=$(cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${CONTEXT_NAME}
  cluster:
    server: https://kubernetes.default.svc
    certificate-authority-data: ${CA}
contexts:
- name: ${CONTEXT_NAME}
  context:
    cluster: ${CONTEXT_NAME}
    user: ${CONTEXT_NAME}
current-context: ${CONTEXT_NAME}
users:
- name: ${CONTEXT_NAME}
  user:
    token: ${DECODED_TOKEN}
EOF
)

kubectl create secret generic "$TARGET_SECRET" -n "$TARGET_NAMESPACE" \
  --from-literal=kubeconfig="$KUBECONFIG_CONTENT" \
  --dry-run=client -o yaml | kubectl apply -f -
