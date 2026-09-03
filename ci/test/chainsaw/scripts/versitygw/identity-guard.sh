#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="${HERE}/../lib"

export GUARD_NAMESPACE="versitygw"
export GUARD_POD_BLANK="versitygw-identity-guard-blank"
# The second case is not redundant: a check testing only for the file's existence
# passes the blank-volume case perfectly.
export GUARD_POD_NO_STORE_ID="versitygw-identity-guard-no-store-id"
DEADLINE=180

kubectl delete pod -n "$GUARD_NAMESPACE" \
  "$GUARD_POD_BLANK" "$GUARD_POD_NO_STORE_ID" --ignore-not-found --wait=true >/dev/null
"${LIB}/render-manifests.sh" "${HERE}/manifests/identity-guard" | kubectl apply -f - >/dev/null

guard_output() {
  local pod="$1" why="$2" marker="$3" phase output
  phase="$("${LIB}/await-pod.sh" "$GUARD_NAMESPACE" "$pod" "$DEADLINE")"
  output="$(kubectl logs -n "$GUARD_NAMESPACE" "$pod" 2>&1 || true)"
  echo "--- guard output: ${why} ---" >&2
  echo "$output" >&2

  if [ "$phase" = "Succeeded" ]; then
    echo "FAIL: the store-identity guard PASSED against ${why}." >&2
    exit 1
  fi
  if ! echo "$output" | grep -q "$marker"; then
    echo "FAIL: the guard failed against ${why}, but not by evaluating the sentinel -- it broke" >&2
    echo "      for some other reason, so this run is no evidence about the guard." >&2
    exit 1
  fi
  echo "$output"
}

blank="$(guard_output "$GUARD_POD_BLANK" "a blank volume" "store-identity sentinel")"

# Fragments within one line of the wrapped message: grep is line-oriented.
for marker in \
  "IF YOU ARE PROVISIONING A NEW STORE" \
  "IF THIS STORE WAS ALREADY SERVING" \
  "never by changing this check"; do
  if ! echo "$blank" | grep -q "$marker"; then
    echo "FAIL: the refusal is missing the guidance fragment: ${marker}" >&2
    echo "      Read in the situation it omits, this message tells an operator the wrong thing." >&2
    exit 1
  fi
done
echo "ok: the store-identity guard refused a blank volume, named the sentinel, and gave an"
echo "    operator both readings of the refusal rather than only the alarming one"

incomplete="$(guard_output "$GUARD_POD_NO_STORE_ID" "a sentinel carrying no store_id" "store_id")"

if ! echo "$incomplete" | grep -q "identifies a store but not"; then
  echo "FAIL: the guard rejected the incomplete sentinel but did not say WHY it is insufficient." >&2
  echo "      An operator reading it would reasonably conclude the file was missing entirely," >&2
  echo "      and prepare a volume that is already prepared." >&2
  exit 1
fi
if ! echo "$incomplete" | grep -q "Do not add the key by hand"; then
  echo "FAIL: the refusal does not warn against hand-adding store_id, which is the cheap way" >&2
  echo "      past it and permanently destroys the field's meaning." >&2
  exit 1
fi
echo "ok: the store-identity guard refused a sentinel that identifies a store but not which one,"
echo "    rather than reading the absent field as nothing-to-disagree-with"
