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
#
# Output goes to a file, not the test log -- the bootstrap-crds.yaml StepTemplate's `catch`
# prints it, so it only surfaces on failure. Keyed on $NAMESPACE (injected by chainsaw, unique
# per test) so sequential suites in the same environment never collide on the path.
LOG_FILE="${TMPDIR:-/tmp}/bootstrap-crds-apply-${NAMESPACE}.log"

# Every one of the ten bundles under infrastructure/bootstrap/crds/ names a CRD manifest by URL,
# so this one command performs ten network fetches with no retry of its own. Measured over the 13
# days to 2026-09-12, a failure here took out three suites in a single dispatch -- three of the
# fleet's eight failures in the window, the largest single contributor.
#
# kustomize also reports the failure misleadingly: when an HTTP fetch fails it falls back to
# treating the URL as a git repository, and the error that finally surfaces says a LOCAL directory
# "must resolve to a file". So a network blip reads as a broken path in this repo, and the
# investigation starts in the wrong place. That is why the note below exists.
#
# This is not the "auto-retry failed jobs" approach that was considered and rejected for this
# fleet, and the difference is the point rather than a nicety. Retrying a job re-runs the
# assertions, so it masks exactly the flakiness the instrumentation exists to surface. There are no
# assertions here: the fetched artifacts are immutable, pinned by version, and byte-identical on
# every attempt, so a second attempt cannot turn a real failure green. It can only recover a
# dropped connection. A genuinely unreachable or removed release asset still fails, having cost 20
# extra seconds.
#
# Server-side apply is declarative, so a partially-applied first attempt converges on the second.
attempts=3
for attempt in $(seq 1 "${attempts}"); do
  if kubectl apply --server-side --force-conflicts -k "${CRDS_DIR}" >>"${LOG_FILE}" 2>&1; then
    break
  fi

  if [[ "${attempt}" -eq "${attempts}" ]]; then
    {
      echo
      echo "apply-bootstrap-crds: failed ${attempts} times."
      echo "Before looking for a path problem in this repo, check the remote fetches -- kustomize"
      echo "reports a failed download as a local path error. The bundles fetch these:"
      # Only `resources:` entries from the bundles' own kustomization.yaml files. Matching any
      # https:// under this tree instead returns ~170 lines, most of them issue links in comments.
      grep -rhE '^[[:space:]]*-[[:space:]]+https://' --include=kustomization.yaml "${CRDS_DIR}" \
        2>/dev/null | sed -E 's/^[[:space:]]*-[[:space:]]+/  /' | sort -u
    } >>"${LOG_FILE}"
    exit 1
  fi

  echo "apply-bootstrap-crds: attempt ${attempt} failed, retrying" >>"${LOG_FILE}"
  sleep $(( attempt * 5 ))
done
