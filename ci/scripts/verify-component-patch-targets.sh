#!/usr/bin/env bash
#
# Fails when a component declares a patch target that matches nothing, or that matches something
# without changing it.
#
# WHY IT EXISTS
# A kustomize patch whose target selector matches no resource is a SILENT no-op. Measured on
# kustomize 5.8.1, all three of these exit 0 and emit no warning:
#
#   target matches nothing        -> the resource keeps whatever it had; build succeeds
#   op: replace on a missing key  -> the key is CREATED (replace behaves as upsert here)
#   op: add on an existing key    -> overwritten
#
# So for a component built entirely out of `patches:` -- components/sso is the one that matters --
# **a target matching nothing is the only way it can fail, and it fails invisibly.** Nothing
# downstream catches it either: kubeconform excludes components/*, and a chainsaw suite can only
# ever reach the one or two targets whose module that suite happens to deploy.
#
# The consequence is specific rather than theoretical. components/sso's Ingress patch swaps in the
# authentik forward-auth middleware; a stale name or namespace there leaves the Ingress serving
# with whatever middleware it already had -- for a newly-added Ingress, none at all -- and reports
# success. That is an authentication control silently absent, on a green build.
#
# WHAT IT CHECKS
# For every `target:` every component declares, both halves of the property, because "the target
# resolves" and "the patch took effect" are exactly the two states the silent no-op separates:
#
#   1. resolves    some module in this repository builds a resource the selector matches
#   2. takes effect  applying that one patch to that module actually changes the output
#
# Nothing here is a hand-maintained map. The targets come out of each component's own
# kustomization.yaml, and the resources come out of `kustomize build` over every module -- so a
# module that renames a HelmRelease, moves a namespace, or drops an Ingress turns the component's
# now-stale target red on the pull request that does it.
#
# WHAT IT DOES NOT CLAIM
# That any cluster actually mixes the component into that module -- `spec.components` lives in the
# clusters repository and is deliberately not this repository's business. It proves the target is
# not stale against the manifests this repository ships, which is the half that can rot here.
#
# --self-test injects a target that matches nothing and a patch that matches without changing
# anything, and fails unless both are caught.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MODULE_GLOBS=("apps/subsystems" "infrastructure/subsystems")

# --- derivation ----------------------------------------------------------------------

