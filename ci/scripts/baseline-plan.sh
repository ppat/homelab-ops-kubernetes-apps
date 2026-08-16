#!/usr/bin/env bash
#
# Selects which chainsaw suites the scheduled-baseline workflow runs in this slot, and
# reads each one's inputs out of its own test-*.yaml rather than restating them.
#
# Restating them is the failure this script exists to avoid: a suite that changes its kind
# topology or its test path would otherwise keep producing baseline samples under the old
# configuration, and the series would silently span two different experiments.
#
# Usage:  baseline-plan.sh [selector]
#   slot   (default) the suites this slot is due to run
#   all    every discovered suite
#   <list> comma- or space-separated suite names
#
# Emits a GitHub Actions matrix on stdout as one JSON object.
set -euo pipefail

WORKFLOW_DIR="${WORKFLOW_DIR:-.github/workflows}"

# Fixed UTC slots. Documented in TESTING.md; anyone running a serial CI experiment reads
# them there and steers around them. Minute 23 rather than :00 because scheduled workflows
# queue behind the top-of-the-hour peak, and a delayed slot is a slot at an unknown hour.
SLOT_HOURS=(2 8 14 20)

# Suites carried in *every* slot rather than once a day. Both are the historically flaky
# ones (~39% and ~44% over a 14-day census) and both are the targets of in-flight work, so
# they are where a rate change is expected and where the extra n actually buys resolution:
# at n≈120/month a 95% interval on p=0.4 is about +/-9pp, against +/-18pp at n≈30.
WEIGHTED=(infra-observability apps-downloaders)

selector="${1:-slot}"

# Every input a suite may declare, and what this planner does with it. Reading the suite's
# inputs by name is only half the job: an input this list does not mention is one the baseline
# would drop, and the sample would then be of a differently-configured run wearing the suite's
# name. So the list is enforced below rather than merely consulted -- an unrecognised input is
# a hard error, not a silent omission. That is the same failure the whole script exists to
# avoid, and it was live here once: `timeout` went uncarried, so the six suites declaring
# `timeout: 25` were sampled at the reusable workflow's 15m default (#3732).
#
#   carried   -> reaches the baseline job, so the sample is run as the suite is
#   overridden -> the baseline sets its own value on purpose
CARRIED_INPUTS=(test_path chainsaw_config kind_config timeout)
# git_ref is deliberately not carried: a suite resolves it from its own triggering event, and
# the baseline resolves it from its own (main, or the PR head that touches the planner).
OVERRIDDEN_INPUTS=(git_ref)

