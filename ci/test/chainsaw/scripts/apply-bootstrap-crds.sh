#!/usr/bin/env bash
#
# Applies infrastructure/bootstrap/crds/ ONCE, which is what a real cluster does.
#
# Until #3678 was diagnosed, every suite instead listed the bundle as a resource of its
# `pre-requisites` Flux Kustomization. That is the bug, and it is worth stating why rather than
# just fixing it, because the wrong version looked entirely reasonable.
#
# DESIGN.md ("CRD Management") makes the bootstrap bundle a MANUAL, ONE-TIME apply, engaged only
# at first-time cluster setup and disaster recovery, with CRD *updates* thereafter owned by the
# helm charts inside the modules. Nothing in the clusters repo references `bootstrap/crds` at
# all -- production has no Flux Kustomization for it. The suites did the opposite: `pre-requisites`
# reconciles every 60s with `prune: false`, so the pinned bundle's copy of a CRD was force-applied
# over whatever the module's chart had installed, once a minute, for the whole run.
#
# That matters because the two copies routinely disagree. The bundle tracks upstream GitHub
# releases and the chart tracks its own chart version -- two independent Renovate datasources
# that cannot move in one PR -- so every module upgrade opens a window where they differ.
#
# And replacing a CRD closes the API server's open watch connections for that resource. The
# operator does not re-establish them, so no events for those objects reach its work queue and it
# never runs a reconcile for them again -- while the process itself stays healthy, holding its
# leader election lease, answering its admission webhooks, and logging NOTHING.
#
# That is #3678 exactly: empty `Status`, `Events: <none>`, no instance pod, operator `1/1 Running`
# with zero restarts. It was reproduced on demand this way, and restoring the CRD makes the same
# object reconcile within seconds.
#
# So this is not a workaround for a CI quirk. Applying once IS the production behaviour, and the
# divergence from it was the defect -- which also means the suites now exercise the real shape.
set -euo pipefail

# chainsaw runs `script` operations with cwd set to the test directory (`ci/test/<suite>/`),
# verified on v0.2.15, and identically so when invoked from a StepTemplate -- which is why the
# sibling scripts here are reached as `../chainsaw/scripts/...`. Three levels up is the repo root.
CRDS_DIR="${1:-../../../infrastructure/bootstrap/crds/}"

if [[ ! -d "${CRDS_DIR}" ]]; then
  echo "apply-bootstrap-crds: ${CRDS_DIR} not found (cwd: $(pwd))" >&2
  exit 1
fi

# --server-side is required, not stylistic. A client-side apply stores the entire object in the
# `last-applied-configuration` annotation, and these bundles are far past the 262144-byte
# annotation ceiling -- the CloudNativePG bundle alone is ~32k lines.
#
# --force-conflicts because this step is emulating the bootstrap that precedes everything else,
# so it must win outright rather than fail on a field another manager already owns.
kubectl apply --server-side --force-conflicts -k "${CRDS_DIR}"
