# Documentation Content Guide

This guide defines required document structure, content and format for three documentation types. Each type has specific requirements optimized for clarity and completeness at the level of abstraction or granularity needed for that type of documentation.

> **NOTE**: For documentation process, see [Documentation Process Guide](./documentation-process-guide.md).

## Individual Module Documentation

Purpose: Document a specific module's capabilities and boundaries.

1. Introduction
   Format: Single sentence or paragraph (based on complexity)
   Required Content:
   - What capabilities the module provides to the system
   Content Constraints:
   - NO implementation details
   - NO configuration specifics
   - NO version numbers
   - Focus on role and capabilities

2. Quick Links
   Format: Bulleted list with markdown links and descriptions
   Required Content:
   - Link to official product/project documentation
   - Link to source code repository (e.g., GitHub)
   Content Constraints:
   - NO links to files within this repository
   - NO links to specific software versions
   - NO links to temporary or unstable URLs

3. Overview
   Format: Single paragraph followed by capability groups
   Required Content:
   - Module purpose and primary function
   - 3-4 main capability groups
   - 4-5 key features listed under each group
   Content Constraints:
   - NO specific configuration values or environment variables
   - NO deployment or installation instructions
   - NO version numbers or release details

4. Component Architecture (Optional)
   When to include:
   - Module has multiple interacting components with non-trivial relationships
   Format: Mermaid flowchart (following the Mermaid Diagram Best Practices detailed separately in this doc)
   Required Content:
   - Component relationship diagram
   - Color scheme definitions
   - Component grouping
   - Data/control flow arrows
   Content Constraints:
   - NO implementation details
   - NO configuration specifics
   - NO deployment topology

5. Component Details
   Format: Table with defined columns
   Required Content:
   - Component name
   - Primary role/purpose
   - Key features (bullet points)
   - Integration points (bullet points)
   Content Constraints:
   - NO configuration parameters
   - NO command-line examples
   - NO internal implementation details

6. Prerequisites
   Format: Numbered sections with tables
   Required Content:
   - Required flux post build variables (table: name, purpose, used by)
   - Required secrets and configmaps (table: name, purpose, keys)
   - Storage requirements if any (table: PVC name, purpose, access mode)
   - RBAC requirements if any (table: resource, access, purpose)
   Content Constraints:
   - MUST be based on actual implementation
   - NO default values
   - NO sensitive information
   - NO implementation-specific details

7. Dependencies
   When to include:
   - Required for Infrastructure Modules, skip for Apps modules
   Format: Two sections with bullet points
   Required Content:
   - Required by: List of modules that depend on this module
   - Depends on: List of modules this module requires
   Content Constraints:
   - NO indirect dependencies
   - NO app module dependencies
   - NO external system dependencies

8. Future Improvements
   Format: Bulleted lists under categories
   Required Content:
   - Planned feature enhancements
   - Known current limitations
   - Potential integration opportunities
   Content Constraints:
   - NO specific implementation plans
   - NO timeline commitments
   - NO version numbers

9. Notes
   When to include: Module has important caveats or special considerations
   Format: Paragraphs with bullet points
   Required Content:
   - Important caveats or limitations
   - Special configuration considerations
   - Architecture decisions affecting usage
   Content Constraints:
   - NO troubleshooting steps
   - NO configuration examples
   - NO operational procedures

## Module Type Documentation

Purpose: Document capabilities and patterns across a collection of related modules

1. Introduction
   Format: Single concise paragraph
   Required Content:
   - Module type's purpose ("provides foundational capabilities" / "provide end-user functionality")
   - Relationship to other modules
   - Value proposition
   - Key distinguishing characteristics
   Content Constraints:
   - NO implementation details
   - NO configuration specifics
   - NO individual module features
   - NO multiple paragraphs
   - YES to capability patterns
   - YES to relationship statements
   - YES to value statements

2. Functional Areas & Capabilities
   Format: Three-column table

   ```markdown
   | Category | Functional Areas | Module Capabilities |
   |----------|-----------------|-------------------|
   | Security | Area 1<br/>Area 2 | [module-name](./path):<br/>• Capability 1<br/>• Capability 2 |
   ```

   Required Content:
   - Categories group related modules
   - Functional area descriptions
   - Module capabilities with links
   - Bullet points for specific capabilities
   Content Constraints:
   - NO implementation details
   - NO configuration specifics
   - NO version numbers
   - Maximum 3-4 capabilities per module
   - Use bullet character • for capabilities

3. Module Relationships
   Format: Mermaid flowchart with consistent styling
   Required Content:
   - Module dependency diagram
   - Color scheme definitions
   - Logical node grouping
   - Clear dependency lines
   Content Constraints:
   - NO crossed dependency lines
   - NO implementation details
   - Infrastructure: Show core/extra pattern
   - Applications: Show infrastructure dependencies

4. Configuration
   Format: Single paragraph with link
   Required Content:
   - Link to projectBrief.md#configuration-methods
   - Brief mention of available methods
   Content Constraints:
   - NO configuration details
   - NO implementation specifics
   - NO duplication of configuration docs

## Repository Root Documentation

Purpose: Provide entry point and high-level understanding of the entire project

1. What This Project Provides
   Format: Two bullet-point groups
   Required Content:
   - Infrastructure capabilities (5-6 bullets)
   - End-user applications (5-6 bullets)
   - Action verbs (Deploy, Manage, Configure)
   - Complete the phrase "This platform enables you to..."
   Content Constraints:
   - NO version numbers
   - NO implementation details
   - NO configuration specifics
   - Focus on end-user value

2. Project Structure & Concepts
   Format: Class diagram and comparison table
   Required Content:
   - Class diagram showing module hierarchy
   - Table comparing module types
   - Links to module directories
   - 3-4 key characteristics per type
   Content Constraints:
   - NO implementation details
   - NO configuration specifics
   - Keep characteristics high-level
   - Focus on type differences

3. Finding Your Way
   Format: Five-column table
   Required Content:
   - Columns: Category, Need, Location, Content, Examples
   - Groups: Understanding, Usage, Configuration
   - Links to actual content
   - Concrete examples
   Content Constraints:
   - Maximum 3-4 rows per category
   - Keep examples specific
   - Focus on common tasks
   - Maintain consistent structure

## Content Requirements

### 1. Must Include

1. Verified implementation requirements
2. Actual component relationships
3. Real integration points
4. Required configurations
5. System boundaries

### 2. Should Include

1. High-level architecture
2. Capability groupings
3. Feature sets
4. Future improvements
5. Known limitations

### 3. Must Not Include

1. Generic configurations
2. Non-required settings
3. Marketing content
4. Implementation details
5. Operational procedures

## Mermaid Diagram Best Practices

For all diagrams in any documentation type:

- Placement of items within the diagram must create a clear, simple, singular directional flow
- Minimize overlap and/or crossing between arrows (whenever possible)
- Properly categorize items using similar colors for the same types of items
- Follow color selection best practices to ensure they work in both dark and light backgrounds
- Use consistent styling within each diagram type:

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
