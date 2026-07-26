# Development Workflow

How changes flow through this repository — from a code change or an automated
dependency bump, through validation, to an independently versioned release.
The design concepts these workflows operate on (modules, the core/extra pattern,
dependencies) are described in [DESIGN.md](./DESIGN.md); the module test flow
that gates every change is detailed in [TESTING.md](./TESTING.md); the exact
lint/validate commands are in [CLAUDE.md](./CLAUDE.md#commands).

## Quality Controls

```mermaid
flowchart LR
    A[Code Change] --> B[Local Validation]
    B --> C[PR Validation]
    C --> D[Module Tests]
    D --> M[Land on Main]

    subgraph local [Local Checks]
        direction TB
        L1[Pre-commit Hooks]
    end

    subgraph static [Static Analysis]
        direction TB
        subgraph resource [Resource Validation]
            R1[Kubeconform]
        end

        subgraph workflow [Workflow Validation]
            W1[GitHub Actions]
        end

        subgraph config [Config Validation]
            C1[Renovate Config]
        end

        subgraph syntax [Syntax & Style]
            S1[YAML Lint]
            S2[ShellCheck]
            S3[Commit Messages]
        end
    end

    B --> L1
    C --> resource
    C --> workflow
    C --> config
    C --> syntax
    static --> M

    note[Release process handled separately
    via release-please]
```

## Version Management

```mermaid
flowchart TB
    subgraph updates [Version Updates]
        direction LR
        R[Renovate Bot] --> PR1[Version Upgrade PR]
        DEV[Developer] --> PR2[Feature PR]
    end

    subgraph validation [Validation]
        direction LR
        T1[Module Tests]
        T2[Pre-commit Checks]
        T3[CI Validation]
    end

    subgraph release [Release Process]
        direction LR
        RP[Release-please PR]
        RM[Land Release PR]
        CL[Changelog Update]
        TAG[Git Tag]
    end

    PR1 --> T3
    PR2 --> T2 --> T3 --> T1

    T1 --> |Tests Pass| PRTYPE{Feature or Version Upgrade?}
    PRTYPE --> |Version Upgrade| AM{Auto-merge?}
    PRTYPE --> |Feature| M[Merge]
    AM --> |Patch/Minor| M
    AM --> |Major| HR[Human Review] --> M

    M --> RP --> RM
    RM --> CL --> TAG

```

### Automated Updates

- Renovate bot manages version updates for applications
- Automated merging rules:
  - Patch versions: Auto-merge if tests pass
  - Minor versions: Auto-merge if tests pass (with exceptions for critical infrastructure)
  - Major versions: Require human approval

### Release Process

Each module is versioned and released independently.

1. Changes land in main branch (via Renovate or manual PRs)
2. Release-please creates release PR with:
   - Version bump
   - Changelog updates
3. When release PR merges:
   - CHANGELOG.md is updated
   - Module gets versioned (git tag)

## Maintenance Practices

1. Module Archival
   - Unused modules moved to `.archive`
   - Preserves historical context
   - Maintains deployment history

2. Repository Organization
   - Helm repositories split by purpose (infra vs apps)
   - Clear module categorization
   - Consistent structure

3. Documentation
   - CHANGELOG.md per module
