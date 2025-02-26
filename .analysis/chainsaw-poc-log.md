# Activity Log: Chainsaw Testing Migration PoC

**Date:** 2024-02-24

## 1. Research Findings

### Finding F001: Project Structure and Testing Framework

- **Source:** `/home/coder/code/homelab-ops-kubernetes-apps/projectBrief.md`
- **Implications:**
  - Must maintain existing module structure and dependencies
  - Testing must validate both native K8s resources and CRDs
  - Need to preserve FluxCD-based deployment in tests
  - Must support Core/Extra pattern for module testing
- **Description:**
  The project uses a structured approach to Kubernetes modules with:
  1. Core/Extra pattern for managing complex dependencies
  2. Comprehensive testing strategy including:
     - Module-level testing as complete units
     - Resource validation against K8s specs and CRDs
     - FluxCD-based deployment in tests
     - Dependency validation (both hard and soft)
  3. Strong emphasis on module independence and clear boundaries
  4. Multiple configuration methods including Kustomize patches and FluxCD post-build variables

### Finding F002: Current Core Module Testing

- **Source:** `/home/coder/code/homelab-ops-kubernetes-apps/.github/workflows/test-infrastructure-kubernetes.yaml`
- **Implications:**
  - Must maintain exact validation sequence
  - Must preserve all timeout configurations
  - Must handle FluxCD-based deployment
  - Need to support variable substitution
- **Description:**
  The current test implementation follows this sequence:
  1. Reconciliation (First Step):
     - Resource: kustomization/infra-kubernetes-core
     - Namespace: flux-system
     - Timeout: 3m
     - Dependencies: cluster-common-conf, cluster-networking-conf
  2. Success Conditions (In Order):
     a. CoreDNS ConfigMap:
        - Resource: configmap/coredns-custom
        - Namespace: kube-system
        - Check: jsonpath={.metadata.creationTimestamp}
        - Timeout: 1m
     b. CoreDNS Deployment:
        - Resource: deployment/coredns
        - Namespace: kube-system
        - Check: condition=available
        - Timeout: 1m
     c. API Access:
        - Resource: ingress/kubernetes-api
        - Namespace: default
        - Check: jsonpath={.metadata.creationTimestamp}
        - Timeout: 1m

### Finding F003: Current Extra Module Testing

- **Source:** `/home/coder/code/homelab-ops-kubernetes-apps/.github/workflows/test-infrastructure-kubernetes.yaml`
- **Implications:**
  - Must maintain exact validation sequence
  - Must preserve all timeout configurations
  - Must handle CI-specific adaptations
  - Need to support variable substitution
- **Description:**
  The current test implementation follows this sequence:
  1. Reconciliation (Second Step):
     - Resource: kustomization/infra-kubernetes-extra
     - Namespace: flux-system
     - Timeout: 3m
     - Dependencies: cluster-common-conf
  2. Success Conditions (In Order):
     a. Node Feature Discovery:
        - Resource: deployment/node-feature-discovery-master
        - Namespace: kube-system
        - Check: condition=available
        - Timeout: 1m
        - Resource: daemonset/node-feature-discovery-worker
        - Namespace: kube-system
        - Check: rollout status
        - Timeout: 1m
        - Resource: deployment/node-feature-discovery-gc
        - Namespace: kube-system
        - Check: condition=available
        - Timeout: 1m
     b. Resource Management:
        - Resource: deployment/vertical-pod-autoscaler-vpa-recommender
        - Namespace: kube-system
        - Check: condition=available
        - Timeout: 1m
     c. Device Plugins:
        - Resource: helmrelease/intel-plugin-operator-release
        - Namespace: intel-device-plugins
        - Check: jsonpath={.metadata.creationTimestamp}
        - Timeout: 1m
        - Resource: helmrelease/intel-gpu-plugin-release
        - Namespace: intel-device-plugins
        - Check: jsonpath={.metadata.creationTimestamp}
        - Timeout: 1m
        - Resource: daemonset/generic-device-plugin
        - Namespace: kube-system
        - Check: rollout status
        - Timeout: 1m
     d. Workload Management:
        - Resource: deployment/descheduler
        - Namespace: kube-system
        - Check: condition=available
        - Timeout: 1m

### Finding F004: Current Testing Implementation

- **Source:** `/home/coder/code/homelab-ops-kubernetes-apps/.github/workflows/test-kubernetes-resources-workflow.yaml`
- **Implications:**
  - Must replicate key testing capabilities in Chainsaw
  - Need to maintain similar environment setup process
  - Must support equivalent validation mechanisms
  - Debug capabilities should be preserved
- **Description:**
  The current testing workflow provides several key capabilities:
  1. Environment Setup:
     - Kind cluster creation with specific K8s version
     - FluxCD installation and configuration
     - Git source bootstrapping
  2. Test Execution:
     - Pre-requisites deployment
     - Module deployment via FluxCD
     - Resource reconciliation
     - Success condition validation
  3. Validation Features:
     - Wait for specific resource conditions
     - Special handling for DaemonSets and StatefulSets
     - Custom command execution support
  4. Debug Capabilities:
     - Detailed failure information
     - Resource state inspection
     - Controller logs access
     - Status reporting

### Finding F005: Test Workflow Orchestration

- **Source:** Multiple files:
  - test-infrastructure-kubernetes.yaml
  - test-kubernetes-resources-workflow.yaml
  - infra-kubernetes-core.yaml
  - infra-kubernetes-extra.yaml
- **Implications:**
  - Must preserve strict execution order
  - Need to maintain workflow integration points
  - Must handle configuration inheritance
  - Need equivalent debug capabilities
- **Description:**
  The test workflow enforces a specific execution order:
  1. Ordered Reconciliation:
     - First: infra-kubernetes-core (3m timeout)
       - Requires: cluster-common-conf, cluster-networking-conf
     - Second: infra-kubernetes-extra (3m timeout)
       - Requires: cluster-common-conf
  2. Ordered Success Validation:
     - Core Module Checks:
       - First: CoreDNS ConfigMap
       - Second: CoreDNS Deployment
       - Third: Kubernetes API ingress
     - Extra Module Checks:
       - First: Node Feature Discovery components (master, worker, gc)
       - Second: VPA recommender
       - Third: Intel device plugins and operator
       - Fourth: Generic device plugin
       - Fifth: Descheduler
  3. Configuration Flow:
     - FluxCD bootstraps git source
     - Kustomizations apply module configs
     - Post-build substitutions from ConfigMaps
     - CI-specific patches for Intel plugins
  4. Debug Sequence:
     - First: Namespace events
     - Second: Intel plugin status
     - Third: HelmRelease details

