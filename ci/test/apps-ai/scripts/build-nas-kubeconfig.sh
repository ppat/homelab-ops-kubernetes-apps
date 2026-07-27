#!/bin/bash
set -euo pipefail

# mcp-kubernetes-nas (apps/subsystems/ai/mcp-kubernetes-nas) authenticates to a
# remote cluster via a mounted kubeconfig; in production that kubeconfig is
# assembled by hand from a minted ServiceAccount token and stored as the
# "kubeconfig_nas_mcp" secret (see
# homelab-ops-kubernetes-clusters/clusters/nas/cluster/rbac/mcp-kubernetes-readonly.yaml).
# A static dummy kubeconfig can't stand in for that here: the server parses it
# at startup and crash-loops on anything invalid, and its /healthz readiness
# probe needs a reachable API server behind it. So this script does the same
# assembly CI does for the real nas cluster, but points it at this kind
# cluster's own in-cluster API endpoint (https://kubernetes.default.svc) --
# reachable from pods in this cluster -- using the mcp-kubernetes-nas
# ServiceAccount token minted in pre-requisites/mcp-kubernetes-rbac.yaml. This
# genuinely exercises the kubeconfig parsing, volume mount, and /healthz code
# paths, just against a stand-in "remote" that happens to be the same cluster.
#
# The apps-ai.yaml test Kustomization deletes the module's own
# mcp-kubernetes-nas-secrets ExternalSecret via spec.patches (it would
# otherwise fight with this script for ownership of the Secret), so this
# creates the target Secret directly instead of going through ESO.

NAMESPACE="mcp-access"
TARGET_NAMESPACE="ai"
SA_SECRET="mcp-kubernetes-nas-token"
TARGET_SECRET="mcp-kubernetes-nas-secrets"

TOKEN=""
CA=""
for _ in $(seq 1 30); do
  TOKEN=$(kubectl get secret "$SA_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null || true)
  CA=$(kubectl get secret "$SA_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)
  if [ -n "$TOKEN" ] && [ -n "$CA" ]; then
    break
  fi
  sleep 2
done

if [ -z "$TOKEN" ] || [ -z "$CA" ]; then
  echo "timed out waiting for secret/$SA_SECRET (-n $NAMESPACE) to be populated by the token controller" >&2
  exit 1
fi

# Decoded into a variable (and checked) up front rather than inline in the heredoc below:
# a command substitution inside a heredoc doesn't propagate its exit status to the
# enclosing "VAR=$(cat <<EOF ...)" assignment, which takes cat's exit status instead --
# so set -e would not catch a base64 decode failure there, silently producing a
# kubeconfig with an empty token.
DECODED_TOKEN=$(echo "$TOKEN" | base64 -d)
if [ -z "$DECODED_TOKEN" ]; then
  echo "base64 decode of the token from secret/$SA_SECRET (-n $NAMESPACE) produced an empty result" >&2
  exit 1
fi

KUBECONFIG_CONTENT=$(cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: nas
  cluster:
    server: https://kubernetes.default.svc
    certificate-authority-data: ${CA}
contexts:
- name: nas
  context:
    cluster: nas
    user: nas
current-context: nas
users:
- name: nas
  user:
    token: ${DECODED_TOKEN}
EOF
)

kubectl create secret generic "$TARGET_SECRET" -n "$TARGET_NAMESPACE" \
  --from-literal=kubeconfig="$KUBECONFIG_CONTENT" \
  --dry-run=client -o yaml | kubectl apply -f -
