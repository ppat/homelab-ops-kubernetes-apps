# LLM Prompt: Implement Chainsaw Namespace-Specific Event Filtering

## Starting Protocol

You MUST begin by:

1. Reading the running log at `.analysis/chainsaw-event-filtering.log` to determine current progress and task context (do NOT rely on context window as it may be condensed/summarized)
2. Stating your understanding of the problem, solution approach, and current progress state from the log
3. Requesting explicit "GO" approval before proceeding with any work

## Context Section

### Problem Definition

Currently, when Chainsaw tests fail, the global configuration dumps ALL Kubernetes events from ALL namespaces (`namespace: '*'` in `.chainsaw.yaml`). This creates excessive noise making it harder to troubleshoot the actual source of problems. We need to modify the system to only output events for relevant namespaces based on actions being taken within each try block, with events appearing at the very end of each catch block.

### Design Concepts Used Within Project

**Module Independence**: Self-contained functionality with clear boundaries, independent versioning, dependencies specified at point of use rather than within modules.

**Configuration Flexibility**: Multiple configuration methods including Kustomize patches, FluxCD post-build variables, and component-based customization.

**Dependency Management**:

- **Hard Dependencies**: Explicitly declared via FluxCD `spec.dependsOn`, used sparingly only when necessary
- **Soft Dependencies**: Rely on Kubernetes eventually consistent model, monitored via Prometheus ServiceMonitors and PrometheusRules
- **Core/Extra Pattern**: Used to break circular dependencies - core modules contain essential services, extra modules depend on other modules

**Testing Integrity**: Module-level testing as complete units, dependency validation, resource state verification.

### Project Structure and Organization (Technical Concepts to File System Mapping)

```
homelab-ops-kubernetes-apps/
├── infrastructure/subsystems/          # Infrastructure Modules
│   ├── security-core/                  # Core security services (cert-manager, external-secrets, trust-manager)
│   ├── security-extra/                 # Extended security (authentik, kyverno, policy-reporter)
│   ├── storage-core/                   # Core storage (longhorn, minio, nfs-csi-driver)
│   ├── networking-core/                # Core networking (metallb, external-dns, traefik)
│   ├── networking-extra/               # Extended networking (pi-hole, freeradius, tailscale, unifi)
│   ├── observability-core/             # Core observability (prometheus, loki, grafana)
│   ├── observability-extra/            # Extended observability (event-exporter, node-problem-detector, snmp-exporter, syslog-ng, unifi-poller)
│   ├── database-core/                  # Core database (cloudnative-pg)
│   ├── kubernetes-core/                # Core k8s (coredns)
│   ├── kubernetes-extra/               # Extended k8s (node-feature-discovery, vpa, descheduler)
│   ├── clusterops-core/                # Core cluster ops (fluxcd, system-upgrade-controller)
│   └── clusterops-extra/               # Extended cluster ops (goldilocks, reloader)
├── apps/subsystems/                    # Application Modules
│   ├── ai/                             # AI applications (ollama, open-webui)
│   ├── bitwarden/                      # Password management
│   ├── coder/                          # Development environments
│   ├── downloaders/                    # Media automation (sonarr, radarr, lidarr, prowlarr, sabnzbd)
│   ├── harbor/                         # Container registry
│   ├── home-automation/                # Smart home (home-assistant)
│   ├── media/                          # Media streaming (plex, jellyfin, freetube, tautulli)
│   └── misc/                           # Miscellaneous (maddy smtp)
├── components/                         # Component Modules (Cross-cutting)
└── ci/test/                           # ← PRIMARY WORK AREA
    ├── chainsaw/
    │   ├── .chainsaw.yaml             # ← Global config with current problem
    │   ├── assertions/                # Reusable assertion templates
    │   ├── scripts/                   # Test utility scripts
    │   └── steps/                     # Reusable step templates
    ├── infra-security/                # Maps to infrastructure/subsystems/security-*
    ├── infra-storage/                 # Maps to infrastructure/subsystems/storage-*
    ├── infra-networking/              # Maps to infrastructure/subsystems/networking-*
    ├── infra-observability/           # Maps to infrastructure/subsystems/observability-*
    ├── infra-database/                # Maps to infrastructure/subsystems/database-*
    ├── infra-kubernetes/              # Maps to infrastructure/subsystems/kubernetes-*
    ├── infra-clusterops/              # Maps to infrastructure/subsystems/clusterops-*
    ├── apps-ai/                       # Maps to apps/subsystems/ai
    ├── apps-bitwarden/                # Maps to apps/subsystems/bitwarden
    ├── apps-coder/                    # Maps to apps/subsystems/coder
    ├── apps-downloaders/              # Maps to apps/subsystems/downloaders
    ├── apps-harbor/                   # Maps to apps/subsystems/harbor
    ├── apps-home-automation/          # Maps to apps/subsystems/home-automation
    ├── apps-media/                    # Maps to apps/subsystems/media
    └── apps-misc/                     # Maps to apps/subsystems/misc
```

