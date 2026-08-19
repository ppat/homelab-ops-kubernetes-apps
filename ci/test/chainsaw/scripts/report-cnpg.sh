#!/bin/bash
# cloudnative-pg operator logs, on a failure where a CNPG Cluster is not Ready.
#
# #3678 was the largest single failure source in this repo -- 36 of 112 real failures across
# four suites. Its signature is a `Cluster` with an empty `Status` and `Events: <none>` while
# the operator itself reports Ready, i.e. the operator never acted.
#
# THE MECHANISM IS NO LONGER A HYPOTHESIS, and this file used to say otherwise. It named a race
# between the operator's informer cache sync and the Cluster being created as the leading
# candidate; that was refuted on the archive before it could be tested -- the operator had a
# ~99s head start and was demonstrably serving admission at the time. The real cause is serving
# operator 1.30.0 a PRE-1.30.0 `clusters` CRD, which wedges it for new objects and is sticky per
# process; a newer CRD under an older operator is harmless. Reproduced 4 arms on one cluster,
# and fixed by #3763 (nothing re-applies the bootstrap bundle on an interval any more).
#
# SO THIS SCRIPT IS A CONFIRMATION INSTRUMENT WITH A SHORT LIFE. It exists to show that the fix
# holds across a few more weeks of real runs, and is expected to be deleted once it has. Keep it
# correct -- a wrong answer during the confirmation window defeats the whole point -- but do not
# invest in it beyond that.
#
# This does NOT come with a budget raise, and must not. The operator never acted, so no budget
# can help; raising one would only delay the same failure and hide it behind a longer red run.
#
# Lives in the shared catch rather than in the six per-suite validate-*database*.yaml catches
# because it is one implementation instead of six, it also fires when the CNPG failure is
# collateral rather than the asserted step, and it is silent in the twelve suites that install
# no CNPG at all.
set -u

KOPTS=(--request-timeout=30s)
CNPG_NS=cnpg-system

ERR_FILE=$(mktemp)
# shellcheck disable=SC2064  # expand now: the trap must survive whatever reassigns it later
trap "rm -f '${ERR_FILE}'" EXIT

# Both kubectl calls below distinguish "CNPG is not installed in this suite" from "the API
# server could not be asked". They used to be indistinguishable, and in the direction that
# matters: an unreachable API server produced the same silence as a healthy suite with no
# CNPG in it. Demonstrated with KUBECONFIG=/nonexistent -- rc 0, zero bytes of stdout AND
# stderr, i.e. this instrument reporting "nothing to see" about a cluster it never reached.
# That is the failure mode it exists to catch, one level up.
crd_err=$(kubectl get crd clusters.postgresql.cnpg.io "${KOPTS[@]}" 2>&1 >/dev/null); crd_rc=$?
if [[ ${crd_rc} -ne 0 ]]; then
  # A genuinely absent CRD is the common case and stays silent -- most suites have no CNPG.
  if [[ "${crd_err}" == *NotFound* || "${crd_err}" == *"not found"* ]]; then
    exit 0
  fi
  echo '--- CNPG: COULD NOT ASK -- the API server did not answer, so nothing below was checked ---'
  echo "${crd_err}"
  exit 0
fi

# ONE call, captured once. An earlier draft ran this listing twice -- once as an rc probe with
# its output discarded, then again for real -- which meant the call that was checked was not the
# call that was used: if the second one failed, its error was still swallowed and `not_ready`
# came back empty, i.e. exactly the silent "all Ready" this section exists to eliminate.
#
# stderr goes to a file rather than into the capture. `2>&1` would be loud on failure, which is
# usually the right instinct and is the wrong one here: on SUCCESS it would fold any kubectl
# warning into `list_out`, where it survives `grep -v '^True '` and prints as a not-Ready
# Cluster. A false positive in the #3678 instrument, during the weeks it exists to confirm #3678
# stays fixed, is worse than anything it buys.
# shellcheck disable=SC2016  # go-template, not shell
list_out=$(kubectl get clusters.postgresql.cnpg.io -A "${KOPTS[@]}" \
  -o go-template='{{range .items}}{{$c := printf "%s/%s" .metadata.namespace .metadata.name}}{{$r := "MISSING-STATUS"}}{{if .status}}{{range .status.conditions}}{{if eq .type "Ready"}}{{$r = .status}}{{end}}{{end}}{{end}}{{printf "%s %s\n" $r $c}}{{end}}' 2>"${ERR_FILE}"); list_rc=$?
if [[ ${list_rc} -ne 0 ]]; then
  echo '--- CNPG: COULD NOT ASK -- listing Cluster objects failed, so "all Ready" is NOT established ---'
  cat "${ERR_FILE}"
  exit 0
fi

not_ready=$(printf '%s\n' "${list_out}" | grep -v '^True ' || true)

[[ -z "${not_ready}" ]] && exit 0

echo '--- CNPG: Cluster objects not Ready (#3678) ---'
echo "${not_ready}"

echo "--- CNPG: operator pods in ${CNPG_NS} ---"
kubectl get pods -n "${CNPG_NS}" "${KOPTS[@]}" -o wide 2>&1

pods=()
mapfile -t pods < <(kubectl get pods -n "${CNPG_NS}" "${KOPTS[@]}" -o name 2>/dev/null || true)
if [[ "${#pods[@]}" -eq 0 ]]; then
  # Said out loud rather than left as an empty section: "no operator pod" and "the capture did
  # not run" look identical in a log, and only one of them is a finding.
  echo "--- CNPG: no pods in ${CNPG_NS}, no operator logs to capture ---"
  exit 0
fi

for p in "${pods[@]}"; do
  echo "--- CNPG: logs ${CNPG_NS}/${p} (tail 500, all containers) ---"
  kubectl logs -n "${CNPG_NS}" "${p}" "${KOPTS[@]}" --all-containers --timestamps --tail=500 2>&1 || true
done

exit 0
