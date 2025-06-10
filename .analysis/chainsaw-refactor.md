# Chainsaw Test Migration Tracker

## Migration Rationale and Benefits

### Why This Migration Was Necessary

**Problem with Original Architecture:**
The original chainsaw test structure used monolithic validation files that grouped multiple unrelated applications and services together. This created several significant problems:

1. **Poor Maintainability:** When a single service needed test updates, developers had to modify large files containing validations for completely unrelated services
2. **Unclear Failure Attribution:** Test failures were difficult to trace to specific components since multiple services were validated in single files
3. **Coupling of Unrelated Concerns:** Services like CoreDNS and Kubernetes API ingress were mixed together despite being functionally independent
4. **Difficult Debugging:** Pod logs and error handling were scattered across large files, making troubleshooting inefficient
5. **Inconsistent Structure:** No clear patterns for organizing tests, leading to ad-hoc file structures

### What We Achieved

**Component-Based Architecture:**
The migration transformed the test suite into a clean, component-based architecture where each service has its own focused validation file. This provides:

1. **Surgical Precision:** Developers can now update tests for individual services without touching unrelated code
2. **Clear Ownership:** Each validation file has a single responsibility, making it obvious which team or service owns each test
3. **Faster Debugging:** When tests fail, it's immediately clear which specific component is having issues
4. **Consistent Patterns:** Three clear patterns (A, B, C) provide predictable structure across all projects

**Enhanced Operational Benefits:**

- **Clearer CI/CD Feedback:** Test results clearly indicate which specific services are failing

## Migration Completion

**Total Projects Migrated:** 11 projects

- **Pattern A:** 4 projects (apps-ai, apps-downloaders, apps-media, apps-misc)
- **Pattern B:** 5 projects (infra-clusterops, infra-database, infra-kubernetes, infra-networking, infra-observability)
- **Pattern C:** 3 projects (apps-bitwarden, apps-coder, apps-harbor)

**Migration Status:** 100% Complete ✅

This migration tracker now serves as a historical record of the transformation from monolithic to component-based chainsaw test architecture, completed in June 2025.

## Migration Status

### ✅ MIGRATED (Already Done)

- [x] apps-home-automation (Pattern A - Multi-app, Single module)
- [x] infra-security (Pattern B - Multi-app, Multi-module)
- [x] infra-storage (Pattern B - Multi-app, Multi-module)

### 🔄 TO BE MIGRATED

#### Pattern A (Multi-app, Single module)

- [x] apps-ai (ollama + open-webui) ✅ COMPLETED
- [x] apps-downloaders (database + radarr + sabnzbd + sonarr + lidarr + overseerr + prowlarr + bazarr) ✅ COMPLETED
- [x] apps-media (freetube + plex + tautulli + jellyfin) ✅ COMPLETED
- [x] apps-misc (cert-manager + maddy) ✅ COMPLETED

#### Pattern B (Multi-app, Multi-module - Core/Extra)

- [x] infra-clusterops (flux + system-upgrade-controller + goldilocks + reloader) ✅ COMPLETED
- [x] infra-database (cloudnative-pg) ✅ COMPLETED
- [x] infra-kubernetes (coredns + node-feature-discovery + vpa + descheduler) ✅ COMPLETED
- [x] infra-networking (metallb + traefik + external-dns + pihole + unifi + freeradius) ✅ COMPLETED
- [x] infra-observability (prometheus + loki + grafana + event-exporter + node-problem-detector + snmp-exporter + syslog-ng + unifi-poller) ✅ COMPLETED

#### Pattern C (Single-app, Single module)

- [x] apps-bitwarden (bitwarden unified application) ✅ COMPLETED
- [x] apps-coder (coder application) ✅ COMPLETED
- [x] apps-harbor (harbor application) ✅ COMPLETED

## Migration Process Steps (Per Test)

### ⚠️ The One Critical Rule

**NEVER delete the original validation file until the migration is complete and verified.**

### Simple Process

1. **Read the original validation file first** - understand the exact order and content
2. **Create new component files** - split the validations as needed
3. **Update chainsaw-test.yaml** - add the new validation steps
4. **Verify everything works** - check that all validations are preserved
5. **Only then delete the original** - after confirming the migration is correct

### Quick Recovery

If you make a mistake and need the original content, ask the user to provide it rather than guessing or trying to reconstruct it from other files.

### 1. Pre-Migration Analysis

- [ ] List ALL files in directory using `list_files`
- [ ] Read original validation file to understand exact order and content
- [ ] Identify all components/services that need validation
- [ ] Classify pattern type (A, B, or C)
- [ ] Plan component split strategy
- [ ] Check for any special files (test-*.yaml, additional configs)