# Pulls `key<TAB>value` for every key inside the reusable-workflow call's `with:` block.
# Block-scoped rather than grepping the whole file for `^\s+<name>:`, so a key that happens to
# share a name with something elsewhere in the workflow cannot be picked up, and so unknown
# keys are enumerable at all.
extract_with_block() {
  awk '
    /^[[:space:]]*with:[[:space:]]*$/ && !inblock { ind = match($0, /[^[:space:]]/) - 1; inblock = 1; next }
    inblock {
      if ($0 ~ /^[[:space:]]*$/) { next }
      li = match($0, /[^[:space:]]/) - 1
      if (li <= ind) { inblock = 0; next }
      line = $0; sub(/^[[:space:]]+/, "", line)
      if (line ~ /^#/) { next }
      if (line ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
        k = line; sub(/:.*$/, "", k)
        v = line; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
        print k "\t" v
      }
    }
  ' "$1"
}

# --- discover the suites, and their real inputs -------------------------------------
declare -a suites=() rows=()
for wf in "${WORKFLOW_DIR}"/test-*.yaml; do
  unset input
  declare -A input=()
  while IFS=$'\t' read -r k v; do
    input["${k}"]="${v}"
  done < <(extract_with_block "${wf}")

  test_path="${input[test_path]:-}"
  chainsaw_config="${input[chainsaw_config]:-}"
  kind_config="${input[kind_config]:-}"
  timeout="${input[timeout]:-}"
  [[ -n "${test_path}" ]] || continue

  suite="$(basename "${test_path}")"
  # Module suites only. test-assertion-semantics is a guard on the assertion engine, not a
  # module under test; its outcome is deterministic, so sampling it says nothing.
  [[ "${suite}" =~ ^(apps|infra)- ]] || continue

  if [[ -z "${chainsaw_config}" || -z "${kind_config}" ]]; then
    echo "baseline-plan: ${wf} declares test_path but not chainsaw_config/kind_config" >&2
    exit 1
  fi

  known=" ${CARRIED_INPUTS[*]} ${OVERRIDDEN_INPUTS[*]} "
  for k in "${!input[@]}"; do
    if [[ "${known}" != *" ${k} "* ]]; then
      echo "baseline-plan: ${wf} declares input '${k}', which the baseline does not carry." >&2
      echo "  A baseline sample must run under the same inputs as the suite's own workflow." >&2
      echo "  Add '${k}' to CARRIED_INPUTS here and to the with: block of" >&2
      echo "  .github/workflows/scheduled-baseline.yaml, or to OVERRIDDEN_INPUTS with a reason." >&2
      exit 1
    fi
  done

  # An unparseable ceiling must not become a silent 0 or a shell error downstream.
  if [[ -n "${timeout}" && ! "${timeout}" =~ ^[1-9][0-9]*$ ]]; then
    echo "baseline-plan: ${wf} declares a non-numeric timeout '${timeout}'" >&2
    exit 1
  fi

  topology="$(basename "${kind_config}" .yaml | sed 's/^kind-cluster-//')"
  suites+=("${suite}")
  rows+=("${suite}"$'\t'"${topology}"$'\t'"${test_path}"$'\t'"${chainsaw_config}"$'\t'"${kind_config}"$'\t'"${timeout}")
done

if [[ ${#suites[@]} -eq 0 ]]; then
  echo "baseline-plan: no suites discovered under ${WORKFLOW_DIR}" >&2
  exit 1
fi

# --- decide which of them run now ----------------------------------------------------
declare -a selected=()
case "${selector}" in
  all)
    selected=("${suites[@]}")
    ;;
  slot)
    # BASELINE_HOUR/BASELINE_DAY exist so the rotation can be simulated across days and
    # slots without waiting four days for the cron to prove it.
    hour="${BASELINE_HOUR:-$((10#$(date -u +%H)))}"
    # The latest slot at or before now, wrapping to the last slot before midnight. A
    # scheduled run that GitHub delays therefore still resolves to the slot it belongs to.
    slot_index=$(( ${#SLOT_HOURS[@]} - 1 ))
    for i in "${!SLOT_HOURS[@]}"; do
      if [[ ${hour} -ge ${SLOT_HOURS[i]} ]]; then
        slot_index=${i}
      fi
    done

    # Rotate the fleet across slots so no suite is permanently sampled at one time of day.
    # Suite i runs in slot ((i - day) mod nslots), so over nslots consecutive days every
    # suite visits every slot, and each slot carries len(suites)/nslots of them.
    day="${BASELINE_DAY:-$(( $(date -u +%s) / 86400 ))}"
    nslots=${#SLOT_HOURS[@]}
    for i in "${!suites[@]}"; do
      if [[ $(( ((i - day) % nslots + nslots) % nslots )) -eq ${slot_index} ]]; then
        selected+=("${suites[i]}")
      fi
    done
    for w in "${WEIGHTED[@]}"; do
      if [[ " ${suites[*]} " == *" ${w} "* && " ${selected[*]} " != *" ${w} "* ]]; then
        selected+=("${w}")
      fi
    done
    ;;
  *)
    read -r -a selected <<< "${selector//,/ }"
    for s in "${selected[@]}"; do
      if [[ " ${suites[*]} " != *" ${s} "* ]]; then
        echo "baseline-plan: unknown suite '${s}'; known: ${suites[*]}" >&2
        exit 1
      fi
    done
    ;;
esac

# --- emit ----------------------------------------------------------------------------
# The `if` is not style. As `[[ ... ]] && printf`, a final non-matching row leaves the loop --
# and so this whole pipeline, under pipefail -- at exit 1 while still printing the right
# answer on stdout. The caller sees a silent failure with correct output above it.
{
  for s in "${selected[@]}"; do
    for row in "${rows[@]}"; do
      if [[ "${row%%$'\t'*}" == "${s}" ]]; then
        printf '%s\n' "${row}"
      fi
    done
  done
} | jq -R -s -c '
  {include: (
    split("\n") | map(select(length > 0)) | map(split("\t")) | map(
      {suite: .[0], topology: .[1], test_path: .[2], chainsaw_config: .[3], kind_config: .[4]}
      # The key is omitted, not set to null or 0, when the suite declares no timeout: the
      # caller falls back only on an absent value, and an emitted 0 would be a valid number
      # that silently becomes a job with no time to run at all.
      + (if .[5] == "" then {} else {timeout: (.[5] | tonumber)} end)
    )
  )}'
