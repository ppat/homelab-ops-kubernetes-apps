# Documentation Process Guide

This guide defines the process and approach for creating or updating documentation. It provides critical instructions for LLMs to ensure accurate and complete documentation.

> **NOTE**: For documentation structure and content requirements, see [Documentation Content Guide](./documentation-content-guide.md).

## Critical Rules

### 1. NO Documentation Without Complete Review of Applicable Sources

**Rule**: MUST review ALL applicable source files before starting documentation. Source files vary by documentation type:

Individual Module Documentation:

- Start with kustomization.yaml to find implementation files
- Review ALL implementation files found
- Extract configurations and requirements
- Document relationships and dependencies

Module Type Documentation:

- Review ALL module README.md files
- Review projectBrief.md for context
- NO implementation file review
- Focus on patterns and relationships

Repository Root Documentation:

- Start with projectBrief.md
- Review module type documentation
- NO individual module details
- NO implementation files

**Why**: LLMs tend to:

- Start writing without complete context
- Mix abstraction levels inappropriately
- Look at wrong files for context
- Include inappropriate details
- Make assumptions about content
- Lose track of documentation purpose

**Verify**:

- Listed all applicable source files for doc type
- Confirmed review of each source file
- Extracted appropriate level of detail:
  - Implementation details for modules
  - Patterns and relationships for module types
  - Project-wide concepts for root
- No mixing of abstraction levels
- No assumptions made
- No inappropriate sources used

**Finding Applicable Source Files**:

1. Individual Module:
   - Located in one of:
     - `apps/subsystems/<name>/`
     - `components/<name>/`
     - `infrastructure/subsystems/<name>/`
   - Start with kustomization.yaml in module directory
   - Review all referenced implementation files

2. Module Type:
   - Located in one of:
     - `apps/README.md`
     - `infrastructure/README.md`
   - Review all module READMEs for the respective module type:
     - apps: `apps/subsystems/*/README.md`
     - infrastructure: `infrastructure/subsystems/*/README.md`
   - Also reference project brief for high level contextual details on how everything fit together:
     - `projectBrief.md`

3. Repository Root:
   - Start with:
     - `projectBrief.md`
   - Review module type docs:
     - `apps/README.md`
     - `infrastructure/README.md`

### 2. NO Assumptions

**Rule**: ONLY use information explicitly found in implementation files.

**Why**: LLMs automatically fill knowledge gaps, resulting in:

- Generic details that don't match implementation
- Assumed relationships that don't exist
- Configurations that won't work with implementation
- Features that aren't actually present

**Verify**:

- Every detail comes from implementation
- Each relationship is in code
- All configurations exist
- No general knowledge used

### 3. Complete Review Required / NO Partial File Review

**Rule**: MUST review each file completely and track progress.

**Why**: LLMs often process files partially or lose context between operations, causing:

- Missed configuration details
- Missing integration points
- Incorrect component relationships (intra-module relationsips)
- Incomplete or incorrect dependency chains (inter-module relationships)
- Overlooked requirements
- Lost progress

**Verify**:

- Listed all implementation files
- Read each file completely
- Extracted all configurations
- Mapped all relationships

### 4. Question-Driven Clarification

**Rule**: MUST ask questions when encountering:

- Ambiguous configurations
- Unclear relationships
- Missing requirements
- Implementation gaps

**Why**: LLMs tend to fill gaps with assumptions rather than asking for clarification.

**Verify**:

- Each assumption is questioned
- Each gap is identified
- Each ambiguity is clarified
- No inferences without verification

## Documentation Process

### 1. Implementation-First Approach

- Start with implementation files
- Extract actual configurations
- Map real dependencies
- Verify all relationships
- Document only what exists

### 2. Bottom-Up Strategy

IMPORTANT: Documentation MUST follow dependency order and abstraction levels:

1. Infrastructure Modules First:
   - Find complete dependency graph in projectBrief.md
   - Start with module at root of dependency tree
   - Follow dependency graph for next module
   - Document each module completely before proceeding
   - Track progress using Required State Format

2. Apps and Component Modules Next:
   - No specific order (not interdependent)
   - MUST complete ALL infrastructure first
   - Located in:
     - `apps/subsystems/<name>/`
     - `components/<name>/`
   - Track progress using Required State Format

3. Module Types (after ALL modules complete):
   - Move up to directory root level:
     - `infrastructure/`
     - `apps/`
     - `components/`
   - Use module READMEs as ONLY source
   - Focus on cluster capabilities
   - Maintain consistent abstraction level

4. Repository Root (after ALL types complete):
   - Use projectBrief.md as primary source
   - Use module type READMEs as secondary source material
   - Document project-wide concepts
   - Ensure clear navigation structure

This maintains strict abstraction progression:
Implementation (modules) -> Capabilities (types) -> Project (root)

### 3. Progress Management

**Required State Format**:

```text
Current Session State:
1. Documents to Process: [full paths]
2. Current Progress:
   - Completed: [docs with paths]
   - In Progress: [current doc]
   - Remaining: [docs to do]
3. Implementation Review:
   - Files Reviewed: [paths]
   - Pending Review: [paths]
4. Dependencies:
   - Verified: [list]
   - Pending: [list]
```

## Common Failure Patterns

### 1. Premature Documentation

|||
|-|-|
| **Pattern** | Starting to write before complete implementation review |
| **Result** | Generic, inaccurate documentation that doesn't match reality |
| **Prevention** | Force complete file review first |

### 2. Assumption Insertion

|||
|-|-|
|**Pattern** | Using general knowledge to fill gaps |
| **Result** | Documentation of features, capabilities or configuration that doesn't exist or doesn't match implementation |
| **Prevention** | Assert that every detail can be tied back to a specific implementation source |

### 3. Partial Processing

|||
|-|-|
| **Pattern** | Using incomplete file information |
| **Result** | Missing critical details and relationships |
| **Prevention** | Mandate complete file processing |

### 4. Context Loss

|||
|-|-|
| **Pattern** | Losing track of progress and dependencies |
| **Result** | Inconsistent, incomplete documentation |
| **Prevention** | Enforce strict state tracking, update progress regularly and verify completion |
