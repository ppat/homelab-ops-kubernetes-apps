#!/bin/bash
set -euo pipefail

# Must NOT judge the phase: fixtures here assert that a pod FAILED.
if [ "$#" -ne 3 ]; then
  echo "usage: await-pod.sh <namespace> <pod> <deadline-seconds>" >&2
  exit 2
fi

namespace="$1"
pod="$2"
deadline_seconds="$3"

deadline=$(( $(date +%s) + deadline_seconds ))
while :; do
  phase="$(kubectl get pod -n "$namespace" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  case "$phase" in
  Succeeded | Failed)
    echo "$phase"
    exit 0
    ;;
  esac
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FAIL: pod/${pod} did not reach a terminal phase within ${deadline_seconds}s (phase=${phase:-unknown})" >&2
    kubectl describe pod -n "$namespace" "$pod" >&2 || true
    exit 1
  fi
  sleep 3
done
