#!/usr/bin/env bash
#
# Fails when the components/ directories a chainsaw suite exercises (spec.components) and the
# on.pull_request.paths filters that start that suite disagree in either direction, or when a
# components/ directory is neither exercised by a suite nor recorded in UNCOVERED below.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Components no suite exercises. TESTING.md 'Component Coverage' holds what covering each takes.
declare -A UNCOVERED=(
  ["components/sso"]="a suite would need a TLS-serving stub IdP"
  ["components/cert-issuer/letsencrypt"]="its ClusterIssuers need ACME and a delegable zone"
  ["components/external-dns-provider/unifi"]="its webhook sidecar exits non-zero without a reachable controller; needs a stub UniFi API"
  ["components/oidc-credentials/coder"]="needs the consuming module's suite to adopt the component and its fake-store keys"
  ["components/oidc-credentials/grafana"]="as oidc-credentials/coder"
  ["components/oidc-credentials/minio"]="as oidc-credentials/coder"
  ["components/oidc-credentials/openwebui"]="as oidc-credentials/coder"
)

# --- derivation ----------------------------------------------------------------------

normalize_path() {
  local p="$1" seg
  local -a out=() segs
  IFS='/' read -r -a segs <<< "${p}"
  for seg in "${segs[@]}"; do
    case "${seg}" in
      '' | '.') ;;
      '..')
        if [[ ${#out[@]} -eq 0 ]]; then
          echo "verify-component-test-coverage: '${p}' escapes the repository root" >&2
          exit 1
        fi
        out=("${out[@]:0:$((${#out[@]} - 1))}")
        ;;
      *) out+=("${seg}") ;;
    esac
  done
  (IFS=/; echo "${out[*]}")
}

# Every spec.components entry of every Flux Kustomization in a file, as `spec.path<TAB>entry`.
flux_component_refs() {
  awk '
    function flush(   i) {
      if (kind == "Kustomization" && api ~ /kustomize\.toolkit\.fluxcd\.io/ && ncomp > 0) {
        if (path == "") { print "!NOPATH" ; err = 1 }
        else for (i = 1; i <= ncomp; i++) print path "\t" comp[i]
      }
      kind = ""; api = ""; path = ""; ncomp = 0; incomp = 0; inspec = 0
    }
    /^---[ \t]*$/                 { flush(); next }
    /^apiVersion:[ \t]/           { api = $2; incomp = 0; next }
    /^kind:[ \t]/                 { kind = $2; incomp = 0; next }
    /^spec:[ \t]*$/               { inspec = 1; incomp = 0; next }
    /^[A-Za-z]/                   { inspec = 0; incomp = 0 }
    inspec && /^  path:[ \t]/     { path = $2; incomp = 0; next }
    inspec && /^  components:[ \t]*$/ { incomp = 1; next }
    incomp && /^[ \t]*#/          { next }
    incomp && /^  -[ \t]/ {
      v = $0
      sub(/^  -[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      comp[++ncomp] = v
      next
    }
    incomp                        { incomp = 0 }
    END { flush(); if (err) exit 1 }
  ' "$1"
}

workflow_test_path() {
  awk '
    /^[ \t]*with:[ \t]*$/         { inw = 1; next }
    inw && /^[ \t]*test_path:[ \t]/ { print $2; exit }
  ' "$1"
}

workflow_component_patterns() {
  awk '
    /^on:[ \t]*$/                 { on = 1; next }
    on && /^  pull_request:[ \t]*$/ { pr = 1; next }
    /^[A-Za-z]/                   { on = 0; pr = 0; inp = 0 }
    on && pr && /^    paths:[ \t]*$/ { inp = 1; next }
    inp && /^[ \t]*#/             { next }
    inp && /^    -[ \t]/ {
      v = $0
      sub(/^    -[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      if (v ~ /^!?components\//) print v
      next
    }
    inp                           { inp = 0 }
    on && /^  [A-Za-z_]+:/        { pr = 0 }
  ' "$1"
}

# --- the check -----------------------------------------------------------------------

check() {
  local failures=0 wf suite file path ref resolved comp pattern bare dir found key
  local -A suite_components=()   # "<suite>|<component dir>" -> 1
  local -A covered=()            # component dir -> the suites exercising it
  local -A suite_workflow=()     # suite -> workflow file

  # A malformed spec.components reference is a hard error, never a skip: a silently dropped one
  # under-reports coverage and is indistinguishable from a component nothing consumes.
  while IFS= read -r file; do
    suite="$(echo "${file#"${REPO_ROOT}/ci/test/"}" | cut -d/ -f1)"
    while IFS=$'\t' read -r path ref; do
      if [[ "${path}" == "!NOPATH" ]]; then
        echo "  ${file#"${REPO_ROOT}/"}: a Flux Kustomization declares spec.components but no spec.path" >&2
        failures=$((failures + 1))
        continue
      fi
      resolved="$(normalize_path "${path}/${ref}")"
      if [[ "${resolved}" != components/* ]]; then
        if [[ "${ref}" == *components/* ]]; then
          echo "  ${file#"${REPO_ROOT}/"}: spec.components entry '${ref}' resolves to '${resolved}', outside components/" >&2
          failures=$((failures + 1))
        fi
        continue
      fi
      suite_components["${suite}|${resolved}"]=1
      covered["${resolved}"]="${covered[${resolved}]:-} ${suite}"
    done < <(flux_component_refs "${file}")
  done < <(find "${REPO_ROOT}/ci/test" -type f -name '*.yaml' | sort)

  for wf in "${REPO_ROOT}"/.github/workflows/test-*.yaml; do
    path="$(workflow_test_path "${wf}")"
    [[ -n "${path}" ]] || continue
    suite="$(basename "${path}")"
    if [[ -n "${suite_workflow[${suite}]:-}" ]]; then
      echo "  ${suite}: run by two workflows (${suite_workflow[${suite}]}, $(basename "${wf}"))" >&2
      failures=$((failures + 1))
    fi
    suite_workflow["${suite}"]="$(basename "${wf}")"
  done

  # under-trigger
  for key in "${!suite_components[@]}"; do
    suite="${key%%|*}"
    comp="${key#*|}"
    wf="${suite_workflow[${suite}]:-}"
    if [[ -z "${wf}" ]]; then
      echo "  ${suite} exercises ${comp} but no test-*.yaml declares test_path ./ci/test/${suite}" >&2
      failures=$((failures + 1))
      continue
    fi
    found=0
    while IFS= read -r pattern; do
      [[ "${pattern}" == "${comp}/**" ]] && found=1
    done < <(workflow_component_patterns "${REPO_ROOT}/.github/workflows/${wf}")
    if [[ "${found}" -eq 0 ]]; then
      echo "  ${wf} runs ${suite}, which exercises ${comp}, but does not list '${comp}/**' in on.pull_request.paths" >&2
      failures=$((failures + 1))
    fi
  done

  # over-trigger -- every green run of a suite that never touches the component reads as
  # coverage it has not got, so this half is what stops the map decaying towards more.
  for suite in "${!suite_workflow[@]}"; do
    wf="${suite_workflow[${suite}]}"
    while IFS= read -r pattern; do
      bare="${pattern#!}"
      found=0
      for key in "${!suite_components[@]}"; do
        [[ "${key%%|*}" == "${suite}" ]] || continue
        comp="${key#*|}"
        [[ "${bare}" == "${comp}/"* ]] && found=1
      done
      if [[ "${found}" -eq 0 ]]; then
        echo "  ${wf} fires on '${pattern}', but ${suite} names no such component in any spec.components" >&2
        failures=$((failures + 1))
      fi
    done < <(workflow_component_patterns "${REPO_ROOT}/.github/workflows/${wf}")
  done

  # undeclared
  while IFS= read -r dir; do
    comp="${dir#"${REPO_ROOT}/"}"
    [[ -n "${covered[${comp}]:-}" ]] && continue
    [[ -n "${UNCOVERED[${comp}]:-}" ]] && continue
    echo "  ${comp} is exercised by no chainsaw suite and is not declared in UNCOVERED" >&2
    echo "    Either name it in a suite's spec.components, or add it to UNCOVERED in $(basename "${BASH_SOURCE[0]}") with what covering it would take." >&2
    failures=$((failures + 1))
  done < <(find "${REPO_ROOT}/components" -type f -name kustomization.yaml -printf '%h\n' | sort)

  # stale
  for comp in "${!UNCOVERED[@]}"; do
    if [[ ! -f "${REPO_ROOT}/${comp}/kustomization.yaml" ]]; then
      echo "  UNCOVERED names ${comp}, which is not a component directory -- remove the entry" >&2
      failures=$((failures + 1))
    elif [[ -n "${covered[${comp}]:-}" ]]; then
      echo "  UNCOVERED names ${comp}, but${covered[${comp}]} now exercises it -- remove the entry" >&2
      failures=$((failures + 1))
    fi
  done

  [[ "${failures}" -eq 0 ]]
}

# --- self-test -----------------------------------------------------------------------

self_test() {
  local root rc
  root="$(mktemp -d -t component-coverage-selftest.XXXXXX)"
  trap 'rm -rf "${root}"' RETURN

  mkdir -p "${root}/.github/workflows" "${root}/ci/test/fake-suite" \
    "${root}/components/fake-covered" "${root}/components/fake-loose"

  cat > "${root}/components/fake-covered/kustomization.yaml" <<'EOF'
---
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
EOF
  cp "${root}/components/fake-covered/kustomization.yaml" \
     "${root}/components/fake-loose/kustomization.yaml"

  cat > "${root}/ci/test/fake-suite/fake.yaml" <<'EOF'
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: fake
spec:
  path: ./ci/test/fake-suite
  components:
  - ../../../components/fake-covered
EOF

  write_workflow() {
    cat > "${root}/.github/workflows/test-fake.yaml" <<EOF
---
name: test-fake
on:
  pull_request:
    paths:
    - 'ci/test/fake-suite/**'
$1
  workflow_dispatch:
jobs:
  test-fake:
    uses: ppat/github-workflows/.github/workflows/chainsaw-test.yaml@abc
    with:
      test_path: ./ci/test/fake-suite
EOF
  }

  run() { REPO_ROOT="${root}" check >/dev/null 2>&1; }

  # The clean baseline is asserted first: without it a "caught" verdict below could come from an
  # unrelated defect in the fixture rather than from the mutation under test.
  write_workflow "    - 'components/fake-covered/**'"
  UNCOVERED=(["components/fake-loose"]="synthetic")
  if ! run; then
    echo "self-test failed: the clean synthetic tree was rejected" >&2
    REPO_ROOT="${root}" check >&2 || true
    return 1
  fi

  write_workflow ""
  run && { echo "self-test failed: an untriggered component was not caught" >&2; return 1; }

  write_workflow "    - 'components/fake-covered/**'
    - 'components/fake-loose/**'"
  run && { echo "self-test failed: a trigger for an unexercised component was not caught" >&2; return 1; }

  write_workflow "    - 'components/fake-covered/**'"
  UNCOVERED=()
  run && { echo "self-test failed: an undeclared uncovered component was not caught" >&2; return 1; }

  UNCOVERED=(["components/fake-loose"]="synthetic" ["components/fake-covered"]="synthetic")
  run && { echo "self-test failed: an UNCOVERED entry for a covered component was not caught" >&2; return 1; }

  UNCOVERED=(["components/fake-loose"]="synthetic" ["components/fake-gone"]="synthetic")
  run && { echo "self-test failed: an UNCOVERED entry for a missing component was not caught" >&2; return 1; }

  rc=0
  echo "self-test: ok -- 5 injected defects, 5 caught, clean tree accepted"
  return "${rc}"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

if ! check; then
  echo "component test coverage and pull_request triggers disagree (see above)" >&2
  echo "Background: ci/scripts/verify-component-test-coverage.sh, TESTING.md 'Component Coverage'" >&2
  exit 1
fi
echo "component test coverage: every components/ directory is either exercised by a suite its workflow fires on, or declared uncovered"
