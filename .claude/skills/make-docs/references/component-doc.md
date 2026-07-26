# Component Documentation — structure

Purpose: document one cross-cutting **Kustomize component** — what it patches/adds when layered onto a module, and what a consumer must provide for it to work.
Path: `components/<name>/README.md`.
Sources: the component's `kustomization.yaml` and **every** resource and patch file it references — the objects it creates, the strategic/JSON6902 patches it applies — read them completely before writing. You may **also** read the module or resource the component is layered onto when the consumption contract isn't in the component's own files (e.g. how a generated ConfigMap/Secret reaches the target HelmRelease, by what name/key) — that's the same rationale as reading a referenced HelmRelease, not a level violation, and for a component whose whole job is to feed another module it's often the only place the key integration point lives. `DESIGN.md` gives context on the components pattern; the worked examples carry no explicit concept link, so none is required.

A component is unlike a module: it deploys nothing on its own. It is applied via a consuming Flux `Kustomization`'s `spec.components` **on top of** a module, and it works by **patching** that module's resources and/or **adding** its own. So the doc is framed around "what this does to the thing it's layered onto", not "what this runs". There is no Quick Links / logo section (a component isn't an app) and no module-style Dependencies section — its coupling is expressed as Prerequisites the consumer must satisfy.

**Flat vs variant layout.** Some components are a single flat directory with a top-level `kustomization.yaml` (e.g. `db-backups`, `sso`); others are a parent directory of mutually-exclusive **variant** subdirectories, each its own deployable component with no top-level kustomization (e.g. `external-dns-provider/{pihole,unifi}`, `oidc-credentials/{coder,grafana,…}`, `cert-issuer/letsencrypt`). Either way the README lives at the component's **top directory** (`components/<name>/README.md`) — that's where a consumer looks. For a variant component, read every variant's files, introduce the variants up front (what each is and when to pick it — a short list or small table), and where Resources or Prerequisites genuinely differ per variant carry a variant dimension (a `Variant` column, or brief per-variant sub-tables) rather than duplicating the whole doc for near-identical variants.

Read the existing `components/db-backups/README.md` and `components/db-restore/README.md` as worked examples; they are the reference shape. Sections appear in this order.

## 1. Introduction

- **Format:** a single short paragraph.
- **Include:** what the component does, that it is applied as a Kustomize component on top of a module, and what kind of module it expects (e.g. "a module that defines a CloudNativePG `Cluster`"). State the value it adds without the consuming module needing to know the details.
- **Exclude:** implementation specifics, configuration values, version numbers.

## 2. Overview

- **Format:** one line in, then numbered capability groups with bullets (same shape as a module Overview).
- **Include:** the 2–4 capability groups the component provides, each with a few concrete bullets grounded in what it actually creates/patches.
- **Exclude:** configuration values, deployment instructions, version detail.

## 3. How It Works

- **Format:** a short prose paragraph, then a Mermaid flowchart following **mermaid.md**.
- **Include:** the mechanism — which resources it **patches** on the target module and which it **creates**, and how those interact at runtime (what reads what, what triggers what, where data flows). The diagram should make the "layered onto an existing resource" relationship legible. A component defines its own diagram colour categories (following **mermaid.md**'s principles); it is not bound to the infra/apps `classDef`s.
- **Exclude:** implementation minutiae, values that belong in the manifests.

## 4. Resources

- **Format:** a table listing the Kubernetes objects the component manages — a component's counterpart to a module's service table, since it manages resources rather than running services.
- **Columns:** `Resource` · `Kind` · `Purpose`. Give the API group where the kind has one (e.g. `ObjectStore` (barmancloud.cnpg.io)); for a core kind or a generator-produced object, note that instead (e.g. `ConfigMap` (core, via `configMapGenerator`)).
- **Include:** every object the component creates. For a resource it **patches** rather than creates, use `(patch)` in the Resource column and name the target Kind — describe what the patch changes.
- **Exclude:** full manifests, field-by-field configuration.

## 5. Prerequisites

- **Format:** numbered subsections, each a table. Include only the subsections that apply.
- **Subsections and their columns (match what the examples use):**
  - Required Variables — `Variable` · `Purpose` · `Example`.
  - Required Secret Store Keys (if it reads from a secret store) — `Key` · `Purpose`.
  - Required Infrastructure — `Component` · `Purpose` · `Provided By` — the operators/CRDs/infra modules and external systems the component needs (this is where its real coupling is expressed). "Component" here means an upstream capability/module it depends on, not the component being documented.
  - Required Companions (if it must be applied alongside another component) — `Component` · `Purpose` · `Provided By`, linking the companion component.
- **Include:** only what the implementation actually requires; every entry traces to a file you read.
- **Exclude:** default values, sensitive information.

## 6. Notes

- **When to include:** the component has important caveats, ordering constraints, or non-obvious behavior.
- **Format:** bullet points.
- **Include:** gotchas a maintainer would otherwise rediscover the hard way (immutability constraints that force a create-not-mutate, must-be-applied-with-X pairing, path/naming scoping). Link related components with a relative link.
- **Exclude:** troubleshooting steps, operational procedures.
