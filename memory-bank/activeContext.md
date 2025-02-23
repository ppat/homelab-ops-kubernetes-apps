# Active Context

## Current State

- Repository providing reusable Kubernetes modules for GitOps-based deployment
- Modules designed for consumption by separate cluster configuration repositories
- Well-established module types (Infrastructure, Application, Component)
- Core/extra pattern implemented across multiple infrastructure modules
- Testing currently implemented through GitHub Actions workflows

## Active Initiatives

- Testing framework migration from GitHub Actions to kyverno/chainsaw

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
   - Enable local testing capabilities
   - Improve test structure and validation
   - Enhance kubernetes context awareness

## Recent Changes

- Documentation completion across infrastructure and application modules
- Core/extra pattern implementation across various modules
- Comprehensive storage solutions (block, object, NFS)
- Module structure standardization
- Initial testing framework setup
