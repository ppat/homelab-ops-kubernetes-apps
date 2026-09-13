#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="${VERSITYGW_NAMESPACE:-versitygw}"

python3 -c 'import yaml' 2>/dev/null || python3 -m pip install --quiet --user pyyaml

# The single place that knows what the store contains, and the same document the
# provisioning step consumed, through the same parser.
kubectl get secret -n "$NAMESPACE" versitygw-provisioning \
  -o jsonpath='{.data.provisioning\.yaml}' | base64 -d \
  | python3 "${HERE}/python/provision-plan.py" 2>/dev/null
