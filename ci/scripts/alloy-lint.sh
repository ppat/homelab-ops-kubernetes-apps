#!/usr/bin/env bash
# Wrapper around `alloy fmt`/`alloy validate` (Grafana Alloy CLI), run via the pinned
# grafana/alloy container image (see alloy-lint-version.yaml) so contributors don't
# need the `alloy` binary installed locally -- only Docker, which this repo's kind/
# chainsaw module tests already require (see TESTING.md).
#
# Usage:
#   alloy-lint.sh fmt-check <file>...   # fail if formatting would change a file (CI)
#   alloy-lint.sh validate  <file>...   # validate all given files as one merged unit
#
# Both modes are driven by the `alloy` CI job in .github/workflows/lint.yaml -- there
# is no local pre-commit hook (this repo's primary dev environment has no Docker, and
# the shared lint-pre-commit reusable workflow only runs a fixed hardcoded hook-id
# list, so a local hook here would get zero CI coverage anyway; see the `alloy` job's
# comments). There is deliberately no `fmt-write` mode: it existed only to back that
# hook, and Docker's absence locally means nothing could actually call it.
#
# `validate` merges files into scratch directories and validates each as a single
# unit, rather than per-file or per-git-parent-directory. Our .alloy configs are loaded
# by Alloy as a directory unit (a module-owned conf.d/ merged with an optional
# cluster-owned config), and a component in one file can legitimately reference a
# component defined in a sibling file -- per-file validation would reject those as
# unresolved references. That merge can itself span more than one git directory:
# infrastructure/subsystems/observability-core/alloy/conf.d/ and
# ci/test/infra-observability/pre-requisites/alloy/conf.d/ are two different paths in
# this repo that Flux composes into the same ConfigMap (and therefore the same Alloy
# runtime directory) via a `spec.patches` entry -- see
# ci/test/infra-observability/infra-observability-core.yaml. Grouping by each file's
# own git parent directory validates those apart and produces false "component does
# not exist" errors for references that resolve correctly once actually deployed.
# Merging is also the only mode that catches cross-file duplicate component labels --
# one of the two failure classes this gate exists to catch (the other being components
# above the stability level the Helm chart pins).
#
# WHICH FILES MERGE WITH WHICH: THE UNIT IS THE DIRECTORY *NAME*.
# There is more than one Alloy deployment in this repo -- the node-log DaemonSet loads
# `alloy/conf.d/`, the Kubernetes Event singleton loads `alloy/events.d/` -- and they
# are separate processes with separate component namespaces. Validating them together
# would be actively wrong: both legitimately declare `loki.write "default"`, and a
# merged unit rejects that as a duplicate label. So files are grouped by the BASENAME
# of their parent directory: everything under any `conf.d/` is one unit, everything
# under any `events.d/` is another. The basename rather than the full path is what lets
# the CI fixture above (a different path, same `conf.d/` name) merge with the module it
# stands in for, which is the whole point of that fixture.
#
# A new Alloy deployment therefore needs its own distinctly-named config directory. Two
# unrelated deployments both calling theirs `conf.d/` would be silently merged and would
# fail on the first component name they happen to share.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

alloy_version="$(sed -n 's/^version: "\(.*\)"$/\1/p' "${script_dir}/alloy-lint-version.yaml")"
if [[ -z "${alloy_version}" ]]; then
  echo "alloy-lint.sh: could not read pinned version from ${script_dir}/alloy-lint-version.yaml" >&2
  exit 1
fi
alloy_image="grafana/alloy:${alloy_version}"

# Matches the --stability.level the Helm chart pins for the alloy container
# (`--stability.level=generally-available`); keep in sync with that HelmRelease.
stability_level="generally-available"

mode="${1:?usage: alloy-lint.sh <fmt-check|validate> <file>...}"
shift

# The CI job already skips its steps entirely when no *.alloy files are matched by
# detect-changes (see .github/workflows/lint.yaml) -- this guard just makes direct/
# manual invocation with no files a no-op instead of an error.
if [[ $# -eq 0 ]]; then
  echo "alloy-lint.sh: no files given, nothing to do"
  exit 0
fi

run_alloy() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "$(pwd):/workdir" \
    --workdir /workdir \
    "${alloy_image}" \
    "$@"
}

case "${mode}" in
fmt-check)
  for f in "$@"; do
    run_alloy fmt --test "${f}"
  done
  ;;
validate)
  # `run_alloy` only bind-mounts $(pwd) into the container, so the scratch dirs must be
  # children of $(pwd) (the repo root in CI) to be visible inside it.
  scratch_root="$(mktemp -d -p "$(pwd)" .alloy-lint-validate.XXXXXX)"
  trap 'rm -rf "${scratch_root}"' EXIT

  declare -A units=()
  for f in "$@"; do
    unit="$(basename -- "$(dirname -- "${f}")")"
    # A file with no parent directory to name a unit after would resolve to "." and be
    # copied into the scratch root, alongside the unit directories rather than into one.
    if [[ "${unit}" == "." || "${unit}" == ".." || "${unit}" == "/" ]]; then
      echo "alloy-lint.sh: '${f}' is not inside a config directory; every *.alloy file" \
        "must live in one (conf.d/, events.d/, ...) because the directory name is the" \
        "validation unit" >&2
      exit 1
    fi
    base="$(basename -- "${f}")"
    mkdir -p "${scratch_root}/${unit}"
    if [[ -e "${scratch_root}/${unit}/${base}" ]]; then
      echo "alloy-lint.sh: two *.alloy files in unit '${unit}' share the name" \
        "'${base}'; cannot merge them into one validation unit (would silently" \
        "drop one)" >&2
      exit 1
    fi
    cp -- "${f}" "${scratch_root}/${unit}/${base}"
    units["${unit}"]=1
  done

  # Sorted so the output order does not depend on associative-array iteration order.
  while IFS= read -r unit; do
    echo "alloy-lint.sh: validating unit '${unit}'"
    run_alloy validate --stability.level="${stability_level}" \
      "$(basename -- "${scratch_root}")/${unit}"
  done < <(printf '%s\n' "${!units[@]}" | sort)
  ;;
*)
  echo "alloy-lint.sh: unknown mode '${mode}' (expected fmt-check or validate)" >&2
  exit 1
  ;;
esac
