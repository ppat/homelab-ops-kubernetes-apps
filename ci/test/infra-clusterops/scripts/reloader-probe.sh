#!/bin/sh
# Runs on the chainsaw runner, against test-resources/reloader-consumers.yaml. Changes the
# Secret and ConfigMap those workloads read, and reports what each workload's pods then see.
#
# A roll is judged by its consequence, not by a restart: the workload's generation moved,
# its rollout completed, the pod serving now is a different pod (UID), and that pod printed
# the new value at start. A pod restarted for any other reason would print the old one.
# The negative checks are read after the positive roll completed: Reloader handles one
# change event against every workload in the namespace at once, so a workload it was going
# to roll for that event has been patched by the time the named one has finished rolling.
#
# One line per check, `RELOADER OK   [<check>] ...` or `RELOADER FAIL [<check>] ...`. Every
# check runs even after a failure; the exit is 1 if any failed.
set -u
BUDGET_S=${1:-90}
NS=reloader-probe
FAILED=0
T0=$(date +%s)
ok() { echo "RELOADER OK   [$1] $2 (t+$(( $(date +%s) - T0 ))s)"; }
fail() { echo "RELOADER FAIL [$1] $2 (t+$(( $(date +%s) - T0 ))s)"; FAILED=1; }

generation() { kubectl -n "$NS" get "$1" -o jsonpath='{.metadata.generation}'; }

# The UID of the one live pod of workload $1 (a label), or nothing if there is not exactly
# one live, Ready pod.
live_pod() {
  kubectl -n "$NS" get pods -l "app=$1" -o json | jq -r '
    [.items[] | select(.metadata.deletionTimestamp == null)]
    | if length == 1 and ([.[0].status.conditions[]? | select(.type == "Ready")][0].status == "True")
      then "\(.[0].metadata.uid) \(.[0].metadata.name)" else empty end'
}

# Whether the controller has finished rolling out the current spec of $1 (kind/name).
rolled_out() {
  kubectl -n "$NS" get "$1" -o json | jq -e '
    .status.observedGeneration == .metadata.generation
    and (.status.readyReplicas // 0) == .spec.replicas
    and (.status.replicas // 0) == .spec.replicas
    and (if .kind == "StatefulSet" then .status.currentRevision == .status.updateRevision
         else (.status.updatedReplicas // 0) == .spec.replicas end)' >/dev/null
}

# What the live pod of $1 printed at start.
seen() {
  pod=$(live_pod "$1" | cut -d' ' -f2)
  [ -n "$pod" ] && kubectl -n "$NS" logs "$pod" 2>/dev/null | grep '^PROBE ' | head -n 1
}

# await_roll <check> <kind/name> <label> <generation before> <pod uid before> <expected line>
await_roll() {
  deadline=$(( $(date +%s) + BUDGET_S ))
  while :; do
    g=$(generation "$2")
    uid=$(live_pod "$3" | cut -d' ' -f1)
    line=$(seen "$3")
    if [ "$g" -gt "$4" ] && rolled_out "$2" && [ -n "$uid" ] && [ "$uid" != "$5" ] \
        && [ "$line" = "$6" ]; then
      ok "$1" "generation $4 -> $g, new pod sees '$line'"
      return
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      fail "$1" "after ${BUDGET_S}s: generation $4 -> $g, pod ${uid:-none} (was $5), sees '${line}', want '$6'"
      return
    fi
    sleep 1
  done
}

# assert_untouched <check> <kind/name> <label> <generation before> <pod uid before> <line>
assert_untouched() {
  g=$(generation "$2")
  uid=$(live_pod "$3" | cut -d' ' -f1)
  line=$(seen "$3")
  if [ "$g" = "$4" ] && [ "$uid" = "$5" ] && [ "$line" = "$6" ]; then
    ok "$1" "generation $g and pod unchanged, still sees '$line'"
  else
    fail "$1" "generation $4 -> $g, pod $5 -> ${uid:-none}, sees '${line}'"
  fi
}

set_value() {
  kubectl -n "$NS" patch "$1" --type merge -p "$2" >/dev/null
}

# ---- baseline --------------------------------------------------------------------------
V1="PROBE secret=secret-v1 config=config-v1"
for w in deployment/annotated statefulset/annotated-sts deployment/unannotated; do
  label=${w#*/}
  if ! rolled_out "$w" || [ "$(seen "$label")" != "$V1" ]; then
    fail baseline "$w is not rolled out with a pod printing '$V1' (sees '$(seen "$label")')"
    exit 1
  fi
done
dep_g0=$(generation deployment/annotated);       dep_u0=$(live_pod annotated | cut -d' ' -f1)
sts_g0=$(generation statefulset/annotated-sts);  sts_u0=$(live_pod annotated-sts | cut -d' ' -f1)
una_g0=$(generation deployment/unannotated);     una_u0=$(live_pod unannotated | cut -d' ' -f1)
ok baseline "three workloads rolled out, each pod sees '$V1'"

# ---- a named Secret changes ------------------------------------------------------------
# The bystander goes first: if its change rolled the annotated Deployment, that roll would
# be queued ahead of the real one and show as a second generation step below.
set_value secret/bystander-secret '{"stringData":{"value":"bystander-v2"}}'
set_value secret/probe-secret '{"stringData":{"value":"secret-v2"}}'
V2="PROBE secret=secret-v2 config=config-v1"
await_roll secret-deployment deployment/annotated annotated "$dep_g0" "$dep_u0" "$V2"
await_roll secret-statefulset statefulset/annotated-sts annotated-sts "$sts_g0" "$sts_u0" "$V2"
dep_g1=$(generation deployment/annotated)
if [ "$dep_g1" = "$(( dep_g0 + 1 ))" ]; then
  ok secret-unnamed "deployment/annotated rolled once; bystander-secret, named by nothing, rolled nothing"
else
  fail secret-unnamed "deployment/annotated generation $dep_g0 -> $dep_g1, want exactly one roll"
fi
assert_untouched secret-unannotated deployment/unannotated unannotated "$una_g0" "$una_u0" "$V1"

# ---- a named ConfigMap changes ---------------------------------------------------------
dep_u1=$(live_pod annotated | cut -d' ' -f1)
sts_g1=$(generation statefulset/annotated-sts); sts_u1=$(live_pod annotated-sts | cut -d' ' -f1)
set_value configmap/probe-config '{"data":{"value":"config-v2"}}'
await_roll configmap-deployment deployment/annotated annotated "$dep_g1" "$dep_u1" \
  "PROBE secret=secret-v2 config=config-v2"
# Names only the Secret, so a ConfigMap change must not roll it.
assert_untouched configmap-unnamed statefulset/annotated-sts annotated-sts "$sts_g1" "$sts_u1" "$V2"
assert_untouched configmap-unannotated deployment/unannotated unannotated "$una_g0" "$una_u0" "$V1"

exit "$FAILED"
