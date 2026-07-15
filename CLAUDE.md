# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Ignore `.prompts/`, `.analysis/`, and `.archive/` — these are not part of the deployable repo.

## Start here

- [README.md](./README.md) — module catalog (what's deployed, by category) and "Finding Your Way" table
- [projectBrief.md](./projectBrief.md) — architecture: module types, core/extra pattern, dependency rules, configuration methods, testing/release pipeline
- `.guides/` — documentation authoring guides (structure/content rules per doc type, and the review process for writing them). Only relevant when creating or updating a README.md/projectBrief.md in this repo; otherwise ignore.
- Every subsystem under `infrastructure/subsystems/*/README.md` and `apps/subsystems/*/README.md` has module-specific details: components, prerequisites, required secrets/variables, and its own Dependencies section (Required By / Depends On). Read the relevant one before touching a module.

This is a GitOps repo (FluxCD) of Kustomize/Helm manifests — there is no application code to build. "Development" here means authoring/editing YAML and validating it.

## Repository layout

- `infrastructure/subsystems/` — platform capabilities, split `*-core` / `*-extra` (extra depends on other cores to break cycles). See [infrastructure/README.md](./infrastructure/README.md).
- `apps/subsystems/` — end-user applications, depend on infrastructure. See [apps/README.md](./apps/README.md).
- `components/` — cross-cutting Kustomize components (`sso`, `db-backups`, `db-restore`, `cert-issuer`, `oidc-credentials`, `external-dns-provider`) applied on top of other modules via `spec.components` in a Flux Kustomization.
- `infrastructure/bootstrap/crds/` — CRDs needed only for first-time cluster bootstrap / disaster recovery (so dependent modules can reference custom resources before the module that normally installs those CRDs is deployed).
- `ci/test/<module>/` — chainsaw test suites per module (pre-requisites, the module manifest under test, validation assertions).
- `ci/test/chainsaw/` — shared chainsaw config, reusable steps (`bootstrap-flux.yaml`, `bootstrap-prerequisites.yaml`), reusable assertions (`*-ready.yaml`), and `scripts/flux-reconcile.sh`.
- `ci/validation/` — base kustomization + `.env` of dummy post-build substitution variables used by kubeconform validation.

Every module directory (infra/app/component) follows the same shape: `kustomization.yaml`, `namespace.yaml`, `CHANGELOG.md`, one subdirectory per component with its own `kustomization.yaml` + `helm-release-*.yaml` / `helm-repository-*.yaml`.

## How modules are actually consumed (cross-repo)

This repo only contains modules — it has no cluster definitions. Modules are packaged, versioned, and released independently (one release-please component per module path). They're consumed by the sibling `homelab-ops-kubernetes-clusters` repo, checked out alongside this one (`../homelab-ops-kubernetes-clusters`), which defines the actual clusters (`clusters/<cluster-name>/`).

For each module a cluster wants, that repo defines:

- A Flux `GitRepository` (in `clusters/<cluster>/sources/`) pinned to a specific released tag of this repo, e.g. `ref.tag: infra-security-core-v0.2.6`, with `spec.ignore` scoped to just that module's directory (plus `/components`).
- A Flux `Kustomization` (in `clusters/<cluster>/kustomizations/`) with `spec.path` pointing at the module directory in this repo (e.g. `./infrastructure/subsystems/security-core`) that:
  - mixes in one or more `components/*` via `spec.components` (e.g. `sso`, `cert-issuer/letsencrypt`, `oidc-credentials/openwebui`) — this is where component modules actually get wired into a module at deploy time
  - configures the module via `spec.postBuild.substitute`/`substituteFrom` (inline values or from a ConfigMap/Secret, e.g. `cluster-secrets`) for Flux post-build variables
  - and/or customizes it via `spec.patches` (JSON6902/strategic patches), e.g. deleting a `HelmRelease` the cluster doesn't want
  - declares hard dependencies on other modules via `spec.dependsOn`

The same module can be referenced by multiple clusters at different versions with different components/patches/variables — that's how one module serves many clusters. When changing a module here, check `../homelab-ops-kubernetes-clusters/clusters/*/kustomizations/` (if available) to see how it's actually being consumed before assuming a change is backwards-compatible.

## Architecture essentials (details in projectBrief.md)

- **Module types**: Infrastructure (platform capabilities) / Application (end-user) / Component (cross-cutting Kustomize patches). See [projectBrief.md#module-types-and-organization](./projectBrief.md#module-types-and-organization).
- **Core/Extra pattern**: used to break circular dependencies between subsystems — deploy order is `X-core → Y → X-extra`. See [projectBrief.md#core-vs-extra-pattern](./projectBrief.md#core-vs-extra-pattern).
- **Dependencies**: hard dependencies are declared only at the point of use via Flux `Kustomization.spec.dependsOn` (never inside the module itself); soft dependencies rely on eventual consistency and are monitored via `ServiceMonitor`/`PrometheusRule`. See [projectBrief.md#dependencies](./projectBrief.md#dependencies) and each module's own README `## Dependencies` section for its specific Required By / Depends On.
- **Configuration**: three mechanisms — Kustomize patches (module-specific), Flux post-build substitution variables (cluster-wide settings), Kustomize component overlays (cross-cutting, e.g. `components/sso`). See [projectBrief.md#configuration](./projectBrief.md#configuration).
- **Module independence**: cluster/environment-specific details (secret store name, storage class, etc.) are never hardcoded in a module — they're injected externally so the same module works across clusters/environments.

## Commands

### Lint / validate (mirrors `.pre-commit-config.yaml` and `.github/workflows/lint.yaml`)

```bash
pre-commit run --all-files      # yamllint, markdownlint, shellcheck, commitlint, etc.
```

Individual checks can be run standalone if needed: `yamllint --strict <path>`, `markdownlint-cli2 --fix --config .markdownlint-cli2.yaml <path>`, `shellcheck <script>`.

Kubernetes manifest validation (kubeconform via the `validate-kubernetes-manifests` pre-commit hook) uses `ci/validation/kustomization.yaml` as the base kustomization and `ci/validation/.env` for dummy post-build substitution values, restricted to `apps/*` and `infrastructure/*` (excludes `components/*` and `.archive/*` since components aren't standalone kustomizations).

### Module tests (chainsaw + kind)

Each module is tested as a full unit in CI, even for single-component changes — see [projectBrief.md#testing-and-validation](./projectBrief.md#testing-and-validation) for the full flow (kind cluster → install Flux → deploy hard deps → apply module → validate resources).

To run a module's suite locally:

```bash
kind create cluster --config .github/kind-cluster-single-node.yaml
chainsaw test ./ci/test/<module-dir> --config ./ci/test/chainsaw/.chainsaw.yaml
```

`<module-dir>` matches the CI workflow names, e.g. `apps-ai`, `apps-coder`, `infra-security`, `infra-database`. Each corresponds 1:1 with a `.github/workflows/test-*.yaml` file — check that workflow to see the exact `chainsaw_config`/`kind_config` inputs used in CI.

Test suite layout per module (see `ci/test/apps-ai/` as reference): `pre-requisites/` (namespaces, fake secret stores, PVCs needed before the module can deploy), the module's Flux `Kustomization` manifest, `validate-*.yaml` chainsaw assertions. Shared bootstrap steps and readiness assertions live in `ci/test/chainsaw/` — reuse those (`assertions/*-ready.yaml`) rather than writing new ones.

## Commit conventions

Conventional Commits, enforced by commitlint (`commitlint.config.js`):

- header max 120 chars; scope must be one of the enums in `commitlint.config.js` (`apps-*`, `infra-*`, `component-*`, or `renovate`/`release`/`github-actions`/`kubernetes-api`/`dev-tools`)
- scope generally matches the module directory name, e.g. a change under `apps/subsystems/ai/` uses scope `apps-ai`

## Releases

Each module is released and versioned independently via release-please (`release-please-config.json` maps module paths → component names). Version bumps and `CHANGELOG.md` updates happen automatically when a release PR is merged — don't hand-edit `CHANGELOG.md` files.

## Dependency updates

Renovate manages version bumps for Helm charts/images across modules (config split across `.github/renovate.json` + `.github/renovate/*.json`). Patch/minor auto-merge if tests pass; major versions require human review.