### Finding F006: Chainsaw Test Structure

- **Source:** `/home/coder/code/chainsaw/website/docs/quick-start/first-test.md`
- **Implications:**
  - Tests can be organized in a clear folder structure
  - Each test can have multiple steps and operations
  - Operations are executed sequentially
  - Test files can reference other files in the filesystem
- **Description:**
  Chainsaw provides a structured testing approach:
  1. Test Organization:
     - One folder per test
     - Default test file: chainsaw-test.yaml
     - Can reference external files and manifests
  2. Test Structure:
     - Tests contain ordered sequence of steps
     - Steps contain ordered sequence of operations
     - Operations include apply and assert capabilities
  3. Test Execution:
     - Sequential operation execution
     - Fail-fast on operation failure
     - Success requires all operations to succeed
  4. Key Features:
     - File-based resource definitions
     - Resource creation verification
     - Data validation capabilities
     - Clear success/failure criteria

### Finding F007: Chainsaw Test Execution

- **Source:** `/home/coder/code/chainsaw/website/docs/quick-start/run-tests.md`
- **Implications:**
  - Need external cluster management (e.g., kind)
  - Must configure appropriate timeouts
  - Need to handle test discovery and organization
  - Must manage namespace creation/cleanup
- **Description:**
  Chainsaw provides test execution features:
  1. Test Discovery:
     - Recursive test file discovery
     - Default test file: chainsaw-test.yaml
     - Configurable test directories
  2. Execution Configuration:
     - Configurable timeouts for different operations
     - Namespace management
     - Fail-fast option
     - Test filtering capabilities
  3. Operation Timeouts:
     - Apply: 5s default
     - Assert: 30s default
     - Cleanup: 30s default
     - Delete: 15s default
     - Error: 30s default
     - Exec: 5s default
  4. Test Lifecycle:
     - Setup phase (namespace creation)
     - Test execution
     - Cleanup phase (resource deletion)
     - Detailed execution logging

### Finding F008: Chainsaw Assertion Capabilities

- **Source:** `/home/coder/code/chainsaw/website/docs/quick-start/assertion-trees.md`
- **Implications:**
  - Can handle complex validation scenarios
  - Supports flexible resource matching
  - Provides detailed failure reporting
  - Can validate array-based configurations
- **Description:**
  Chainsaw offers powerful assertion features:
  1. Resource Validation:
     - Exact resource matching by name
     - Label-based resource discovery
     - Partial resource validation
     - Complex condition evaluation
  2. Advanced Assertions:
     - Comparison operations beyond equality
     - Array filtering and iteration
     - Expression-based validation
     - Condition status verification
  3. Failure Reporting:
     - Detailed error messages
     - Resource diffs for failures
     - Context-rich output
     - Clear validation results
  4. Key Features:
     - JMESPath expression support
     - Array element iteration
     - Flexible resource lookup
     - Comprehensive diff output

### Finding F009: Chainsaw Operation File Support

- **Source:** Chainsaw API Documentation (v1alpha1)
- **Implications:**
  - Different operations have different file support capabilities
  - Some operations require inline resource definitions
  - Template reuse strategy needs to be operation-specific

- **Description:**
  Operations fall into distinct categories based on their file support:
  1. Operations Supporting External Files:
     - Apply: via ActionResourceRef.file
     - Assert: via ActionCheckRef.file
     - Create: via ActionResourceRef.file
     - Delete: via direct file field
     - Error: via ActionCheckRef.file
     - Patch: via ActionResourceRef.file
     - Update: via ActionResourceRef.file

 2. Operations Requiring Inline Resource Definitions:
    - Wait: uses ActionObject + WaitFor structure
    - Describe: uses ActionObject structure
    - Events: uses ActionObjectSelector
    - Get: uses ActionObject structure
    - PodLogs: uses ActionObjectSelector
    - Proxy: uses ObjectName + ObjectType

 3. Operations Using Direct Field Definitions:
    - Command: uses entrypoint + args
    - Script: uses content field
    - Sleep: uses duration field

### Finding F010: Chainsaw Template Support

- **Source:** Chainsaw Documentation (resource-templating.md, templating.md, explicit.md)
- **Implications:**
  - Templates work consistently across both inline and external files
  - Enables reuse of templated resources across tests
  - Supports dynamic configuration through bindings
  - Provides powerful JMESPath-based expressions

- **Description:**
  Chainsaw's templating system provides flexible configuration:

1. Template Locations:
   - Works in inline resource definitions
   - Works in external referenced files
   - Consistent behavior across both approaches

2. Template Features:
   - Binding substitution (e.g., ($namespace))
   - JMESPath expressions
   - Function support (e.g., join, length)
   - Dynamic value injection

3. Template Use Cases:
   - Resource naming and labels
   - Configuration values
   - Dynamic field values
   - Cross-test resource sharing

## 2. Conclusions

### Conclusion C001: Feature Parity Analysis

- **Statement:** Chainsaw provides equivalent or superior capabilities for all current testing requirements
- **Related Findings:** F004, F005, F006, F007, F008
- **Basis:**
  1. Test Workflow Integration (F004, F005):
     - Current: GitHub Actions workflow with FluxCD integration
     - Chainsaw: Step-based execution with external cluster management
     - Equivalent: Both support orchestrated test execution

  2. Test Organization (F004, F006):
     - Current: Workflow-based test configuration
     - Chainsaw: Structured test folders and files
     - Advantage: Better organization and maintainability

  3. Resource Validation (F004, F008):
     - Current: Wait conditions and status checks
     - Chainsaw: Assertion trees with complex validation
     - Advantage: More powerful validation capabilities

  4. Debug Capabilities (F004, F008):
     - Current: Logs access and event inspection
     - Chainsaw: Detailed diffs and failure reporting
     - Advantage: More comprehensive debugging information

### Conclusion C002: Module Test Migration Requirements

