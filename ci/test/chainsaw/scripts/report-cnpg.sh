#!/bin/bash
# cloudnative-pg operator logs, on a failure where a CNPG Cluster is not Ready.
#
# #3678 is the largest single failure source in this repo -- 36 of 112 real failures across
# four suites and twelve unrelated branches -- and it is undiagnosed for exactly one reason:
# nothing captures the operator's logs. Its signature is a `Cluster` with an empty `Status` and
# `Events: <none>` while the operator itself reports Ready, i.e. the operator never acted. The
# absence of the obligatory SettingUp/CreatingInstance events proves inaction, but says nothing
# about why, and the per-suite `describe`/`events` catches can only ever show the object that
# did not change. The leading hypothesis -- a race between the operator's informer cache sync
# and the Cluster being created just after its HelmRelease reconciles -- is testable only
# against what the operator logged during that window.
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

kubectl get crd clusters.postgresql.cnpg.io "${KOPTS[@]}" >/dev/null 2>&1 || exit 0

# shellcheck disable=SC2016  # go-template, not shell
not_ready=$(kubectl get clusters.postgresql.cnpg.io -A "${KOPTS[@]}" \
  -o go-template='{{range .items}}{{$c := printf "%s/%s" .metadata.namespace .metadata.name}}{{$r := "MISSING-STATUS"}}{{if .status}}{{range .status.conditions}}{{if eq .type "Ready"}}{{$r = .status}}{{end}}{{end}}{{end}}{{printf "%s %s\n" $r $c}}{{end}}' 2>/dev/null \
  | grep -v '^True ' || true)

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
