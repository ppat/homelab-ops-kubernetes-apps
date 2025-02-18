# Product Context

## Project Overview

This repository provides reusable Kubernetes modules for GitOps-based deployment. Each module is a self-contained unit that can be composed to build complete cluster configurations.

### Key Capabilities

- Infrastructure modules for core cluster services
- Application modules for end-user functionality
- Component modules for cross-cutting concerns
- GitOps-based deployment via FluxCD
- Comprehensive testing framework
- Automated version management

## Module Types

### Infrastructure Modules

- Provide foundational cluster capabilities
- Focus on platform services and operations
- Follow core/extra pattern for dependencies
- Examples: networking, storage, security

### Application Modules

- Deliver end-user functionality
- Depend on infrastructure capabilities
- More focused in scope
- Examples: media servers, home automation

### Component Modules

- Provide cross-cutting configuration
- Apply consistent patterns across modules
- Examples: SSO integration, backup configuration

## Design Principles

### 1. Module Independence

- Self-contained functionality
- Clear boundaries
- Explicit dependencies
- Environment-agnostic design

### 2. Configuration Flexibility

- Multiple configuration methods
- Environment-specific settings
- Component-based customization
- Patch-based modifications

### 3. Dependency Management

- Explicit hard dependencies
- Implicit soft dependencies
- Dependency cycle prevention
- Core/Extra pattern usage

### 4. Testing Integrity

- Module-level testing
- Complete dependency validation
- Resource state verification

### 5. Operational Clarity

- Clear module categorization
- Consistent naming patterns
- Change tracking
- Version update automation

## Short-term Roadmap

1. Testing Framework Migration
   - Move from GitHub Actions to kyverno/chainsaw
   - Enable local testing capabilities
   - Improve test structure and validation

2. Infrastructure Evolution
   - Migration to cillium for CNI and load balancing
   - Implementation of default alerts
   - Development of backup strategy
   - Security controls through kyverno

## Long-term Vision

### 1. Infrastructure Maturity

- Comprehensive monitoring and alerting
- Advanced security controls
- Automated operations
- Resilient storage solutions

### 2. Application Portfolio

- Expanded application support
- Enhanced integration capabilities
- Improved user experience
- Broader use case coverage

### 3. Component Framework

- Extended configuration patterns
- Enhanced reusability
- Simplified integration
- Better customization options

## Success Metrics

### 1. Deployment Success

- Module deployment success rates
- Error rates and types
- Recovery time metrics
- Version upgrade success

### 2. Operational Efficiency

- Resource utilization
- Performance metrics
- Maintenance overhead
- Update frequency

### 3. User Experience

- Deployment time
- Configuration complexity
- Issue resolution time
- User satisfaction