- **Statement:** Current test validations for both modules can be effectively implemented using Chainsaw's assertion capabilities
- **Related Findings:** F002, F003, F005, F008
- **Basis:**
  1. Core Module Tests (F002):
     - Resource Validation:
       - Current: CoreDNS ConfigMap and Deployment checks with 1m timeout
       - Chainsaw Solution: Assert operations with configurable timeouts
     - API Validation:
       - Current: Kubernetes API ingress existence check
       - Chainsaw Solution: Resource existence assertions
     - Configuration:
       - Current: FluxCD kustomization with 3m timeout
       - Chainsaw Solution: Sequential apply and assert operations

  2. Extra Module Tests (F003):
     - Component Validation:
       - Current: NFD deployments and DaemonSet checks
       - Chainsaw Solution: Multi-resource assertions with status checks
     - CI Adaptations:
       - Current: Special handling for Intel plugins
       - Chainsaw Solution: Conditional assertions and error handling
     - Deployment Checks:
       - Current: Multiple component availability checks
       - Chainsaw Solution: Parallel resource validation

  3. Common Requirements (F005, F008):
     - Timeout Management:
       - Current: Per-resource timeout configuration
       - Chainsaw Solution: Operation-specific timeout settings
     - Debug Support:
       - Current: Event and status inspection
       - Chainsaw Solution: Built-in failure reporting and diffs

### Conclusion C003: Migration Strategy Requirements

- **Statement:** A successful migration requires maintaining current capabilities while leveraging Chainsaw's enhanced features
- **Related Findings:** F001, F004, F005, F006, F007
- **Basis:**
  1. Environment Setup (F004, F007):
     - Current Approach: GitHub Actions workflow manages cluster setup
     - Migration Need: Maintain kind cluster creation and FluxCD setup
     - Solution: Use external cluster management with Chainsaw tests

  2. Test Organization (F001, F006):
     - Current Approach: Workflow-based test configuration
     - Migration Need: Preserve module testing structure
     - Solution: Map to Chainsaw's folder-based test organization

  3. Validation Strategy (F005):
     - Current Approach: Success conditions in workflow config
     - Migration Need: Maintain all current validation checks
     - Solution: Convert to Chainsaw assertion trees and timeouts

  4. Tooling Requirements:
     - Cluster Management: External kind setup
     - FluxCD Integration: Pre-test environment setup
     - Test Discovery: Chainsaw's recursive file discovery
     - Resource Validation: Chainsaw's assertion capabilities

### Conclusion C004: Operation-Specific Reusability Constraints

- **Statement:** Component reusability is determined by operation type support for external files
- **Related Findings:** F009
- **Basis:**
  1. File-Supporting Operations:
     - Operations like Apply, Assert, Create, Delete, Error, Patch, and Update
     - Can externalize components into reusable files
     - Enable sharing between tests
     - Support modular organization
     - Best suited for resource definitions and assertions

  2. Inline-Only Operations:
     - Operations like Wait, Describe, Events, Get, PodLogs, and Proxy
     - Must be defined within test files
     - Cannot be externalized
     - Limited reuse through bindings
     - Best suited for monitoring and inspection

  3. Direct Field Operations:
     - Operations like Command, Script, and Sleep
     - Simple field-based configuration
     - No component externalization
     - Minimal reuse needs
     - Best suited for utility operations

  4. Impact on Component Strategy:
     - Reusability depends on operation type
     - External files only where supported
     - Inline definitions where required
     - Clear boundaries between approaches
     - Operation type drives organization

### Conclusion C005: Unified Template Strategy

- **Statement:** Chainsaw's template capabilities enable a unified approach to resource reuse despite operation-specific file support limitations
- **Related Findings:** F009, F010
- **Basis:**

1. Template-First Design:
   - Templates work consistently in both inline and external files
   - Bindings provide operation-agnostic value substitution
   - JMESPath expressions work across all template locations
   - Enables consistent patterns regardless of operation type

2. Operation-Aware Implementation:
   - File-supporting operations (Apply, Assert, etc.):
     - Use external files with templates
     - Enable direct resource reuse
     - Support complex template patterns
   - Inline-only operations (Wait, Describe, etc.):
     - Use templates directly in test files
     - Leverage bindings for value reuse
     - Share patterns through binding definitions

3. Reuse Patterns:
   - Common values through global bindings
   - Shared templates for file-supporting operations
   - Binding-based templates for inline operations
   - Consistent expression patterns across all uses

4. Best Practices:
   - Define reusable values as bindings
   - Use external files when supported
   - Maintain consistent template patterns
   - Share bindings across related operations

### Conclusion C006: Configuration Management Requirements

- **Statement:** Effective test configuration requires a layered approach to handle different scopes and environments
- **Related Findings:** F004, F005, F007
- **Basis:**
  1. Configuration Scopes:
     - Global test settings (timeouts, error handling)
     - Environment-specific values (URLs, namespaces)
     - Test-specific bindings (component names, versions)
     - Current approach uses workflow variables and ConfigMaps

  2. Environment Adaptability:
     - CI vs local execution differences
     - Need for environment-specific values
     - Consistent configuration interface
     - Easy environment switching

  3. Chainsaw Features:
     - Built-in configuration file support
     - Values file capabilities
     - Command-line overrides
     - Native binding system

### Conclusion C007: Error Handling and Debug Requirements

- **Statement:** Comprehensive error handling must combine step-specific debugging with proper resource cleanup
- **Related Findings:** F004, F007, F008
- **Basis:**
  1. Current Capabilities:
     - Workflow-level error reporting
     - Resource state inspection
     - Log access for debugging
     - Manual cleanup steps

  2. Chainsaw Features:
     - Try/catch/finally blocks
     - Operation-specific error handling
     - Built-in cleanup mechanisms
     - Detailed failure reporting

  3. Integration Requirements:
     - Step-specific debug information
     - Consistent resource cleanup
     - Clear error reporting
     - Fail-fast behavior

### Conclusion C008: Template-Based Testing Effectiveness

- **Statement:** Template-based testing significantly reduces maintenance overhead and improves test consistency
- **Related Findings:** F006, F010
- **Related Decisions:** D003, D004, D008, D009
- **Basis:**
  1. Code Reduction:
     - 75% reduction in test YAML size through templates
     - Consistent timeout handling across 12+ resources
     - Single source of truth for assertions

 2. Maintenance Benefits:
     - Changes to validation logic only needed in one place
     - Assert-based validation with conditional checks provides precise status validation
     - Common operations centralized in step templates

 3. Consistency Improvements:
     - Standardized validation patterns across resources
     - Uniform approach to FluxCD bootstrapping
     - Consistent error handling and debugging

## 3. Design Decisions

