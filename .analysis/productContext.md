# Product Context

## Project Overview

This repository provides a collection of reusable Kubernetes modules that can be composed to build complete cluster configurations. These modules are consumed by separate cluster configuration repositories where environment-specific settings are applied. The project enables consistent, maintainable, and automated infrastructure deployment through GitOps principles.

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
