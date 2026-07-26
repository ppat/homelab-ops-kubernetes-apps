# Mermaid Diagram Best Practices

Applies to every Mermaid diagram in any of the three doc types. The goal is a diagram that reads clearly at a glance and renders legibly in both light and dark themes — consistency across the repo matters as much as any single diagram.

## Layout and flow

- Place nodes so the diagram has a single, clear directional flow — don't make the reader trace a tangle.
- Minimize arrow overlap and crossings wherever possible.
- Group related items and give same-type items the same color.

## Color

- Choose colors that work on both dark and light backgrounds (the styles below are picked for this — reuse them rather than inventing new fills).
- Categorize by color: one `classDef` per type of thing, applied consistently.

## Consistent styles per diagram type

Use these `classDef` conventions so infrastructure and application diagrams stay visually consistent across the repo:

```mermaid
%% Infrastructure Style
flowchart BT
    classDef core fill:#86efac,stroke:#059669,color:#064e3b
    classDef extra fill:#fca5a5,stroke:#dc2626,color:#7f1d1d

%% Application Style
flowchart BT
    classDef infra fill:#e2e8f0,stroke:#64748b,color:#475569
    classDef apps fill:#93c5fd,stroke:#2563eb,color:#1e3a8a
```

- **Infrastructure** diagrams (module-type `infrastructure/README.md`, and infra module docs): distinguish **core** vs **extra** with the classes above, and show the core/extra pattern.
- **Application** diagrams (module-type `apps/README.md`, and app module docs): distinguish **infra** dependencies from **apps** with the classes above, and show the infrastructure dependencies.
- Individual module **Service Architecture** diagrams, and component **How It Works** diagrams, may define their own `classDef`s for their own categories (services, database, storage, client; or for a component, the target resource vs. added resources vs. external store) — they are not bound to the infra/apps classes above. Keep the same principles: one color per category, contrast-safe, consistent within the diagram, and a small legend so the colors are self-explanatory.