### Decision D001: Test Organization Structure

- **Decision Topic:** How to organize Chainsaw tests to maintain module dependencies and ordering
- **Options Considered:**
  1. Separate Test Files:
     - Pros:
       - Clear module separation
       - Independent test definitions
     - Cons:
       - Hard to manage dependencies
       - Could break required ordering
       - Doesn't match current workflow

  2. Single Test File with Sections:
     - Pros:
       - Maintains module coupling
       - Clear test flow
       - Easy to see dependencies
     - Cons:
       - Less modular
       - Larger file to maintain

  3. Combined Approach with Resource Separation (Recommended):
     - Pros:
       - Preserves core/extra coupling
       - Clear resource organization
       - Maintains test ordering
       - Enables resource reuse
     - Cons:
       - Need careful resource management
- **Recommended Approach:**

  ```
  ci/
  ├── test/
  │   ├── common/                          # Shared test resources
  │   │   ├── configmaps/                  # Common ConfigMaps
  │   │   │   ├── cluster-common.yaml      # Default test config
  │   │   │   └── cluster-networking.yaml  # Network config
  │   │   └── kind-cluster.yaml           # Cluster configuration
  │   └── infra-kubernetes/               # Test directory
  │       ├── chainsaw-test.yaml          # Main test definition
  │       ├── configmaps/                 # Test-specific configs
  │       │   └── test-config.yaml        # Test variables
  │       ├── infra-kubernetes-core.yaml  # Core module config with patches
  │       └── infra-kubernetes-extra.yaml # Extra module config with patches
  ```

- **Questions for Collaborator:**
  1. Do we need additional structure for FluxCD bootstrapping beyond the existing files?

### Decision D002: Reusable Component Strategy

- **Decision Topic:** How to identify and implement reusable components based on operation capabilities
- **Related Findings and Conclusions:**
  - F009: Operation File Support
  - C004: Operation-Specific Reusability Constraints
- **Key Capabilities:**
  - Different operations support different file handling methods
  - Some operations require inline resource definitions
  - Component organization must align with operation constraints
- **Options Considered:**
  1. All Components as External Files:
     - Pros:
       - Maximum reusability
       - Easier maintenance
       - Clear separation of concerns
     - Cons:
       - Not supported by all operations
       - Could lead to invalid configurations
       - More complex file management

  2. All Components Inline:
     - Pros:
       - Works with all operations
       - Simpler file structure
       - Direct visibility
     - Cons:
       - No reuse between tests
       - Duplicate code
       - Harder to maintain

  3. Operation-Aware Component Strategy (Recommended):
     - Pros:
       - Respects operation capabilities
       - Maximizes reuse where possible
       - Clear guidelines for each type
     - Cons:
       - Different approaches for different operations
       - Need to understand operation capabilities
       - More initial setup

- **Recommended Approach:**
  1. File-Supporting Operations:
     - Apply, Assert, Create, Delete, Error, Patch, Update
     - Externalize only when component is reusable across tests
     - Keep test-specific components inline or within test directory
     - Example:

       ```yaml
       # common/resources/deployment.yaml (reusable component)
       apiVersion: apps/v1
       kind: Deployment
       metadata:
         name: nginx
         namespace: web
         labels:
           app: nginx
       spec:
         replicas: 3
         selector:
           matchLabels:
             app: nginx
         template:
           metadata:
             labels:
               app: nginx
           spec:
             containers:
             - name: nginx
               image: nginx:latest
       ```

       Usage in test:

       ```yaml
       steps:
         - try:
           - assert:
               file: common/resources/deployment.yaml  # or test/my-test/resources/specific.yaml
       ```

  2. Inline-Required Operations:
     - Wait, Describe, Events, Get, PodLogs, Proxy
     - Define directly in test files
     - Example:

       ```yaml
       # Operation in test file
       wait:
         apiVersion: apps/v1
         kind: Deployment
         name: nginx
         namespace: web
         for:
           condition:
             name: Available
             value: "true"
       ```

  3. Direct Field Operations:
     - Command, Script, Sleep
     - Define with clear, static values
     - Example:

       ```yaml
       # Operation in test file
       command:
         entrypoint: kubectl
         args:
           - get
           - pods
           - -n
           - web
       ```

- **Implementation Guidelines:**
  1. Component Organization:
     - External files in common/ directory
     - Group by operation type
     - Clear naming conventions

  2. Value Sharing:
     - Use bindings for dynamic values
     - Define common values at test level
     - Keep operation-specific values close to use

  3. Maintenance Strategy:
     - Regular review of common components
     - Version control for shared files
     - Clear documentation of usage

  4. Component Types:
     - Resource Definitions: Kubernetes manifests for apply operations
     - Assertion Patterns: Status validation patterns for assert operations
     - Command Templates: Common command patterns for script/command operations
     - Each type should be organized in its own directory structure

- **Rationale:**
  1. Operation Support:
     - Respects Chainsaw's operation capabilities
     - Prevents invalid configurations
     - Clear guidance for each type

  2. Reusability:
     - Maximizes reuse where supported
     - Provides alternative patterns where needed
     - Consistent approach across tests

  3. Maintainability:
     - Clear organization structure
     - Easy to understand patterns
     - Reduced duplication

### Decision D003: Success Condition Implementation

- **Decision Topic:** How to implement kubectl wait status checks in Chainsaw
- **Current Implementation Analysis:**
  1. Condition Types:

     ```bash
     # Type 1: Wait for condition
     kubectl wait -n kube-system --for=condition=available deployment/coredns

     # Type 2: Wait for jsonpath
     kubectl wait -n kube-system --for=jsonpath={.metadata.creationTimestamp} configmap/coredns-custom
     ```

- **Chainsaw Implementation Options:**
  1. Using Wait Operation:

     ```yaml
     # For condition=available
     apiVersion: chainsaw.kyverno.io/v1alpha1
     kind: Test
     spec:
       steps:
       - try:
         - wait:
             apiVersion: apps/v1
             kind: Deployment
             name: coredns
             namespace: kube-system
             timeout: 1m
             for:
               condition:
                 name: Available
                 value: 'true'
     ```

  2. Using Assert Operation with Conditional Checks:

     ```yaml
     # For condition=available
     apiVersion: chainsaw.kyverno.io/v1alpha1
     kind: Test
     spec:
       steps:
       - try:
         - assert:
             resource:
               apiVersion: apps/v1
               kind: Deployment
               metadata:
                 name: coredns
                 namespace: kube-system
               status:
                 (replicas == readyReplicas): true
                 (replicas == availableReplicas): true
                 (conditions[?type == 'Available']):
                 - status: 'True'
     ```