# Every `patches:` entry of a component kustomization, as
# `patch file<TAB>group<TAB>kind<TAB>name<TAB>namespace`, with `-` for an absent selector field.
# An absent field is a wildcard to kustomize, so it must stay distinguishable from an empty one.
component_targets() {
  awk '
    /^patches:[ \t]*$/            { inp = 1; next }
    /^[A-Za-z]/                   { if (inp) { flush() } inp = 0 }
    function flush() {
      if (p != "") printf("%s\t%s\t%s\t%s\t%s\n", p, g == "" ? "-" : g, k == "" ? "-" : k,
                          n == "" ? "-" : n, ns == "" ? "-" : ns)
      p = ""; g = ""; k = ""; n = ""; ns = ""; intgt = 0
    }
    inp && /^[ \t]*#/             { next }
    inp && /^-[ \t]+path:[ \t]/   { flush(); p = $3; next }
    inp && /^[ \t]+target:[ \t]*$/ { intgt = 1; next }
    inp && intgt && /^[ \t]+(group|version|kind|name|namespace):[ \t]/ {
      key = $1; sub(/:$/, "", key)
      v = $0; sub(/^[ \t]+[A-Za-z]+:[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      if (key == "group") g = v
      else if (key == "kind") k = v
      else if (key == "name") n = v
      else if (key == "namespace") ns = v
      next
    }
    END { if (inp) flush() }
  ' "$1"
}

# Every resource a build emits, as `kind<TAB>namespace<TAB>name`. Tracks whether it is inside the
# document's own `metadata:` block rather than matching `name:` anywhere, because spec fields sit
# at the same indent and would otherwise overwrite the identity of the object.
build_index() {
  awk '
    function flush() { if (kind != "") print kind "\t" (ns == "" ? "-" : ns) "\t" name; kind = ""; name = ""; ns = ""; inmeta = 0 }
    /^---[ \t]*$/                 { flush(); next }
    /^kind:[ \t]/                 { kind = $2; inmeta = 0; next }
    /^metadata:[ \t]*$/           { inmeta = 1; next }
    /^[A-Za-z]/                   { inmeta = 0 }
    inmeta && /^  name:[ \t]/     { name = $2; next }
    inmeta && /^  namespace:[ \t]/ { ns = $2; next }
    END { flush() }
  '
}

# kustomize treats a target `name` as a regular expression, so an exact name and an alternation
# like "(lidarr|prowlarr|...)" go down the same path. Anchored, because an unanchored match would
# let a target that is subtly wrong still look satisfied by a longer name.
target_matches() {
  local t_kind="$1" t_name="$2" t_ns="$3" r_kind="$4" r_ns="$5" r_name="$6"
  [[ "${t_kind}" == "-" || "${t_kind}" == "${r_kind}" ]] || return 1
  [[ "${t_ns}" == "-" || "${t_ns}" == "${r_ns}" ]] || return 1
  [[ "${t_name}" == "-" ]] && return 0
  printf '%s' "${r_name}" | grep -Eq "^(${t_name})\$"
}

# --- the check -----------------------------------------------------------------------

# Builds <module> twice through the SAME synthetic root -- once with the single patch under test
# and once without it -- so the two outputs differ only by the patch. Comparing against the
# module's own `kustomize build` instead would drown the signal in resource-ordering differences
# that the extra root introduces.
patch_changes_module() {
  local module="$1" patch_src="$2" group="$3" kind="$4" name="$5" namespace="$6"
  local probe="${REPO_ROOT}/${PROBE_DIR}"
  rm -rf "${probe}"; mkdir -p "${probe}"
  cp "${patch_src}" "${probe}/p.yaml"

  {
    echo "---"
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "resources:"
    echo "- ../${module}"
  } > "${probe}/kustomization.yaml"
  local without; without="$(kubectl kustomize "${probe}" 2>/dev/null)" || return 2

  {
    echo "patches:"
    echo "- path: p.yaml"
    echo "  target:"
    [[ "${group}" != "-" ]] && echo "    group: ${group}"
    [[ "${kind}" != "-" ]] && echo "    kind: ${kind}"
    [[ "${name}" != "-" ]] && echo "    name: \"${name}\""
    [[ "${namespace}" != "-" ]] && echo "    namespace: ${namespace}"
  } >> "${probe}/kustomization.yaml"
  local with; with="$(kubectl kustomize "${probe}" 2>/dev/null)" || return 2

  [[ "${with}" != "${without}" ]]
}

check() {
  local failures=0 comp ck module rel patch group kind name namespace rc
  local -a modules=()
  local -A index=()

  while IFS= read -r module; do
    modules+=("${module}")
    index["${module}"]="$(kubectl kustomize "${REPO_ROOT}/${module}" 2>/dev/null | build_index)" || {
      echo "  ${module}: kustomize build failed -- cannot establish what it emits" >&2
      failures=$((failures + 1))
    }
  done < <(cd "${REPO_ROOT}" && find "${MODULE_GLOBS[@]}" -mindepth 1 -maxdepth 1 -type d | sort)

  while IFS= read -r ck; do
    comp="$(dirname "${ck}")"
    rel="${comp#"${REPO_ROOT}/"}"
    while IFS=$'\t' read -r patch group kind name namespace; do
      [[ -n "${patch}" ]] || continue
      if [[ ! -f "${comp}/${patch}" ]]; then
        echo "  ${rel}: patches entry names '${patch}', which does not exist" >&2
        failures=$((failures + 1))
        continue
      fi

      # 1. does the selector resolve against anything this repository ships?
      local -a hits=()
      for module in "${modules[@]}"; do
        while IFS=$'\t' read -r r_kind r_ns r_name; do
          [[ -n "${r_kind}" ]] || continue
          if target_matches "${kind}" "${name}" "${namespace}" "${r_kind}" "${r_ns}" "${r_name}"; then
            hits+=("${module}")
            break
          fi
        done <<< "${index[${module}]}"
      done

      if [[ ${#hits[@]} -eq 0 ]]; then
        echo "  ${rel}/${patch}: target {kind=${kind} name=${name} namespace=${namespace}} matches no resource any module builds." >&2
        echo "    kustomize applies this as a SILENT no-op -- the component ships doing nothing here." >&2
        echo "    Either the module renamed/moved the resource, or the target is stale." >&2
        failures=$((failures + 1))
        continue
      fi

      # 2. and does applying it there actually change the output?
      # rc captured explicitly: inside `if ! cmd`, $? is the negation's result, not the
      # function's, so the build-failure case would be indistinguishable from the inert case.
      rc=0
      patch_changes_module "${hits[0]}" "${comp}/${patch}" "${group}" "${kind}" "${name}" "${namespace}" || rc=$?
      if [[ "${rc}" -ne 0 ]]; then
        if [[ "${rc}" -eq 2 ]]; then
          echo "  ${rel}/${patch}: probe build against ${hits[0]} failed" >&2
        else
          echo "  ${rel}/${patch}: target matches ${hits[0]} but applying the patch changes nothing there" >&2
          echo "    The selector resolves and the patch is inert -- coverage that isn't." >&2
        fi
        failures=$((failures + 1))
      fi
    done < <(component_targets "${ck}")
  done < <(find "${REPO_ROOT}/components" -type f -name kustomization.yaml | sort)

  rm -rf "${REPO_ROOT:?}/${PROBE_DIR}"
  [[ "${failures}" -eq 0 ]]
}

# --- self-test -----------------------------------------------------------------------

self_test() {
  local root
  root="$(mktemp -d -t component-patch-targets-selftest.XXXXXX)"
  trap 'rm -rf "${root}"' RETURN

  mkdir -p "${root}/apps/subsystems/fake" "${root}/components/fake" "${root}/ci/scripts"
  cat > "${root}/apps/subsystems/fake/kustomization.yaml" <<'EOF'
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ing.yaml
EOF
  cat > "${root}/apps/subsystems/fake/ing.yaml" <<'EOF'
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fake-ing
  namespace: fake
  annotations:
    example.com/mw: original
spec:
  rules: []
EOF
  cat > "${root}/components/fake/p.yaml" <<'EOF'
---
- op: replace
  path: /metadata/annotations/example.com~1mw
  value: patched
EOF
  # An inert patch: sets the annotation to the value it already has.
  cat > "${root}/components/fake/inert.yaml" <<'EOF'
---
- op: replace
  path: /metadata/annotations/example.com~1mw
  value: original
EOF

  write_component() {
    { echo "---"
      echo "apiVersion: kustomize.config.k8s.io/v1alpha1"
      echo "kind: Component"
      echo "patches:"
      echo "$1"
    } > "${root}/components/fake/kustomization.yaml"
  }
  run() { REPO_ROOT="${root}" PROBE_DIR="${PROBE_DIR}" check >/dev/null 2>&1; }

  # Baseline. Asserted first, so a caught defect below is attributable to its own mutation.
  write_component "- path: p.yaml
  target:
    kind: Ingress
    name: fake-ing
    namespace: fake"
  if ! run; then
    echo "self-test failed: the clean synthetic tree was rejected" >&2
    REPO_ROOT="${root}" check >&2 || true
    return 1
  fi

  # 1. the silent no-op: a selector that matches nothing.
  write_component "- path: p.yaml
  target:
    kind: Ingress
    name: fake-ing
    namespace: wrong-namespace"
  run && { echo "self-test failed: a target matching nothing was not caught" >&2; return 1; }

  # 2. resolves, but the patch is inert -- "matches" without "takes effect".
  write_component "- path: inert.yaml
  target:
    kind: Ingress
    name: fake-ing
    namespace: fake"
  run && { echo "self-test failed: a matching but inert patch was not caught" >&2; return 1; }

  # 3. a patch file the component names but does not ship.
  write_component "- path: gone.yaml
  target:
    kind: Ingress
    name: fake-ing
    namespace: fake"
  run && { echo "self-test failed: a missing patch file was not caught" >&2; return 1; }

  echo "self-test: ok -- 3 injected defects, 3 caught, clean tree accepted"
}

# Probe scratch directory. Lives inside the repository because kustomize refuses to read a patch
# file outside the kustomization root, and carries the pid so two concurrent runs cannot collide.
PROBE_DIR="${PROBE_DIR:-.component-patch-probe-$$}"

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

if ! check; then
  echo "a component declares a patch target that matches nothing, or that changes nothing (see above)" >&2
  echo "Background: ci/scripts/verify-component-patch-targets.sh, TESTING.md 'Component Coverage'" >&2
  exit 1
fi
echo "component patch targets: every declared target resolves against a module this repo ships, and changes it"
