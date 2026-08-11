#!/usr/bin/env bash
# Wrapper around `alloy fmt`/`alloy validate` (Grafana Alloy CLI), run via the pinned
# grafana/alloy container image (see alloy-lint-version.yaml) so contributors don't
# need the `alloy` binary installed locally -- only Docker, which this repo's kind/
# chainsaw module tests already require (see TESTING.md).
#
# Usage:
#   alloy-lint.sh fmt-write <file>...   # auto-format in place (local pre-commit hook)
#   alloy-lint.sh fmt-check <file>...   # fail if formatting would change a file (CI)
#   alloy-lint.sh validate  <file>...   # validate all given files as one merged unit
#
# `validate` merges every given file into one scratch directory and validates that as
# a single unit, rather than per-file or per-git-parent-directory. Our .alloy configs
# are loaded by Alloy as a directory unit (a module-owned conf.d/ merged with an
# optional cluster-owned config), and a component in one file can legitimately
# reference a component defined in a sibling file -- per-file validation would reject
# those as unresolved references. That merge can itself span more than one git
# directory: infrastructure/subsystems/observability-core/alloy/conf.d/ and
# ci/test/infra-observability/pre-requisites/alloy/conf.d/ are two different paths in
# this repo that Flux composes into the same ConfigMap (and therefore the same Alloy
# runtime directory) via a `spec.patches` entry -- see
# ci/test/infra-observability/infra-observability-core.yaml. Grouping by each file's
# own git parent directory validates those apart and produces false "component does
# not exist" errors for references that resolve correctly once actually deployed.
# Merging everything is also the only mode that catches cross-file duplicate component
# labels -- one of the two failure classes this gate exists to catch (the other being
# components above the stability level the Helm chart pins).
#
# This assumes the repo has exactly one Alloy deployment (true today). A second,
# independent one would incorrectly get validated together with this one -- if that
# ever happens, scope the merge per-deployment (e.g. a shared ancestor directory
# convention) rather than reverting to per-git-directory grouping.

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

mode="${1:?usage: alloy-lint.sh <fmt-write|fmt-check|validate> <file>...}"
shift

# pre-commit already skips this hook entirely when no *.alloy files match (see the
# `files:` regex in .pre-commit-config.yaml) and the CI job skips its steps the same
# way (see .github/workflows/lint.yaml) -- this guard just makes direct/manual
# invocation with no files a no-op instead of an error.
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
fmt-write)
  for f in "$@"; do
    run_alloy fmt --write "${f}"
  done
  ;;
fmt-check)
  for f in "$@"; do
    run_alloy fmt --test "${f}"
  done
  ;;
validate)
  # `run_alloy` only bind-mounts $(pwd) into the container, so the scratch dir must be
  # a child of $(pwd) (repo root, in both CI and pre-commit) to be visible inside it.
  scratch="$(mktemp -d -p "$(pwd)" .alloy-lint-validate.XXXXXX)"
  trap 'rm -rf "${scratch}"' EXIT
  for f in "$@"; do
    base="$(basename -- "${f}")"
    if [[ -e "${scratch}/${base}" ]]; then
      echo "alloy-lint.sh: two *.alloy files share the name '${base}'; cannot merge" \
        "them into one validation unit (would silently drop one)" >&2
      exit 1
    fi
    cp -- "${f}" "${scratch}/${base}"
  done
  run_alloy validate --stability.level="${stability_level}" "$(basename -- "${scratch}")"
  ;;
*)
  echo "alloy-lint.sh: unknown mode '${mode}' (expected fmt-write, fmt-check, or validate)" >&2
  exit 1
  ;;
esac