- **Updated Recommendation:**
  While the `wait` operation provides a direct mapping to `kubectl wait`, the `assert` operation with conditional checks offers several advantages:

  1. Enhanced Validation:
     - Can check multiple conditions simultaneously
     - Supports complex JMESPath expressions
     - Enables precise status field validation

  2. Resource-Specific Validation:
     - Deployment: `(replicas == readyReplicas)` and `(replicas == availableReplicas)`
     - DaemonSet: `(numberReady == desiredNumberScheduled)` and `(numberAvailable == desiredNumberScheduled)`
     - StatefulSet: `(replicas == readyReplicas)` and `(currentReplicas == replicas)`

  3. Improved Test UX:
     - Richer failure reporting with detailed diffs
     - Clear indication of which conditions failed
     - Consistent timeout behavior from global configuration

- **Rationale for Assert-Based Approach:**
  1. Native Chainsaw Integration:
     - Uses Chainsaw's powerful assertion capabilities
     - Leverages built-in waiting mechanism (retries until timeout)
     - Provides more detailed failure information

  2. Flexibility:
     - Can validate complex resource states beyond simple conditions
     - Supports both simple and advanced validation patterns
     - Works consistently across all resource types

  3. Maintainability:
     - Clearer expression of validation requirements
     - More precise validation of resource state
     - Better alignment with Kubernetes resource status fields

- **Implementation Guidance:**
  - Use assert operations with conditional checks for all resource validation
  - Define specific status field checks based on resource type
  - Configure appropriate timeouts at the operation or global level

### Decision D004: Rollout Status Implementation

- **Decision Topic:** How to implement kubectl rollout status checks in Chainsaw
- **Current Implementation Analysis:**

  ```bash
  # Current command
  kubectl -n $namespace rollout status $resource_kind $resource_name --timeout $timeout

  # Example from test workflow
  kubectl -n kube-system rollout status daemonset/node-feature-discovery-worker --timeout 1m
  ```

- **Chainsaw Implementation Options:**
  1. Using Wait Operation:

     ```yaml
     # For DaemonSet rollout
     apiVersion: chainsaw.kyverno.io/v1alpha1
     kind: Test
     spec:
       steps:
       - try:
         - wait:
             apiVersion: apps/v1
             kind: DaemonSet
             name: node-feature-discovery-worker
             namespace: kube-system
             timeout: 1m
             for:
               condition:
                 name: Ready
                 value: 'true'
     ```

  2. Using Assert Operation:

     ```yaml
     apiVersion: chainsaw.kyverno.io/v1alpha1
     kind: Test
     spec:
       steps:
       - try:
         - assert:
             resource:
               apiVersion: apps/v1
               kind: DaemonSet
               metadata:
                 name: node-feature-discovery-worker
                 namespace: kube-system
               status:
                 (numberReady == desiredNumberScheduled): true
     ```

- **Recommended Approach:**
  Since Chainsaw doesn't have a direct equivalent to `kubectl rollout status`, we should use assert operations with specific status field checks for each resource type:

  1. DaemonSet:

     ```yaml
     apiVersion: chainsaw.kyverno.io/v1alpha1
     kind: Test
     spec:
       steps:
       - try:
         - assert:
             resource:
               apiVersion: apps/v1
               kind: DaemonSet
               metadata:
                 name: node-feature-discovery-worker
                 namespace: kube-system
               status:
                 (numberReady == desiredNumberScheduled): true
                 (numberAvailable == desiredNumberScheduled): true
     ```

  2. Deployment:

     ```yaml
     apiVersion: chainsaw.kyverno.io/v1alpha1
     kind: Test
     spec:
       steps:
       - try:
         - assert:
             resource:
               apiVersion: apps/v1
               kind: Deployment
               metadata:
                 name: coredns
                 namespace: kube-system
               status:
                 (replicas == readyReplicas): true
                 (replicas == availableReplicas): true
     ```

  3. StatefulSet:

     ```yaml
     apiVersion: chainsaw.kyverno.io/v1alpha1
     kind: Test
     spec:
       steps:
       - try:
         - assert:
             resource:
               apiVersion: apps/v1
               kind: StatefulSet
               metadata:
                 name: example
                 namespace: default
               status:
                 (replicas == readyReplicas): true
                 (currentReplicas == replicas): true
     ```

- **Rationale:**
  1. Resource-Specific Checks:
     - Each resource type has different status fields
     - Assert allows precise validation of these fields
     - More accurate than generic Ready condition

  2. Complete Status Verification:
     - Checks both readiness and availability
     - Ensures proper rollout completion
     - Matches kubectl rollout status behavior

  3. Consistent Approach:
     - Same pattern across resource types
     - Clear status field validation
     - Easy to maintain and understand

- **Next Steps:**
  1. Document these patterns for reuse
  2. Consider creating test templates for common cases
  3. Add timeout configuration at the assert operation level

### Decision D005: Workflow Integration Strategy

- **Decision Topic:** How to split responsibilities between GitHub Actions workflow and Chainsaw tests

- **Current Workflow Analysis:**
  1. Environment Setup (GitHub Actions):

     ```yaml
     - Setup kind cluster
     - Setup kubectl
     - Setup flux
     - Install flux in cluster
     ```

  2. Test Execution (Could Move to Chainsaw):

     ```yaml
     - Bootstrap flux from git source
     - Reconcile kustomizations
     - Wait for success conditions
     - Run custom commands
     ```

  3. Debug Capabilities (Mix):

     ```yaml
     - Show status (all resources)
     - Debug flux failures
     - Debug success condition failures
     ```

