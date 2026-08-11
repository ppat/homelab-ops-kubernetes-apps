#!/usr/bin/env bash
# Wrapper around `alloy fmt`/`alloy validate` (Grafana Alloy CLI), run via the pinned
# grafana/alloy container image (see alloy-lint-version.yaml) so contributors don't
# need the `alloy` binary installed locally -- only Docker, which this repo's kind/
# chainsaw module tests already require (see TESTING.md).
#
# Usage:
#   alloy-lint.sh fmt-write <file>...   # auto-format in place (local pre-commit hook)
#   alloy-lint.sh fmt-check <file>...   # fail if formatting would change a file (CI)
#   alloy-lint.sh validate  <file>...   # validate each file's parent directory
#
# `validate` operates per parent-directory, not per-file. Our .alloy configs are
# loaded by Alloy as a directory unit (a module-owned conf.d/ merged with an optional
# cluster-owned config from a different repo), and a component in one file can
# legitimately reference a component defined in a sibling file in the same directory.
# Per-file validation would reject those as unresolved references. Directory-scoped
# validation is also the only mode that catches cross-file duplicate component
# labels -- one of the two failure classes this gate exists to catch (the other being
# components above the stability level the Helm chart pins).

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
  # Unique parent directories of the given files, so each conf.d/-style directory
  # is validated once as a unit regardless of how many of its files changed.
  mapfile -t dirs < <(for f in "$@"; do dirname -- "${f}"; done | sort -u)
  for d in "${dirs[@]}"; do
    run_alloy validate --stability.level="${stability_level}" "${d}"
  done
  ;;
*)
  echo "alloy-lint.sh: unknown mode '${mode}' (expected fmt-write, fmt-check, or validate)" >&2
  exit 1
  ;;
esac