### Dependencies Influencing Implementation Order

**Complete Module Dependency Graph** (from projectBrief.md):

```
Legend: Arrow direction (→) indicates "depends on"

Core Dependencies:
- storage-core → security-core
- networking-core → security-core
- observability-core → security-core
- observability-core → storage-core

Extra Dependencies:
- clusterops-extra → clusterops-core
- security-extra → security-core
- security-extra → storage-core
- security-extra → database-core
- networking-extra → security-core
- networking-extra → storage-core
- networking-extra → networking-core
- observability-extra → observability-core
- kubernetes-extra → kubernetes-core

Applications:
- All applications → Infrastructure modules
```

**Test Implementation Order** (based on dependency graph):

1. **Foundation**: `infra-security` (security-core) - No dependencies
2. **Core Infrastructure**: `infra-storage`, `infra-networking`, `infra-observability` - Depend on security-core
3. **Specialized Core**: `infra-database`, `infra-kubernetes`, `infra-clusterops` - May depend on other core modules
4. **Extended Infrastructure**: `infra-security` (security-extra), `infra-networking` (networking-extra), `infra-observability` (observability-extra), `infra-kubernetes` (kubernetes-extra), `infra-clusterops` (clusterops-extra)
5. **Applications**: All `apps-*` modules - Depend on infrastructure

### Current Chainsaw Implementation Analysis

**Global Configuration Problem** (from `ci/test/chainsaw/.chainsaw.yaml`):

```yaml
error:
  catch:
  - script:
      content: |
        echo -----------------------------------------------------------------------
        flux get all --all-namespaces
        echo -----------------------------------------------------------------------
        kubectl get -A crd,cm,secret,po,svc,ing,deploy,ds,sts,cj,job,pv,pvc,es,cert
        echo -----------------------------------------------------------------------
  - events:
      namespace: '*'  # ← PROBLEM: Dumps ALL namespace events
```

**Test Structure Patterns** (from `ci/test/infra-networking/chainsaw-test.yaml`):

```yaml
steps:
- name: Apply infra-networking modules
  try:
  - description: Apply infra-networking-core
    apply:
      file: ./infra-networking-core.yaml    # ← Targets flux-system namespace
  catch:
  - describe:
      namespace: flux-system                # ← Namespace identified but no events
```

**StepTemplate Patterns** (from `ci/test/infra-networking/validate-traefik.yaml`):

```yaml
spec:
  try:
  - description: Assert daemonset/traefik
    assert:
      bindings:
      - name: namespace
        value: traefik                      # ← Namespace identified
  catch:
  - describe:
      namespace: traefik                    # ← Namespace identified but no events
```

## Work Instructions

### Implementation Approach

Work through items in CURRENT PROGRESS STATE (see Progress Tracking Mechanism section) in listed order - Global Config must be completed first, then each test in sequence. Each item must be completed and verified before moving to the next.

### Global Configuration Changes

For the Global Config item in CURRENT PROGRESS STATE:

1. **Remove Global Event Dumping**: Modify `ci/test/chainsaw/.chainsaw.yaml` to remove or comment out the `events: namespace: '*'` line that dumps all namespace events

### Per-Test Implementation Approach

For each test item in CURRENT PROGRESS STATE, follow this comprehensive approach:

1. **Analyze Test Structure**: Review all `chainsaw-test.yaml` and `validate-*.yaml` files in the test directory as well as any module definitions (`infra-*.yaml` or `apps-*.yaml`) - these are additional files within the test directory that you should analyze to understand what namespaces are being used

2. **Identify Try/Catch Blocks and Extract Namespace Information**: Locate all try/catch blocks across main test file and StepTemplate files, then for each try block identify namespaces using these rules:

   **Namespace Identification Rules**:
   - **apply operations**: Check file content or determine target namespace from Kustomization
   - **assert operations**: Use `namespace` binding value or resource definition namespace
   - **describe/podLogs operations**: Use explicit `namespace` field value
   - **script operations**: Analyze kubectl/flux commands to identify target namespaces
   - Each try block may involve multiple namespaces - collect ALL namespaces used across ALL operations
   - Add separate `events:` operation for each unique namespace

3. **Implement Event Filtering**: Add `events:` operations with specific `namespace:` field at end of each catch block for all identified namespaces, positioning ALL event operations at very end of catch block

4. **Verify Implementation**: Ensure entire test passes Verification Checklist and Success Criteria section before marking completed

5. **Update Progress**: After completing entire test implementation:
   - Update `.analysis/chainsaw-event-filtering.log` with current progress state (see Progress Tracking Mechanism section for log format)
   - Log implementation details including files modified and namespaces identified

### Work Constraints

- **Cannot run tests**: Must request user validation for any testing needs
- **Write restrictions**: Only modify files in ci/, .analysis/, .prompts/ directories
- **Sequential completion**: Complete current item from CURRENT PROGRESS STATE fully before moving to next
- **Verification per item**: Must pass Verification Checklist and Success Criteria section before marking item completed
- **Log dependency**: Always read running log first to understand current context

## Progress Tracking Mechanism

This is the Running Log Format used in the running log file (`.analysis/chainsaw-event-filtering.log`). Order in CURRENT PROGRESS STATE follows Dependencies Influencing Implementation Order section.

```
=== CHAINSAW EVENT FILTERING IMPLEMENTATION LOG ===

## CURRENT PROGRESS STATE
[Updated after each completed item]
- Global Config: [Pending/In-Progress/Completed] - Remove global event dumping
- infra-security: [Pending/In-Progress/Completed] - Event filtering implementation
- infra-storage: [Pending/In-Progress/Completed] - Event filtering implementation
- infra-networking: [Pending/In-Progress/Completed] - Event filtering implementation
- infra-observability: [Pending/In-Progress/Completed] - Event filtering implementation
- infra-database: [Pending/In-Progress/Completed] - Event filtering implementation
- infra-kubernetes: [Pending/In-Progress/Completed] - Event filtering implementation
- infra-clusterops: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-ai: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-bitwarden: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-coder: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-downloaders: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-harbor: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-home-automation: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-media: [Pending/In-Progress/Completed] - Event filtering implementation
- apps-misc: [Pending/In-Progress/Completed] - Event filtering implementation

## ACTIONS TAKEN LOG
[Chronological list with timestamps]
YYYY-MM-DD HH:MM - Action description
YYYY-MM-DD HH:MM - Action description
```

## Verification Checklist and Success Criteria

For Each Item Implementation, perform the following verification. Verification must pass before moving to next item. Verification result must indicate how the verification was performed.

**Syntactical and Technical Accuracy**:

- [ ] Existing naming and formatting conventions are followed for changes
- [ ] Namespace references are correct and match try block operations
- [ ] Event operations are properly positioned at end of catch blocks
- [ ] Implementation achieves the goal of test-specific event filtering by applicable namespace
- [ ] Events appear at very end of catch blocks as specified
- [ ] Namespace identification correctly matches operations in try blocks

**No Unintended Changes**:

- [ ] No improvements or optimizations beyond the stated task
- [ ] Existing naming and formatting conventions preserved
- [ ] No modifications outside ci/, .analysis/, .prompts/ directories
- [ ] Existing test logic and behavior preserved
- [ ] Changes are minimal and focused on the specific problem

Start by reading the running log to understand current progress and context.
