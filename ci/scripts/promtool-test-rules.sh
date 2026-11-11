#!/usr/bin/env bash
# Runs `promtool test rules` over unit-test files for PrometheusRule manifests.
#
# Usage:
#   promtool-test-rules.sh <file.rules-test.yaml>...
#
# Each test file sits next to the PrometheusRule manifest it tests and lists that
# manifest by its plain file name under `rule_files:`. promtool cannot read a
# PrometheusRule custom resource, only a bare rule file, so each listed manifest is
# reduced to its `.spec` (the `groups:` document) in a scratch directory before the
# test runs there.
#
# promtool comes from the pinned prom/prometheus image (promtool-version.yaml) through
# Docker. Set PROMTOOL to a local promtool binary to run without Docker.
#
# Needs `yq` (mikefarah) on PATH.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 ]]; then
  echo "promtool-test-rules.sh: no test files given, nothing to do"
  exit 0
fi

if [[ -z "${PROMTOOL:-}" ]]; then
  version="$(sed -n 's/^version: "\(.*\)"$/\1/p' "${script_dir}/promtool-version.yaml")"
  if [[ -z "${version}" ]]; then
    echo "promtool-test-rules.sh: could not read pinned version from promtool-version.yaml" >&2
    exit 1
  fi
fi

# Docker bind-mounts $(pwd), so scratch directories must live under it.
scratch_root="$(mktemp -d -p "$(pwd)" .promtool-test-rules.XXXXXX)"
trap 'rm -rf "${scratch_root}"' EXIT

run_promtool() {
  local dir="$1"
  shift
  if [[ -n "${PROMTOOL:-}" ]]; then
    (cd "${dir}" && "${PROMTOOL}" "$@")
  else
    docker run --rm \
      --user "$(id -u):$(id -g)" \
      --volume "$(pwd):/workdir" \
      --workdir "/workdir/${dir#"$(pwd)/"}" \
      --entrypoint promtool \
      "prom/prometheus:${version}" \
      "$@"
  fi
}

failed=0
i=0
for test_file in "$@"; do
  i=$((i + 1))
  src_dir="$(dirname -- "${test_file}")"
  work="${scratch_root}/${i}"
  mkdir -p "${work}"
  cp -- "${test_file}" "${work}/"

  while IFS= read -r rule_file; do
    [[ -z "${rule_file}" ]] && continue
    if [[ "${rule_file}" == */* ]]; then
      echo "promtool-test-rules.sh: ${test_file}: rule_files entry '${rule_file}' must be a" \
        "plain file name in the same directory" >&2
      exit 1
    fi
    if [[ "$(yq '.kind' "${src_dir}/${rule_file}")" != "PrometheusRule" ]]; then
      echo "promtool-test-rules.sh: ${src_dir}/${rule_file} is not a PrometheusRule" >&2
      exit 1
    fi
    yq '.spec' "${src_dir}/${rule_file}" >"${work}/${rule_file}"
  done < <(yq '.rule_files[]' "${test_file}")

  echo "::group::${test_file}"
  if ! run_promtool "${work}" test rules "$(basename -- "${test_file}")"; then
    failed=1
    echo "promtool-test-rules.sh: FAILED ${test_file}" >&2
  fi
  echo "::endgroup::"
done

exit "${failed}"
