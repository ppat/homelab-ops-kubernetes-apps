#!/bin/sh
# Runs on the chainsaw runner. Proves the Flux controllers now running are the ones this
# module ships, not the ones the test harness installed before the module was applied.
#
# The harness pins its Flux release independently of the one this module vendors, and the
# two are normally the same, so image equality alone cannot tell them apart. The full
# container identity can: the module patches the args (feature gates, OOM watch) and the
# harness installs at a different log level. Tolerations are checked too, as the module's
# other patch a pod carries. Expected values are read from the module's own render in this
# checkout, never written here, so a Flux bump or a new patch moves them automatically.
#
# Every controller's pods must ALL match: a rollout still in progress leaves a harness pod
# serving next to a module pod, and the harness one may be the one holding the leader lease.
#
# One line per controller, `FLUX OK   [<name>] ...` or `FLUX FAIL [<name>] ...`.
set -eu
BUDGET_S=${1:-120}
MODULE=../../../infrastructure/subsystems/clusterops-core
NS=flux-system
CONTROLLERS="source-controller kustomize-controller helm-controller notification-controller"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# kustomize output -> just the Deployment documents -> a stream of JSON objects. Client-side
# dry-run only needs the API server for the Deployment mapping, which every cluster has.
kubectl kustomize "$MODULE" | awk '
  /^---$/ { if (doc ~ /\nkind: Deployment\n/) printf "---%s", doc; doc = "\n"; next }
  { doc = doc $0 "\n" }
  END { if (doc ~ /\nkind: Deployment\n/) printf "---%s", doc }' >"$tmp/deployments.yaml"
kubectl create --dry-run=client -o json -f "$tmp/deployments.yaml" >"$tmp/render.json"

# The fields that identify an install, as one canonical JSON value per container.
identity='{image: .image, args: (.args // [])}'

deadline=$(( $(date +%s) + BUDGET_S ))
FAILED=0
for name in $CONTROLLERS; do
  want=$(jq -c -s --arg n "$name" "
    [.[] | .items[]? // . | select(.metadata.name == \$n)] | first
    | {containers: [.spec.template.spec.containers[] | $identity],
       tolerations: (.spec.template.spec.tolerations // [])}" "$tmp/render.json")
  if [ -z "$want" ] || [ "$want" = null ]; then
    echo "FLUX FAIL [$name] the module render has no Deployment of this name"
    FAILED=1
    continue
  fi
  while :; do
    # Every pod of the controller, terminating ones included: a harness pod still shutting
    # down is still a harness pod, and may still be reconciling.
    got=$(kubectl -n "$NS" get pods -l "app=$name" -o json | jq -c "
      [.items[] | {containers: [.spec.containers[] | $identity],
                   tolerations: (.spec.tolerations // []),
                   ready: ([.status.conditions[]? | select(.type == \"Ready\")][0].status == \"True\"),
                   terminating: (.metadata.deletionTimestamp != null)}]")
    replicas=$(kubectl -n "$NS" get deploy "$name" -o jsonpath='{.spec.replicas}')
    verdict=$(printf '%s' "$got" | jq -r --argjson want "$want" --argjson r "${replicas:-0}" '
      if length != $r then "pods=\(length) replicas=\($r)"
      elif any(.[]; .terminating) then "a pod is still terminating"
      elif any(.[]; .containers != $want.containers) then
        "running containers differ from the module render: " +
        ([.[] | .containers | tostring] | unique | join(" | "))
      elif any(.[]; (.tolerations | contains($want.tolerations)) | not) then
        "a pod lacks the module tolerations"
      elif any(.[]; .ready | not) then "a pod is not Ready"
      else "" end')
    if [ -z "$verdict" ]; then
      echo "FLUX OK   [$name] $replicas pod(s) run the module render: $(printf '%s' "$want" | jq -c '.containers[0].args')"
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "FLUX FAIL [$name] $verdict; module renders $(printf '%s' "$want" | jq -c '.containers')"
      FAILED=1
      break
    fi
    sleep 2
  done
done
exit "$FAILED"