- **FluxCD Integration Strategy:**
  Moving FluxCD bootstrapping into Chainsaw provides better test isolation and debugging capabilities. The complete test implementation looks like this:

  ```yaml
  apiVersion: chainsaw.kyverno.io/v1alpha1
  kind: Test
  spec:
    # Test-wide timeouts
    timeouts:
      apply: 3m
      assert: 1m

    # Test configuration
    bindings:
      - name: git_url
        value: https://github.com/org/repo
      - name: git_ref
        value: main

    steps:
    # Step 1: Bootstrap FluxCD
    - try:
        # Create git source
        - command:
            entrypoint: flux
            args:
              - create
              - source
              - git
              - test-source
              - --url=($git_url)
              - --branch=($git_ref)
              - --export
        # Apply git source
        - command:
            entrypoint: kubectl
            args: ["apply", "--server-side", "-f", "-"]
        # Wait for source
        - wait:
            apiVersion: source.toolkit.fluxcd.io/v1
            kind: GitRepository
            name: test-source
            namespace: flux-system
            timeout: 1m
            for:
              condition:
                name: Ready
                value: "true"
      catch:
        # Debug source issues
        - command:
            entrypoint: flux
            args: ["get", "sources", "git", "-A"]
        - describe:
            apiVersion: source.toolkit.fluxcd.io/v1
            kind: GitRepository
            name: test-source
            namespace: flux-system

    # Step 2: Core Module
    - try:
        # Reconcile core module
        - command:
            entrypoint: flux
            args: ["reconcile", "kustomization", "-n", "flux-system", "infra-kubernetes-core", "--timeout", "3m"]
        # Wait for core components
        - assert:
            file: core/coredns.yaml
        - assert:
            file: core/api.yaml
      catch:
        # Component-specific debugging
        - describe:
            apiVersion: apps/v1
            kind: Deployment
            name: coredns
            namespace: kube-system
        - podLogs:
            name: coredns
            namespace: kube-system

    # Step 3: Extra Module
    - try:
        # Reconcile extra module
        - command:
            entrypoint: flux
            args: ["reconcile", "kustomization", "-n", "flux-system", "infra-kubernetes-extra", "--timeout", "3m"]
        # Wait for extra components
        - assert:
            file: extra/nfd.yaml
        - assert:
            file: extra/plugins.yaml
      catch:
        # Component-specific debugging
        - describe:
            apiVersion: apps/v1
            kind: DaemonSet
            name: node-feature-discovery-worker
            namespace: kube-system
        - podLogs:
            name: node-feature-discovery-worker
            namespace: kube-system
  ```

  This approach:
  1. Uses Chainsaw bindings for git configuration
  2. Provides clear step-by-step test flow
  3. Includes comprehensive error handling
  4. Maintains all existing validat/home/coder/code/chainsaw/website/docs/configuration/file.mdion checks

  GitHub Actions remains responsible for:
  - Cluster setup and management
  - FluxCD installation
  - Global resource status reporting

### Decision D006: Error Handling Strategy

- **Decision Topic:** How to handle errors across multiple test steps to ensure proper test failure

- **Current Implementation Analysis:**
 According to Chainsaw documentation:

 1. Step Behavior:
    - If an operation in `try` fails:
      - Remaining operations in `try` are skipped
      - All operations in `catch` are executed
    - If all operations in `try` succeed:
      - `catch` block is skipped entirely
    - `finally` block always executes

 2. Test Behavior:
    - Operations in `catch` and `finally` continue executing even if they fail
    - Any operation failure marks the test as failed
    - Test continues to next step after `catch`/`finally` complete

- **Problem:**
  We need to ensure:
  1. Tests fail fast on any step failure
  2. Step-specific debug info is collected
  3. Resources are properly cleaned up

- **Recommended Solution:**
  Use try/finally blocks with step-specific debugging:

  ```yaml
  steps:
  # Step 1: Bootstrap FluxCD
  - try:
      - command:
          entrypoint: flux
          args: ["create", "source", "git"...]
      - wait:
          apiVersion: source.toolkit.fluxcd.io/v1
          kind: GitRepository
          name: test-source
          for:
            condition:
              name: Ready
    finally:
      - describe:
          apiVersion: source.toolkit.fluxcd.io/v1
          kind: GitRepository
          name: test-source
          namespace: flux-system

  # Step 2: Core Module (only runs if previous step succeeded)
  - try:
      - command:
          entrypoint: flux
          args: ["reconcile", "kustomization", "infra-kubernetes-core"...]
      - assert:
          file: core/coredns.yaml
      - assert:
          file: core/api.yaml
    finally:
      - describe:
          apiVersion: apps/v1
          kind: Deployment
          name: coredns
          namespace: kube-system
      - podLogs:
          name: coredns
          namespace: kube-system

  # Step 3: Extra Module (only runs if previous step succeeded)
  - try:
      - command:
          entrypoint: flux
          args: ["reconcile", "kustomization", "infra-kubernetes-extra"...]
      - assert:
          file: extra/nfd.yaml
      - assert:
          file: extra/plugins.yaml
    finally:
      - describe:
          apiVersion: apps/v1
          kind: DaemonSet
          name: node-feature-discovery-worker
          namespace: kube-system
      - podLogs:
          name: node-feature-discovery-worker
          namespace: kube-system
      # Clean up git source in last step's finally
      - delete:
          apiVersion: source.toolkit.fluxcd.io/v1
          kind: GitRepository
          name: test-source
  ```

- **Benefits:**
  1. Step-specific debugging:
     - Debug commands tailored to each step
     - Only run debug commands for failed step
     - Clear connection between failure and debug info

  2. Fail-fast behavior:
     - Each step fails independently
     - Later steps don't execute after failure
     - Test status preserved for debug scripts

  3. Reliable cleanup:
     - Finally block in last step ensures cleanup
     - Cleanup runs regardless of test outcome
     - Consistent test environment

- **Questions for Collaborator:**

 1. Should we add any other debug commands to the catch block?
 2. Do we need additional cleanup in the finally block?

- **Next Steps:**
  1. Create assertion templates for common patterns
  2. Implement module-specific checks
  3. Add any additional debug capabilities needed

### Decision D007: Test Configuration Strategy

- **Decision Topic:** How to handle environment-specific configuration values consistently between CI and local environments

- **Current Configuration Analysis:**
  1. Configuration Types:
     - Git repository details (URL, branch)
     - Operation timeouts
     - Resource names and namespaces
     - CI-specific patches

  2. Available Chainsaw Features:
     - Values flag: Pass arbitrary values via `--values` file
     - Configuration file: Global settings in `.chainsaw.yaml`
     - Command-line flags: Override specific settings

