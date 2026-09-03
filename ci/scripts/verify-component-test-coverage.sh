#!/usr/bin/env bash
#
# Fails when the chainsaw coverage a components/ directory actually has and the pull_request
# triggers that fire it disagree.
#
# WHY IT EXISTS
# A component is not a released artifact and owns no test suite. It is exercised only where a
# suite's Flux Kustomization names it in spec.components -- and nothing connected that fact to
# the path filters that decide which suites run. Every test-*.yaml filtered on its own module
# directory and on ci/test/, so a pull request touching only components/ ran no suite at all
# and reported green (measured on #3870, a components-only bump: sixteen suites, zero
# executed). kubeconform does not close it either -- it excludes components/* because they are
# not standalone kustomizations, and on such a pull request it validates the component's
# kustomization.yaml as a file and then prints "Skipping post-build (no kustomization package
# dirs)". So components/db-backups, which six live CloudNativePG backup configurations across
# two clusters consume, could change with nothing rendering it and nothing running it.
#
# WHY IT IS A DERIVED CHECK AND NOT A HAND-WRITTEN MAP
# GitHub evaluates on.pull_request.paths from static YAML: there is no computing it, so the
# component paths have to be written into each workflow by hand. A hand-written map that goes
# stale is worse than no map, because it reads as coverage while covering nothing. This script
# is what makes the hand-written half honest: it derives the true relationship from the two
# places that already hold it -- spec.components inside ci/test/**, and test_path inside each
# test-*.yaml -- and fails on any disagreement, in either direction:
#
#   under-trigger  a suite exercises a component its workflow does not fire on   (the defect)
#   over-trigger   a workflow fires on a component its suite never exercises     (a false claim)
#   undeclared     a component no suite exercises and UNCOVERED does not name    (silent gap)
#   stale          an UNCOVERED entry that is gone, or has since become covered  (rotting map)
#
# The over-trigger and stale rules are the ones that matter later. Without them the map decays
# in the direction that looks like more coverage rather than less, which is the failure mode
# every mapping of this kind actually dies of.
#
# WHY IT IS UNGATED IN lint.yaml
# Its input is repository state, not a diff: adding a components/ directory, adding a
# spec.components line, or renaming a suite each changes the answer with no edit to any file a
# path filter could name. Gating it would skip exactly the cases it exists to catch. It costs
# seconds. Same argument as the commit-taxonomy job, for the same reason.
#
# --self-test builds a synthetic tree, injects one of each of the four defects above, and fails
# unless every one is caught, so a green verdict comes from a checker that has just shown it can
# see defects.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Components no chainsaw suite exercises, and what covering one would actually take. An entry
# here is a recorded gap, never a dismissal: the check refuses to let a new component arrive
# without one, and refuses to let one linger after the component is covered or deleted.
#
# What they have in common is that the component is not the thing that would fail. Each needs
# its consuming module's suite to deploy the component AND to assert the property the component
# is for -- which is test authoring per consumer, not a path filter.
declare -A UNCOVERED=(
  ["components/sso"]="Patches HelmReleases and Ingresses across seven modules by name+namespace. A patch target that matches nothing is a silent no-op (kustomization.yaml says so), so the failure is SSO switched off, not a build error -- only a suite deploying the target module WITH this component and asserting the patched values can see it."
  ["components/cert-issuer/letsencrypt"]="Creates ACME ClusterIssuers with a DNS-01 solver. Exercising one needs an ACME account and a delegable DNS zone, which would make the suite depend on Let's Encrypt staging and on a real zone."
  ["components/external-dns-provider/unifi"]="The variant both clusters actually run, and the one Renovate bumps most. Its webhook sidecar EXITS NON-ZERO at startup when it cannot reach a UniFi controller (measured on 0.10.12: 'initializing provider ... no such host', exit 1), so covering it needs a stub UniFi API in the suite's pre-requisites, not just a spec.components line. The pihole variant is covered in its place because its provider is in-tree and external-dns starts without the server answering."
  ["components/oidc-credentials/coder"]="One ExternalSecret carrying OIDC client credentials. Covering it means the consuming module's suite adopting the component and its fake-store keys."
  ["components/oidc-credentials/grafana"]="As oidc-credentials/coder."
  ["components/oidc-credentials/minio"]="As oidc-credentials/coder."
  ["components/oidc-credentials/openwebui"]="As oidc-credentials/coder."
)

# --- path handling -------------------------------------------------------------------

