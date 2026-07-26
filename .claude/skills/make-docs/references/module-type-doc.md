# Module Type Documentation — structure

Purpose: document the capabilities and patterns across a collection of related modules.
Path: `apps/README.md` or `infrastructure/README.md`.
Sources: **only** the module `README.md` files under that tree (`apps/subsystems/*/README.md` or `infrastructure/subsystems/*/README.md`), plus `DESIGN.md` for context. Do **not** open implementation files — this doc summarizes the module docs, it doesn't re-derive them. Which means the module READMEs must be correct first (see the bottom-up rule in SKILL.md).

Sections appear in this order.

## 1. Introduction

- **Format:** a single concise paragraph — not multiple paragraphs.
- **Include:** the module type's purpose (e.g. "provides foundational capabilities" / "provide end-user functionality"), its relationship to other modules, its value proposition, and its key distinguishing characteristics.
- **Exclude:** implementation details, configuration specifics, individual module features. Yes to capability patterns, relationship statements, and value statements; no to per-module minutiae.

## 2. Functional Areas & Capabilities

- **Format:** a three-column table.

  ```markdown
  | Category | Functional Areas | Module Capabilities |
  |----------|-----------------|-------------------|
  | Security | Area 1<br/>Area 2 | [module-name](./path):<br/>• Capability 1<br/>• Capability 2 |
  ```

- **Include:** categories that group related modules; functional-area descriptions; module capabilities with links to each module; bullet points for specific capabilities.
- **Constraints:** no implementation details, no configuration specifics, no version numbers; **maximum 3–4 capabilities per module**; use the `•` bullet character for capabilities.

## 3. Module Relationships

- **Format:** a Mermaid flowchart with consistent styling — follow **mermaid.md**.
- **Include:** the module dependency diagram, color-scheme definitions, logical node grouping, clear dependency lines.
- **Constraints:** no crossed dependency lines, no implementation details. For **infrastructure**, show the core/extra pattern; for **applications**, show the infrastructure dependencies.

## 4. Configuration

- **Format:** a single short paragraph with a link.
- **Include:** a link to `DESIGN.md#configuration-methods` and a brief mention of the available methods.
- **Exclude:** configuration details or implementation specifics — do not duplicate what the configuration docs already cover; point to them.