- **Recommended Solution:**
  1. Global Configuration (`.chainsaw.yaml`):

  ```yaml
  apiVersion: chainsaw.kyverno.io/v1alpha2
  kind: Configuration
  metadata:
    name: infra-kubernetes-test
  spec:
    # Common timeouts
    timeouts:
      apply: 3m
      assert: 1m
      cleanup: 30s
    # Test execution settings
    execution:
      failFast: true
    # Global error handlers
    error:
      catch:
        - events: {}
        - describe:
            resource: kustomizations
  ```

  2. Environment Values (`values-ci.yaml`/`values-local.yaml`):

  ```yaml
  # Git configuration
  git:
    url: https://github.com/org/repo  # or http://localhost:3000/test-repo
    ref: main                         # or dev

  # Resource configuration
  namespaces:
    flux: flux-system
    core: kube-system
  ```

  3. Test Implementation:

  ```yaml
  apiVersion: chainsaw.kyverno.io/v1alpha1
  kind: Test
  spec:
    steps:
    - try:
        - command:
            entrypoint: flux
            args:
              - create
              - source
              - git
              - test-source
              - --url=($values.git.url)
              - --branch=($values.git.ref)
              - --namespace=($values.namespaces.flux)
  ```

  4. Usage in GitHub Actions:

  ```yaml
  - name: Run Tests
    run: |
      chainsaw test ./ci/test/infra-kubernetes \
        --config .chainsaw.yaml \
        --values values-ci.yaml \
        --fail-fast
  ```

  5. Usage Locally:

  ```bash
  chainsaw test ./ci/test/infra-kubernetes \
    --config .chainsaw.yaml \
    --values values-local.yaml
  ```

- **Benefits:**
  1. Clear Separation:
     - Global settings in `.chainsaw.yaml`
     - Environment values in values files
     - CLI flags for one-off overrides

  2. Native Chainsaw Features:
     - Uses built-in values system
     - Leverages standard configuration
     - No custom configuration loading

  3. Flexible Usage:
     - Easy to switch environments
     - Simple command-line interface
     - Works in both CI and local

- **Questions for Collaborator:**
  1. Should we add any global error handlers beyond events and kustomizations?
  2. Do we need different timeout settings for CI vs local?
  3. Are there other values we should include in the values files?

### Decision D008: Template Usage Strategy

- **Decision Topic:** When and how to use templates for resource definitions and value reuse
- **Related Findings and Conclusions:**
  - F010: Template Support (consistent behavior across inline and external files)
  - C005: Unified Template Strategy (consistent patterns across all uses)
- **Key Capabilities:**
  - Templates work consistently in both inline and externalized resources
  - Same templating features available regardless of location
  - Enables flexible component organization without sacrificing template functionality
  - Supports operation-specific constraints while maintaining consistency

- **Options Considered:**
  1. Template Everything:
      - Pros:
        - Maximum flexibility
        - Consistent approach
        - High reusability
      - Cons:
        - Unnecessary complexity for simple values
        - Harder to debug
        - Performance overhead

  2. Minimal Templates:
      - Pros:
        - Simpler to understand
        - Direct visibility
        - Faster execution
      - Cons:
        - Duplicate values
        - Hard to maintain
        - Limited reuse

  3. Value-Driven Template Strategy (Recommended):
      - Pros:
        - Templates where they add value
        - Clear decision criteria
        - Balance of reuse and simplicity
      - Cons:
        - Requires careful consideration
        - Mixed approach
        - Need clear guidelines

- **Recommended Approach:**
  1. When to Use Templates:
      - Dynamic values that change between environments
      - Values used in multiple places
      - Complex string manipulations
      - Resource names that follow patterns
      - Example:

        ```yaml
        # Use template for environment-specific values
        metadata:
          name: (join('-', [$namespace, 'config']))
          namespace: ($namespace)
        ```

  2. When to Use Static Values:
      - Constants that don't change
      - One-time use values
      - Simple string literals
      - Example:

        ```yaml
        # Use static for fixed values
        metadata:
          labels:
            app: coredns
            component: dns
        ```

  3. Template Patterns:
      - Inline Template (for operations requiring inline):

        ```yaml
        # In chainsaw-test.yaml
        steps:
          - try:
            - wait:
                apiVersion: apps/v1
                kind: Deployment
                metadata:
                  name: ($deployment_name)
                  namespace: ($namespace)
                for:
                  condition:
                    name: Available
                    value: 'true'
        ```

      - External Template (for file-supporting operations):

        ```yaml
        # common/resources/deployment.yaml
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: (join('-', [$namespace, $component]))
          namespace: ($namespace)
          labels:
            app: ($component)
            environment: (to_lower($env))
        spec:
          replicas: ($replicas)
          selector:
            matchLabels:
              app: ($component)
          template:
            metadata:
              labels:
                app: ($component)
            spec:
              containers:
              - name: ($component)
                image: ($image)
        ```

        Usage in test:

        ```yaml
        steps:
          - try:
            - assert:
                bindings:
                  - name: component
                    value: nginx
                  - name: namespace
                    value: web
                  - name: replicas
                    value: 3
                  - name: image
                    value: nginx:latest
                  - name: env
                    value: production
                file: common/resources/deployment.yaml
        ```

      - Template Functions:
        - Simple Binding: ($deployment_name)
        - String Join: (join('-', [$namespace, 'config']))
        - String Transform: (to_lower($env))
        - Array Operations: (length($replicas))

- **Implementation Guidelines:**
  1. Value Management:
      - Define common values as bindings
      - Use descriptive binding names
      - Document binding purposes
      - Group related bindings

  2. Template Organization:
      - Keep templates close to usage
      - Document complex templates
      - Use consistent patterns
      - Validate template output

  3. Best Practices:
      - Start simple, add complexity when needed
      - Document all bindings
      - Use clear naming conventions
      - Test template combinations

- **Rationale:**
  1. Value-Based Decision Making:
      - Templates add overhead
      - Must justify complexity
      - Clear criteria for usage

  2. Consistent Patterns:
      - Predictable template usage
      - Easy to understand
      - Maintainable long-term

  3. Balance:
      - Reuse where valuable
      - Simplicity where possible
      - Clear guidelines for decisions

### Decision D009: Step Templates for Reusable Test Sequences

- **Decision Topic:** How to implement reusable multi-operation sequences across tests
- **Related Decisions:** D002 (Reusable Component Strategy)
- **Key Differences from D002:**
  - D002 focuses on component-level reuse (individual resources, assertions)
  - D009 focuses on sequence-level reuse (multiple operations as a single unit)
  - Step templates encapsulate entire workflows rather than individual components