# Resolves a spec.components entry against its Kustomization's spec.path. Both are
# repository-relative once normalised, which is what lets a component reference be compared
# against a directory on disk and against a path filter without any of the three agreeing on
# how many ../ segments to write.
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

# --- derivation ----------------------------------------------------------------------

# Every spec.components entry of every Flux Kustomization in a file, as `spec.path<TAB>entry`.
# Document-scoped rather than grepping the file for '- ../components/...', so an entry can only
# ever be paired with the path it is actually relative to. A Kustomization that declares
# components without a path is a hard error: silently dropping it would under-report coverage,
# which is the direction that reads as safe and is not.
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

# The reusable-workflow input that says which suite a test-*.yaml runs. Read rather than
# restated for the same reason ci/scripts/baseline-plan.sh reads it: a suite that moves must
# not leave a second file still believing the old location.
workflow_test_path() {
  awk '
    /^[ \t]*with:[ \t]*$/         { inw = 1; next }
    inw && /^[ \t]*test_path:[ \t]/ { print $2; exit }
  ' "$1"
}

# Every on.pull_request.paths entry naming components/, negations included and marked.
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

  # 1. what each suite exercises
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
        # A reference that reads like a component but does not land in components/ has the
        # wrong number of ../ segments. Skipping it quietly would under-report coverage and
        # look exactly like the component having no consumer.
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

  # 2. which workflow runs which suite, and what it claims to fire on
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

  # 3. under-trigger -- the defect. A suite exercising a component whose workflow does not
  #    fire on it runs on the component's own pull request only by accident.
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

  # 4. over-trigger -- a workflow firing on a component its suite never touches spends a kind
  #    cluster proving nothing, and every green run of it reads as coverage the suite has not
  #    got. Negations are held to the same rule: one that sits under no exercised component is
  #    excluding files nothing would have matched.
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

  # 5. undeclared -- a component directory (one carrying a kustomization.yaml) that no suite
  #    exercises and UNCOVERED does not name. This is what stops a new component arriving with
  #    no coverage and no record of the fact.
  while IFS= read -r dir; do
    comp="${dir#"${REPO_ROOT}/"}"
    [[ -n "${covered[${comp}]:-}" ]] && continue
    [[ -n "${UNCOVERED[${comp}]:-}" ]] && continue
    echo "  ${comp} is exercised by no chainsaw suite and is not declared in UNCOVERED" >&2
    echo "    Either name it in a suite's spec.components, or add it to UNCOVERED in $(basename "${BASH_SOURCE[0]}") with what covering it would take." >&2
    failures=$((failures + 1))
  done < <(find "${REPO_ROOT}/components" -type f -name kustomization.yaml -printf '%h\n' | sort)

  # 6. stale -- an UNCOVERED entry naming a component that is gone, or that has since been
  #    covered. Both leave the file claiming something untrue about today's tree.
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

# Each case is a one-line mutation of a synthetic tree that the baseline has just been shown to
# accept, so a caught defect is attributable to that mutation and to nothing else.
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

  # A baseline that passes. Without it every "caught" verdict below could come from an
  # unrelated defect in the fixture rather than from the mutation under test.
  write_workflow "    - 'components/fake-covered/**'"
  UNCOVERED=(["components/fake-loose"]="synthetic")
  if ! run; then
    echo "self-test failed: the clean synthetic tree was rejected" >&2
    REPO_ROOT="${root}" check >&2 || true
    return 1
  fi

  # 1. under-trigger: the suite exercises fake-covered, the workflow stops firing on it.
  write_workflow ""
  run && { echo "self-test failed: an untriggered component was not caught" >&2; return 1; }

  # 2. over-trigger: the workflow fires on a component the suite never names.
  write_workflow "    - 'components/fake-covered/**'
    - 'components/fake-loose/**'"
  run && { echo "self-test failed: a trigger for an unexercised component was not caught" >&2; return 1; }

  # 3. undeclared: a component that is neither exercised nor recorded as uncovered.
  write_workflow "    - 'components/fake-covered/**'"
  UNCOVERED=()
  run && { echo "self-test failed: an undeclared uncovered component was not caught" >&2; return 1; }

  # 4a. stale: UNCOVERED naming a component that is now exercised.
  UNCOVERED=(["components/fake-loose"]="synthetic" ["components/fake-covered"]="synthetic")
  run && { echo "self-test failed: an UNCOVERED entry for a covered component was not caught" >&2; return 1; }

  # 4b. stale: UNCOVERED naming a component that does not exist.
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
