# Active Context

## Current State

- Repository providing reusable Kubernetes modules for GitOps-based deployment
- Modules designed for consumption by separate cluster configuration repositories
- Well-established module types (Infrastructure, Application, Component)
- Core/extra pattern implemented across multiple infrastructure modules
- Testing currently implemented through GitHub Actions workflows

## Active Initiatives

- Testing framework migration from GitHub Actions to kyverno/chainsaw
  - PoC completed successfully with kubernetes-core/extra modules
  - Learnings and design decisions documented in `.analysis/chainsaw-poc.md`
  - Remaining modules to be migrated (2 at a time, core/extra in tandem)

## Backlog Items

- Migration from flannel + metallb to cillium for CNI and load balancing
- Implementation of sensible default alerts across modules
- Development of comprehensive backup strategy
- Future security controls through kyverno

## Key Metrics

- Module deployment success rates
- Test coverage and validation metrics
- Documentation completeness
- Module reusability across clusters

## Current Focus Areas

1. Testing Framework Migration
   - Moving from GitHub Actions workflows to kyverno/chainsaw
   - PoC completed with kubernetes-core/extra modules
   - Migrating remaining modules (2 at a time, core/extra modules in tandem)
   - Enable local testing capabilities
   - Improve test structure and validation
   - Enhance kubernetes context awareness

## Recent Changes

- Successful PoC completion for kyverno/chainsaw migration with kubernetes-core/extra modules
- Documentation of chainsaw migration learnings and design decisions
- Documentation completion across infrastructure and application modules
- Core/extra pattern implementation across various modules
- Comprehensive storage solutions (block, object, NFS)
- Module structure standardization
