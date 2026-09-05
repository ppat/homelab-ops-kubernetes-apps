#!/usr/bin/env bash
#
# Fails a component patch target that matches nothing, or that matches without changing anything.
# kustomize applies both as exit-0 no-ops with no warning, so an unchecked stale selector in
# components/sso ships an Ingress with no forward-auth middleware and a green build.
#
# It does not claim any cluster mixes the component into that module -- spec.components lives in
# the clusters repository. Only that the target is not stale against what this repository ships.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MODULE_GLOBS=("apps/subsystems" "infrastructure/subsystems")

# --- derivation ----------------------------------------------------------------------

# Every `patches:` entry of a component kustomization, as
# `patch file<TAB>group<TAB>kind<TAB>name<TAB>namespace`, with `-` for an absent selector field.
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

# Every resource a build emits, as `kind<TAB>namespace<TAB>name`.
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

# kustomize treats a target `name` as a regular expression, hence grep -E. Anchored deliberately:
# unanchored, a subtly wrong target would look satisfied by any longer name that contains it.
target_matches() {
  local t_kind="$1" t_name="$2" t_ns="$3" r_kind="$4" r_ns="$5" r_name="$6"
  [[ "${t_kind}" == "-" || "${t_kind}" == "${r_kind}" ]] || return 1
  [[ "${t_ns}" == "-" || "${t_ns}" == "${r_ns}" ]] || return 1
  [[ "${t_name}" == "-" ]] && return 0
  printf '%s' "${r_name}" | grep -Eq "^(${t_name})\$"
}

# --- the check -----------------------------------------------------------------------

# Both builds go through the same synthetic root, differing only by the patch. Diffing against
# the module's own build instead drowns the patch in the ordering changes the extra root causes.
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

      # rc is captured rather than tested with `if !`, under which $? is the negation's result
      # and a probe-build failure (rc=2) would be reported as the inert case.
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

  # The clean baseline is asserted first: without it a "caught" verdict below could come from an
  # unrelated defect in the fixture rather than from the mutation under test.
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

  write_component "- path: p.yaml
  target:
    kind: Ingress
    name: fake-ing
    namespace: wrong-namespace"
  run && { echo "self-test failed: a target matching nothing was not caught" >&2; return 1; }

  write_component "- path: inert.yaml
  target:
    kind: Ingress
    name: fake-ing
    namespace: fake"
  run && { echo "self-test failed: a matching but inert patch was not caught" >&2; return 1; }

  write_component "- path: gone.yaml
  target:
    kind: Ingress
    name: fake-ing
    namespace: fake"
  run && { echo "self-test failed: a missing patch file was not caught" >&2; return 1; }

  echo "self-test: ok -- 3 injected defects, 3 caught, clean tree accepted"
}

# Inside the repository, because kustomize refuses to read a patch file outside its root.
PROBE_DIR="${PROBE_DIR:-.component-patch-probe-$$}"
trap 'rm -rf "${REPO_ROOT:?}/${PROBE_DIR:?}"' EXIT

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
