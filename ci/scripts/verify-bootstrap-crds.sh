#!/usr/bin/env bash
#
# Fails when infrastructure/bootstrap/crds/ builds to anything besides CustomResourceDefinitions.
#
# The bundle strips non-CRD kinds out of vendored upstream release manifests with a kustomize
# `$patch: delete` denylist. Kustomize targets match with Go's RE2 regexp, which cannot express
# "any kind except CustomResourceDefinition", so the filter cannot fail closed on its own: a
# release that ships a kind absent from the denylist sails through silently, and the surviving
# namespaced objects break bootstrap because they target namespaces that deliberately do not
# exist yet (the bundle deletes Namespace by design -- modules own their namespaces). That is
# not a CI-only problem: DESIGN.md makes this bundle the manual one-time apply for first-time
# cluster setup and disaster recovery, so an escaped kind fails an operator at the worst
# possible moment. #3803 shipped six NetworkPolicies through the filter exactly this way.
#
# This check is the fail-closed half of that filter: any kind the denylist misses turns into a
# build failure here instead of an apply error on the disaster-recovery path. It is also why
# the kubeconform validation can keep excluding this bundle -- schema validity is not the
# property that matters here, kind survival is.
#
# --self-test feeds the check known-bad and known-good streams and fails unless both verdicts
# are right, so a green run comes from a checker that has just demonstrated it can see escapes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CRDS_DIR="${REPO_ROOT}/infrastructure/bootstrap/crds"

# kustomize emits document-level keys at column zero, so '^kind: ' cannot match text inside an
# indented block scalar. Refusing an input with zero CRDs keeps the check from passing vacuously
# when handed an empty or wrong build.
check() {
  awk '
    /^kind: / { if ($2 == "CustomResourceDefinition") crd++; else bad[$2]++ }
    END {
      for (k in bad) { badn++; printf("%6d %s\n", bad[k], k) > "/dev/stderr" }
      if (badn) {
        print "these kinds escaped the $patch: delete denylist in infrastructure/bootstrap/crds/kustomization.yaml -- add them to it" > "/dev/stderr"
        exit 1
      }
      if (!crd) {
        print "the built bundle contains no CustomResourceDefinitions at all -- refusing a vacuous pass" > "/dev/stderr"
        exit 1
      }
    }'
}

self_test() {
  if printf 'kind: CustomResourceDefinition\nkind: NetworkPolicy\n' | check 2>/dev/null; then
    echo "self-test failed: an escaped non-CRD kind was not caught" >&2
    exit 1
  fi
  if printf '' | check 2>/dev/null; then
    echo "self-test failed: an empty build was not rejected" >&2
    exit 1
  fi
  if ! printf 'kind: CustomResourceDefinition\n' | check; then
    echo "self-test failed: a CRD-only stream was rejected" >&2
    exit 1
  fi
  echo "self-test: ok"
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit 0
fi

# kubectl's embedded kustomize is what the bootstrap apply itself uses (kubectl apply -k), so
# verify the same build the operator would apply.
kubectl kustomize "${CRDS_DIR}" | check
echo "bootstrap CRD bundle: only CustomResourceDefinitions survive the filter"