### 2. Migration Execution

- [ ] **Move reconciliation logic** from validation files to main `chainsaw-test.yaml`
- [ ] **Remove global namespace bindings** from validation files
- [ ] **Add individual namespace bindings** per assertion in new validation files
- [ ] **Split validation by component** into separate `validate-{component}.yaml` files
- [ ] **Update main chainsaw-test.yaml** to call individual validation templates
- [ ] **Ensure proper step sequencing**: Bootstrap → Apply → Reconcile → Validate
- [ ] **Preserve all original validation logic** (assertions, catch blocks, pod logs)
- [ ] **Follow naming conventions** for the specific pattern

### 3. Key Changes to Make

- [ ] **Reconciliation Movement**: Move `script` steps with `flux-reconcile.sh` from validation files to main test
- [ ] **Namespace Binding Approach**: Change from global to individual per assertion
- [ ] **Validation Structure**: Transform from monolithic to component-specific files
- [ ] **Step Organization**: Clear separation between orchestration and validation
- [ ] **Template Usage**: Each validation file becomes a `StepTemplate`

### 4. Verification Checklist

- [ ] All original files were examined and accounted for
- [ ] All validation assertions were preserved
- [ ] All catch blocks and error handling preserved
- [ ] All pod logs and debugging preserved
- [ ] Reconciliation properly moved to main test file
- [ ] File structure matches migrated examples
- [ ] Naming conventions followed correctly
- [ ] No validation logic was lost in the split

### 5. Migration Scope Verification

**CRITICAL: Verify ALL changes are ONLY in service of these goals:**

- [ ] **Structural refactor**: Split validation by component instead of grouping in 1 file
- [ ] **Naming conventions**: Consistent file names and chainsaw name/description elements
- [ ] **NO OTHER CHANGES**: No functional changes, no logic changes, no new features, no bug fixes
- [ ] **Pure refactor**: Only moving/splitting existing code, not modifying behavior
- [ ] **Preserve everything**: All timeouts, bindings, assertions, descriptions stay identical
- [ ] **No improvements**: Do not "improve" or "optimize" anything beyond the structural split

## Migration Rules by Pattern

### Pattern A Rules (Multi-app, Single module)

**Structure:** Single module containing multiple distinct applications
**Example:** apps-ai (ollama + open-webui), apps-home-automation (home-assistant + nanomq + piper + whisper + database)
**Migration:** Split by individual application/service
**Naming:** `validate-{app-name}.yaml` (e.g., `validate-ollama.yaml`, `validate-open-webui.yaml`)

### Pattern B (Multi-app, Multi-module)

**Structure:** Multiple modules (core/extra) each containing multiple applications
**Example:** infra-networking (core: metallb + traefik, extra: pihole + unifi + external-dns + freeradius)
**Migration:** Split by individual application, group by module if logical
**Naming:** `validate-{app-name}.yaml` (e.g., `validate-metallb.yaml`, `validate-traefik.yaml`, `validate-pihole.yaml`)

### Pattern C Rules (Single-app, Single module)

**Structure:** Single module containing one unified application (may have multiple workloads)
**Example:** apps-bitwarden (multiple bitwarden services but one logical app)
**Migration:** Split by logical service components within the app
**Naming:** `validate-{app-component}.yaml` (e.g., `validate-bitwarden-api.yaml`, `validate-bitwarden-web.yaml`)

## Naming Conventions

### File Names

- **Main test:** `chainsaw-test.yaml` (unchanged)
- **Module files:** `{module-name}.yaml` or `{module-name}-{core|extra}.yaml` (unchanged)
- **Validation files:** `validate-{component}.yaml`
  - Pattern A: `validate-{app-name}.yaml`
  - Pattern B: `validate-{app-name}.yaml`
  - Pattern C: `validate-{app-component}.yaml`

### Chainsaw Test Elements

- **Test name:** `{module-name}` (e.g., `apps-ai`, `infra-networking`)
- **Step names:**
  - `Bootstrap FluxCD`
  - `Apply {module-name} modules` or `Apply {module-name} module`
  - `Reconcile {module-name}` or `Reconcile {module-name}-{core|extra}`
  - `Validate {component-name}`
- **StepTemplate names:** `validate-{component}`
- **Descriptions:**
  - Apply: `Apply {module-name}` or `Apply {module-name}-{core|extra}`
  - Reconcile: `Reconcile kustomization/{module-name}` or `Reconcile kustomization/{module-name}-{core|extra}`
  - Validate: `Assert {resource-type}/{resource-name}`
