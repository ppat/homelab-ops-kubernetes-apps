#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: render-manifests.sh <kustomize-dir>" >&2
  exit 2
fi

dir="$1"
if [ ! -f "${dir}/kustomization.yaml" ]; then
  echo "FAIL: ${dir} has no kustomization.yaml" >&2
  exit 2
fi

# SUBSTITUTION BEFORE THE BUILD, AND THE ORDER IS LOAD-BEARING. kustomize decides
# quoting from the text it parses, which at build time is the placeholder: a
# quoted `"${AGE_MINUTES}"` is re-emitted bare and substituting afterwards yields
# a number where the API requires a string.
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cp -R "${dir}/." "${work}/"

while IFS= read -r -d '' file; do
  flux envsubst <"$file" >"${file}.rendered"
  mv "${file}.rendered" "$file"
done < <(find "$work" -type f -print0)

kubectl kustomize "$work"