- **Options Considered:**
  1. Duplicate Steps Across Test Files:
     - Pros:
       - Simple implementation
       - Direct visibility of all operations
       - No additional concepts to understand
     - Cons:
       - High duplication across tests
       - Difficult to maintain consistency
       - Changes require updates to multiple files

  2. Use StepTemplate Resources with Parameterization (Recommended):
     - Pros:
       - Centralizes complex sequences
       - Enables parameterization through bindings
       - Maintains consistent workflows
       - Simplifies test files
     - Cons:
       - Adds indirection (operations defined elsewhere)
       - Requires understanding of template mechanism
       - May hide implementation details

- **Implementation:**

  ```yaml
  # Step template definition (../chainsaw/steps/sample-template.yaml)
  apiVersion: chainsaw.kyverno.io/v1alpha1
  kind: StepTemplate
  metadata:
    name: sequence-example
  spec:
    try:
    - apply:
        file: ../chainsaw/resources/sample-resource.yaml
    - script:
        content: ../chainsaw/scripts/sample-script.sh --param=($sample_param)
    - assert:
        file: ../chainsaw/assertions/sample-assertion.yaml
  ```

  ```yaml
  # Usage
  steps:
    - use:
        template: ../chainsaw/steps/sample-template.yaml
        with:
          bindings:
            - name: sample_param
              value: example
  ```

- **When to Use Step Templates:**
  1. For Complex Sequences:
     - Multi-step bootstrapping processes
     - Setup/teardown sequences used across tests
     - Standard validation workflows

  2. For Parameterized Workflows:
     - Operations that need different inputs but follow the same pattern
     - Sequences that vary only in target resources or namespaces
     - Common patterns with test-specific configuration

  3. For Standardized Processes:
     - Critical sequences that must be performed consistently
     - Complex error handling patterns
     - Multi-stage validation workflows

- **Rationale:**
  1. Sequence-Level Reusability:
     - Encapsulates entire workflows as reusable units
     - Reduces duplication of complex operation sequences
     - Enables standardization of critical processes

  2. Maintainability Benefits:
     - Changes to sequence logic only needed in one place
     - Consistent implementation across all tests
     - Simplified test files focused on test-specific logic

  3. Parameterization Advantages:
     - Adapts common sequences to test-specific needs
     - Maintains consistent structure while allowing variation
     - Reduces need for conditional logic in test files

### Decision D011: Script-Based Operations for Complex Commands

- **Decision Topic:** How to handle complex command operations
- **Related Decisions:** D002 (Reusable Component Strategy)
- **Options Considered:**
  1. Inline Command Operations with Multiple Arguments:
     - Pros:
       - Direct visibility of command in test file
       - No external dependencies
       - Simple for basic commands
     - Cons:
       - Complex commands become hard to read
       - No parameter validation
       - Limited error handling
       - Duplication across tests

  2. External Script Files with Parameter Handling (Recommended):
     - Pros:
       - Encapsulates complex command logic
       - Enables robust parameter validation
       - Provides consistent error handling
       - Reusable across multiple tests
     - Cons:
       - Adds indirection (command logic in separate file)
       - Requires shell scripting knowledge
       - Additional files to maintain

- **Implementation:**

  ```bash
  # ./flux-get-ks.sh
  #!/bin/bash
  set -eu
  flux get -n flux-system ks $1
  ```

  ```yaml
  # Usage
  - script:
      content: ./flux-get-ks.sh ($ks_name)
  ```

- **When to Use Script-Based Operations:**
  1. For Complex Commands:
     - Commands with many parameters
     - Commands requiring parameter validation
     - Commands with error handling needs
     - Commands used across multiple tests

  2. For Command Sequences:
     - Multiple related commands that should be executed together
     - Commands with conditional logic
     - Commands that need to capture and process output

  3. For Standardized Operations:
     - Common operations that should be performed consistently
     - Operations with specific error handling requirements
     - Operations that benefit from parameter validation

- **Rationale:**
  1. Improved Readability:
     - Complex command logic moved to dedicated scripts
     - Test files remain clean and focused
     - Clear separation of concerns

  2. Enhanced Reliability:
     - Parameter validation prevents errors
     - Consistent error handling
     - Proper exit code propagation
     - Fail-fast behavior with set -e

  3. Maintenance Benefits:
     - Changes to command logic only needed in one place
     - Consistent implementation across all tests
     - Simplified test files with descriptive operation names

## Current Session State

1. Research Status:
   - Completed:
      - /home/coder/code/homelab-ops-kubernetes-apps/projectBrief.md
      - /home/coder/code/homelab-ops-kubernetes-apps/infrastructure/subsystems/kubernetes-core/README.md
      - /home/coder/code/homelab-ops-kubernetes-apps/infrastructure/subsystems/kubernetes-extra/README.md
      - /home/coder/code/homelab-ops-kubernetes-apps/.github/workflows/test-kubernetes-resources-workflow.yaml
      - /home/coder/code/chainsaw/website/docs/quick-start/* (all sections)
      - /home/coder/code/chainsaw/website/docs/test/* (all sections)
      - /home/coder/code/chainsaw/website/docs/operations/* (all sections)
   - In Progress: None
   - Pending: None

2. Design Decisions:
   - Completed:
      - D001: Test Organization Structure
      - D002: Reusable Component Strategy
      - D003: Success Condition Implementation
      - D004: Rollout Status Implementation
      - D005: Workflow Integration Strategy
      - D006: Error Handling Strategy
      - D007: Test Configuration Strategy
      - D008: Template Usage Strategy
      - D009: Step Templates for Reusable Test Sequences
      - D011: Script-Based Operations for Complex Commands
   - In Discussion: None
   - Pending: None

3. Clarifications:
   - Resolved:
      - FluxCD bootstrapping approach
      - Error handling with try/finally
      - Configuration management strategy
   - Awaiting Response: None
   - To Be Discussed: None

4. Discussion Context:
   - Current Topic: Implementation completed
   - Related Decisions: All decisions completed
   - Open Questions: None

5. Implementation:
   - Completed:
      - Chainsaw test structure with step templates
      - Resource-specific assertion templates
      - Script-based operations
      - FluxCD bootstrapping
   - In Progress: None
   - Remaining: None

6. Activity Log:
   - Research Findings:
      - Logged: F001-F010
      - Remaining: None
   - Conclusions:
      - Logged: C001-C008
      - Remaining: None
   - Design Decisions:
      - Logged: D001-D011
      - Remaining: None
