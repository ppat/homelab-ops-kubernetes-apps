#!/usr/bin/env node
// Layer A: closure over every scope-carrying site in the commit-emission machinery.
//
// Asserts that every commit header this repo's configuration CAN emit -- Renovate
// (all managers, all update types, over the package occupancy the repo actually has)
// and release-please (its pull-request-title-pattern) -- passes the repo's own
// commitlint config. The site list is derived MECHANICALLY by walking the resolved
// Renovate config closure (renovate.json -> extends -> local sub-configs + remote
// presets fetched at their pinned ref) and collecting every field that can place a
// type, scope or '!' into a header: semanticCommitScope, semanticCommitType,
// semanticCommits, commitMessagePrefix. There is no hand-maintained list of files
// or rules; adding a preset or a rule extends the closure automatically.
//
// Package occupancy is resolved from `git ls-files` (never a filesystem walk:
// .claude/worktrees/ can contain full checkouts), honouring each manager's
// managerFilePatterns and its *effective* ignorePaths. Occupancy is repo state:
// a new directory, a moved package or a new image can mint a new cell with no
// config change, which is why this runs per-commit in CI rather than once.
//
// What this closure is, and is not (stated per the design's own limits):
//   - It closes PER-UPGRADE resolution: (manager x packageFile x package x update
//     type) -> one rendered header, judged by commitlint itself (type, scope and
//     '!', not scope alone).
//   - It does NOT model branch-level aggregation (which upgrade's prefix a grouped
//     multi-upgrade branch emits). That is unbounded repo state; the merge-time
//     commitlint check is the gate there, and this script's guarantee for grouped
//     branches is only that every CANDIDATE prefix on such a branch is in-enum.
//   - Renovate built-in presets (":ignoreModulesAndTests" etc.) are not fetched;
//     they are Renovate-internal and carry no ppat scopes. The one whose semantics
//     matter here (:ignoreModulesAndTests' ignorePaths) is encoded as a constant
//     below, with its source cited.
//   - Subjects are synthesized ("update <dep> (1.0.0 -> 2.0.0)"); commitMessage
//     Action/Topic/Extra cannot place a scope or type (they render after the
//     prefix), so this loses nothing the check cares about.
//
// Usage:
//   node ci/scripts/verify-commit-taxonomy.mjs [--self-test] [--offline-presets DIR]
//
// --self-test injects known-bad synthetic cells and templates and exits non-zero
// unless every one of them is caught: a zero-defect result from a checker that
// cannot see an injected defect is vacuous, so CI runs this mode first.
// --offline-presets uses pre-downloaded preset files (dir containing <name>.json)
// instead of fetching from raw.githubusercontent.com.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const args = process.argv.slice(2);
const selfTest = args.includes('--self-test');
const offlineIdx = args.indexOf('--offline-presets');
const offlinePresets = offlineIdx >= 0 ? args[offlineIdx + 1] : null;
const dumpHeaders = args.includes('--dump-headers');

const failures = [];
const notes = [];
const fail = (msg) => failures.push(msg);
const note = (msg) => notes.push(msg);

// --- Renovate's :ignoreModulesAndTests, encoded (not fetched: it is an internal
// preset). Source: renovatebot/renovate lib/config/presets/internal/default.ts.
const IGNORE_MODULES_AND_TESTS = [
  '**/node_modules/**', '**/bower_components/**', '**/vendor/**', '**/examples/**',
  '**/__tests__/**', '**/test/**', '**/tests/**', '**/__fixtures__/**',
];

// All ten Renovate update types.
const UPDATE_TYPES = [
  'major', 'minor', 'patch', 'pin', 'pinDigest', 'digest',
  'lockFileMaintenance', 'rollback', 'bump', 'replacement',
];

// ---------------------------------------------------------------------------
// 1. Load the config closure, in extends order.
// ---------------------------------------------------------------------------

const fetchText = async (url) => {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${url}: HTTP ${res.status}`);
  return res.text();
};

async function loadClosure() {
  const configs = []; // { name, config }
  const skippedBuiltins = [];
  const queue = [{ ref: 'local://.github/renovate.json' }];
  while (queue.length) {
    const { ref } = queue.shift();
    let name, config;
    if (ref.startsWith('local://')) {
      name = ref.slice('local://'.length);
      config = JSON.parse(readFileSync(join(repoRoot, name), 'utf8'));
    } else if (ref.startsWith('github>')) {
      // github>owner/repo[//path/to/preset][:preset][#tag]
      const m = ref.match(/^github>([^/]+)\/([^/:#]+)(?:\/\/([^:#]+))?(?::([^#]+))?(?:#(.+))?$/);
      if (!m) throw new Error(`unparseable extends ref: ${ref}`);
      const [, owner, repo, path, preset, tag] = m;
      if (owner === 'ppat' && repo === 'homelab-ops-kubernetes-apps') {
        // this repo: read from the working tree so in-flight edits are what is checked
        let p = path ?? `${preset ?? 'default'}`;
        if (!p.endsWith('.json')) p += '.json';
        queue.unshift({ ref: `local://${p}` });
        continue;
      }
      const file = `${preset ?? 'default'}.json`;
      name = `${owner}/${repo}/${file}@${tag ?? 'HEAD'}`;
      if (offlinePresets) {
        config = JSON.parse(readFileSync(join(offlinePresets, file), 'utf8'));
      } else {
        if (!tag) throw new Error(`remote preset without a pinned tag: ${ref}`);
        config = JSON.parse(await fetchText(
          `https://raw.githubusercontent.com/${owner}/${repo}/${tag}/${file}`));
      }
    } else {
      // built-in / internal preset: not fetched (see header comment)
      skippedBuiltins.push(ref);
      continue;
    }
    for (const e of config.extends ?? []) queue.push({ ref: e });
    configs.push({ name, config });
  }
  // extends order semantics: an extended preset is resolved BEFORE the config that
  // extends it, so the extender's own fields win. Our BFS pushes parents first;
  // re-order so presets come before the config that named them, in listed order.
  // (renovate.json lists extends in priority order, later wins.)
  const root = configs.shift();
  configs.push(root);
  return { configs, skippedBuiltins };
}

// ---------------------------------------------------------------------------
// 2. Mechanical site enumeration + flattening.
// ---------------------------------------------------------------------------

const RELEVANT_FIELDS = ['semanticCommits', 'semanticCommitScope', 'semanticCommitType', 'commitMessagePrefix', 'commitBody', 'enabled'];
const SUPPORTED_MATCHERS = new Set([
  'matchManagers', 'matchPackageNames', 'matchFileNames', 'matchUpdateTypes',
  'matchDatasources', 'matchDepTypes',
]);

function flatten(configs) {
  const rootDefaults = {};
  const rules = [];
  const sites = []; // human-readable site list, for the report
  for (const { name, config } of configs) {
    for (const f of ['semanticCommits', 'semanticCommitScope', 'semanticCommitType']) {
      if (f in config) { rootDefaults[f] = config[f]; sites.push(`${name} (root): ${f}=${JSON.stringify(config[f])}`); }
    }
    for (const [i, rule] of (config.packageRules ?? []).entries()) {
      const relevant = RELEVANT_FIELDS.filter((f) => f in rule);
      const entry = { src: `${name}#${i}`, rule, relevant };
      rules.push(entry);
      for (const f of relevant) {
        if (f !== 'enabled') sites.push(`${name}#${i}: ${f}=${JSON.stringify(rule[f])}`);
      }
      if (relevant.length > 0) {
        for (const k of Object.keys(rule)) {
          if (k.startsWith('match') && !SUPPORTED_MATCHERS.has(k)) {
            fail(`${name}#${i}: unsupported matcher '${k}' on a rule carrying ${relevant.join('/')} -- extend the resolver before trusting this run`);
          }
        }
      }
    }
  }
  return { rootDefaults, rules, sites };
}

// ---------------------------------------------------------------------------
// 3. Template evaluation (the exact handlebars grammar these configs use).
// ---------------------------------------------------------------------------

function evalTemplate(tpl, { packageFileDir, updateType }, src) {
  let out = tpl;
  // {{#if (or isMajor isMinor)}}feat{{else if isPatch}}fix{{else}}chore{{/if}}
  out = out.replace(
    /\{\{#if \(or isMajor isMinor\)\}\}(.*?)\{\{else if isPatch\}\}(.*?)\{\{else\}\}(.*?)\{\{\/if\}\}/g,
    (_, a, b, c) => (updateType === 'major' || updateType === 'minor') ? a : (updateType === 'patch' ? b : c));
  // {{#if (equals (lookup (split packageFileDir '/') 0) 'apps')}}apps{{else}}infra{{/if}}
  out = out.replace(
    /\{\{#if \(equals \(lookup \(split packageFileDir '\/'\) (\d+)\) '([^']*)'\)\}\}(.*?)\{\{else\}\}(.*?)\{\{\/if\}\}/g,
    (_, idx, val, a, b) => ((packageFileDir.split('/')[Number(idx)] ?? '') === val ? a : b));
  // {{ lookup (split packageFileDir '/') N }} -- absent index renders '' (silently,
  // like handlebars; the resulting degenerate scope must then fail the lint)
  out = out.replace(
    /\{\{\s*lookup \(split packageFileDir '\/'\) (\d+)\s*\}\}/g,
    (_, idx) => packageFileDir.split('/')[Number(idx)] ?? '');
  if (/\{\{/.test(out)) {
    fail(`${src}: template uses handlebars this resolver does not implement: ${tpl}`);
    return null;
  }
  return out;
}

// ---------------------------------------------------------------------------
// 4. Matching primitives (the subset of Renovate semantics these configs use).
// ---------------------------------------------------------------------------

function globToRegex(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') { re += '.*'; i++; if (glob[i + 1] === '/') i++; }
      else re += '[^/]*';
    } else if ('.+?^${}()|[]\\'.includes(c)) re += '\\' + c;
    else re += c;
  }
  return new RegExp(`^${re}$`);
}

const matchesFileName = (file, patterns) =>
  patterns.some((p) => globToRegex(p).test(file) || (p.endsWith('/**') && file === p.slice(0, -3)));

function matchesPackageName(dep, patterns) {
  const positives = patterns.filter((p) => !p.startsWith('!'));
  const negatives = patterns.filter((p) => p.startsWith('!')).map((p) => p.slice(1));
  const one = (p) => {
    if (p.startsWith('/') && p.endsWith('/')) return new RegExp(p.slice(1, -1)).test(dep);
    if (p.includes('{/,}**')) { const base = p.split('{/,}**')[0]; return dep === base || dep.startsWith(base + '/'); }
    if (p.includes('*')) return globToRegex(p).test(dep);
    return dep === p;
  };
  if (positives.length && !positives.some(one)) return false;
  if (negatives.some(one)) return false;
  return true;
}

function ruleMatches(rule, cell) {
  if (rule.matchManagers && !rule.matchManagers.includes(cell.manager)) return false;
  if (rule.matchDatasources && !rule.matchDatasources.includes(cell.datasource)) return false;
  if (rule.matchUpdateTypes && !rule.matchUpdateTypes.includes(cell.updateType)) return false;
  if (rule.matchFileNames && !matchesFileName(cell.packageFile, rule.matchFileNames)) return false;
  if (rule.matchPackageNames && !matchesPackageName(cell.depName, rule.matchPackageNames)) return false;
  if (rule.matchDepTypes) return false; // no dep-type-bearing managers have occupancy here
  return true;
}

// ---------------------------------------------------------------------------
// 5. Package occupancy, from git ls-files.
// ---------------------------------------------------------------------------

function gitLsFiles() {
  return execFileSync('git', ['-C', repoRoot, 'ls-files', '-z'], { maxBuffer: 16 * 1024 * 1024 })
    .toString('utf8').split('\0').filter(Boolean);
}

const regexFromSlashes = (s) => {
  const m = s.match(/^\/(.*)\/$/);
  return m ? new RegExp(m[1]) : null;
};

function detectOccupancy(configs, allFiles) {
  const rootConfig = configs[configs.length - 1].config; // renovate.json
  const cells = []; // {manager, datasource, depName, packageFile}
  const add = (manager, datasource, depName, packageFile) =>
    cells.push({ manager, datasource, depName, packageFile });

  const managerFiles = (managerName, defaultPatterns) => {
    const managerCfg = rootConfig[managerName] ?? {};
    const patterns = (managerCfg.managerFilePatterns ?? defaultPatterns).map(regexFromSlashes);
    // manager-level ignorePaths REPLACES the global list for that manager
    // (non-mergeable option); otherwise :ignoreModulesAndTests applies.
    const ignore = managerCfg.ignorePaths ?? IGNORE_MODULES_AND_TESTS;
    return allFiles.filter((f) =>
      patterns.some((re) => re && re.test(f)) &&
      !ignore.some((g) => globToRegex(g).test(f) || f === g));
  };

  const readLines = (f) => {
    try { return readFileSync(join(repoRoot, f), 'utf8').split('\n'); } catch { return []; }
  };

  // kubernetes manager: image refs + apiVersions in k8s manifests
  const k8sDefault = ['/apps/.+\\.yaml$/', '/ci/.+\\.yaml$/', '/components/.+\\.yaml$/', '/infrastructure/.+\\.yaml$/'];
  let sawApiVersion = false;
  for (const f of managerFiles('kubernetes', k8sDefault)) {
    for (const line of readLines(f)) {
      const im = line.match(/^\s*(?:-\s+)?image:\s*["']?([^\s"']+)/);
      if (im) {
        const dep = im[1].split('@')[0].split(':')[0];
        if (dep && !dep.startsWith('{{')) add('kubernetes', 'docker', dep, f);
      }
      if (/^apiVersion:\s/.test(line)) sawApiVersion = true;
    }
  }
  if (sawApiVersion) {
    // the kubernetes manager also emits kubernetes-api datasource deps for
    // apiVersion fields; one representative cell covers the (path-independent)
    // literal prefix its rule carries
    add('kubernetes', 'kubernetes-api', 'networking.k8s.io/Ingress', 'infrastructure/subsystems/kubernetes-core/representative.yaml');
  }

  // flux manager: HelmRelease charts, OCIRepository refs, the flux toolkit itself
  const fluxDefault = k8sDefault;
  for (const f of managerFiles('flux', fluxDefault)) {
    const text = readLines(f);
    for (const line of text) {
      const cm = line.match(/^\s*chart:\s*["']?([A-Za-z0-9._/-]+)["']?\s*$/);
      if (cm) add('flux', 'helm', cm[1], f);
      const om = line.match(/^\s*url:\s*oci:\/\/([^\s"']+)/);
      if (om) add('flux', 'docker', om[1], f);
    }
    if (f.endsWith('flux/gotk-components.yaml') && text.some((l) => l.startsWith('# Flux Version:'))) {
      add('flux', 'github-releases', 'fluxcd/flux2', f);
    }
  }

  // custom.regex managers: the annotation grammars from custom-managers.json +
  // renovate.json (all share 'datasource=... depName=...')
  const regexDefault = ['/(^|/).+\\.ya?ml$/'];
  for (const f of managerFiles('regex', regexDefault)) {
    for (const line of readLines(f)) {
      const am = line.match(/#\s*renovate(?:-gh-release-asset|-gh-raw-url)?:\s*datasource=([a-z-.]+)\s+depName=([A-Za-z0-9-/.]+)/);
      if (am) add('custom.regex', am[1], am[2], f);
    }
  }

  // github-actions manager: uses: refs in workflows
  for (const f of allFiles.filter((x) => /^\.github\/workflows\/[^/]+\.ya?ml$/.test(x))) {
    for (const line of readLines(f)) {
      const um = line.match(/^\s*(?:-\s+)?uses:\s*["']?([A-Za-z0-9_.-]+\/[A-Za-z0-9_./-]+)@/);
      if (um) add('github-actions', 'github-tags', um[1].split('/').slice(0, 2).join('/'), f);
    }
  }

  // pre-commit manager
  if (allFiles.includes('.pre-commit-config.yaml')) {
    for (const line of readLines('.pre-commit-config.yaml')) {
      const rm = line.match(/^\s*-\s+repo:\s*https:\/\/github\.com\/(\S+)/);
      if (rm) add('pre-commit', 'github-tags', rm[1], '.pre-commit-config.yaml');
    }
  }

  // dedupe
  const seen = new Set();
  return cells.filter((c) => {
    const k = `${c.manager}|${c.datasource}|${c.depName}|${dirname(c.packageFile)}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

// ---------------------------------------------------------------------------
// 6. Per-cell resolution (B1, static): fold rules in order, last match wins.
// ---------------------------------------------------------------------------

function resolveCell(rootDefaults, rules, occ, updateType) {
  const cell = { ...occ, updateType, packageFileDir: dirname(occ.packageFile).replace(/^\.$/, '') };
  const eff = {
    enabled: true,
    semanticCommits: rootDefaults.semanticCommits ?? 'enabled',
    semanticCommitScope: rootDefaults.semanticCommitScope ?? 'deps',
    semanticCommitType: rootDefaults.semanticCommitType ?? 'chore',
    commitMessagePrefix: null,
    commitBody: null,
  };
  const applied = [];
  for (const { src, rule, relevant } of rules) {
    if (relevant.length === 0) continue;
    if (!ruleMatches(rule, cell)) continue;
    applied.push(src);
    for (const f of relevant) eff[f] = rule[f];
  }
  if (!eff.enabled) return { cell, header: null, applied, eff };
  let header;
  const subject = `update ${occ.depName} (1.0.0 -> 2.0.0)`;
  if (eff.commitMessagePrefix != null && eff.semanticCommits === 'disabled') {
    const prefix = evalTemplate(eff.commitMessagePrefix, cell, applied.join(','));
    if (prefix == null) return { cell, header: null, applied, eff };
    header = `${prefix} ${subject}`;
  } else {
    const scope = evalTemplate(String(eff.semanticCommitScope ?? ''), cell, applied.join(','));
    if (scope == null) return { cell, header: null, applied, eff };
    header = scope === '' ? `${eff.semanticCommitType}: ${subject}` : `${eff.semanticCommitType}(${scope}): ${subject}`;
  }
  return { cell, header, applied, eff };
}

// ---------------------------------------------------------------------------
// 6b. Calver classification + breaking-treatment predicate (Layer C).
//
// Calver-class = matched by any override-calver.json rule with matchUpdateTypes
// ignored. Ignoring that field is deliberate: the F5-era defect was matchUpdateTypes
// being (wrongly) added to those rules, and a classifier that consulted it would go
// blind to exactly that mutation. A calver "major" is a year rollover -- calver
// segments date the release, they do not signal API compatibility (calver.org) --
// so a calver-class cell must NEVER resolve with breaking treatment, for ANY
// update type. Non-calver majors of module-path packages must still resolve WITH
// breaking treatment ('!' or a BREAKING CHANGE body).
// ---------------------------------------------------------------------------

function isCalverCell(rules, occ) {
  return rules.some(({ src, rule }) => {
    if (!src.includes('override-calver')) return false;
    const rest = { ...rule };
    delete rest.matchUpdateTypes;
    return ruleMatches(rest, { ...occ, updateType: 'major', packageFileDir: dirname(occ.packageFile).replace(/^\.$/, '') });
  });
}

function breakingTreatmentFault(rules, occ, updateType, header, eff, applied = []) {
  const bang = /^\w+(\([^)]*\))?!:/.test(header);
  const breakingBody = String(eff.commitBody ?? '').includes('BREAKING CHANGE');
  const prov = `${occ.manager}:${occ.depName}@${dirname(occ.packageFile)} [${updateType}] via ${applied.join(',')}`;
  if (isCalverCell(rules, occ)) {
    if (bang || breakingBody) {
      return `calver-class package resolves WITH breaking treatment (a calver major is a year rollover, not an API break; override-calver must win for every update type):\n    ${header}\n    ${prov}`;
    }
    return null;
  }
  if (updateType === 'major' &&
      /^(apps\/subsystems|infrastructure\/subsystems|infrastructure\/bootstrap\/crds)\//.test(occ.packageFile) &&
      !bang && !breakingBody) {
    return `major update of a module-path package resolves without breaking treatment (no '!' and no BREAKING CHANGE body):\n    ${header}\n    ${prov}`;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 7. Judgement: every rendered header through commitlint itself (type, scope
//    and '!', not a scope set-membership test).
// ---------------------------------------------------------------------------

async function makeLinter() {
  const { default: load } = await import('@commitlint/load');
  const { default: lint } = await import('@commitlint/lint');
  const opts = await load({}, { cwd: repoRoot });
  return async (header) => {
    const r = await lint(header, opts.rules,
      opts.parserPreset ? { parserOpts: opts.parserPreset.parserOpts, plugins: opts.plugins } : { plugins: opts.plugins });
    return r;
  };
}

// ---------------------------------------------------------------------------
// 8. release-please: the one scope-carrying site outside Renovate. From E2 on
//    its rendered titles must pass the required check or releases stop.
// ---------------------------------------------------------------------------

function releasePleaseHeaders() {
  const cfg = JSON.parse(readFileSync(join(repoRoot, 'release-please-config.json'), 'utf8'));
  const pattern = cfg['pull-request-title-pattern'];
  if (!pattern) { fail('release-please-config.json: no pull-request-title-pattern found'); return []; }
  const components = Object.values(cfg.packages ?? {}).map((p) => p.component ?? '');
  return components.map((c) =>
    pattern.replaceAll('${component}', c ? ` ${c}` : '').replaceAll('${version}', '0.0.1'));
}

// ---------------------------------------------------------------------------
// Self-test: inject defects; a checker that cannot see them proves nothing.
// ---------------------------------------------------------------------------

async function runSelfTest(lintHeader, rootDefaults, rules) {
  const injected = [
    ['feat(infra-crds)!: update longhorn (1.8.0 -> 1.9.0)', 'off-enum scope (the F6a live defect shape)'],
    ['feat(infra-)!: update fluxcd/flux2 (2.3.0 -> 2.4.0)', 'degenerate empty-segment render (F6b shape)'],
    ['chore(apps-ai)!: breaking chore (the cell-19 shape)', "'!' on a non-shipped type"],
    ['feat(internal-workflows): shipped type on internal scope', 'pairing violation'],
    ['style: address markdown linting errors', 'removed type'],
  ];
  let caught = 0;
  for (const [header, why] of injected) {
    const r = await lintHeader(header);
    if (r.valid) fail(`SELF-TEST: injected defect NOT caught (${why}): ${header}`);
    else caught++;
  }
  // resolution-stage injection: a calver-class package planted on a ci/test path
  // must render an off-enum doubled scope and be caught end to end
  const synthetic = { manager: 'kubernetes', datasource: 'docker', depName: 'visibilityspots/cloudflared', packageFile: 'ci/test/infra-networking/injected.yaml' };
  const { header } = resolveCell(rootDefaults, rules, synthetic, 'minor');
  if (!header) fail('SELF-TEST: synthetic ci/test cloudflared cell resolved to no emission -- resolver defect');
  else {
    const r = await lintHeader(header);
    if (r.valid) fail(`SELF-TEST: synthetic ci/test calver cell passed the lint but must not: ${header}`);
    else { caught++; note(`self-test: synthetic ci/test calver cell rendered '${header}' and was caught`); }
  }
  // breaking-treatment injections (the F5-era defect, both directions):
  // (a) re-apply the reverted PR #3795 mutation -- matchUpdateTypes excluding
  //     major on the override-calver rules. A calver major then falls through to
  //     override-breaking-changes, resolves as feat(<scope>)!: + BREAKING CHANGE,
  //     and the calver falsifier must catch it (classification ignores
  //     matchUpdateTypes precisely so this mutation cannot blind it).
  const authentikOcc = { manager: 'flux', datasource: 'helm', depName: 'authentik', packageFile: 'infrastructure/subsystems/security-extra/authentik/helm-release-authentik.yaml' };
  const mutated = rules.map((e) => e.src.includes('override-calver')
    ? { ...e, rule: { ...e.rule, matchUpdateTypes: UPDATE_TYPES.filter((t) => t !== 'major') } }
    : e);
  const maj = resolveCell(rootDefaults, mutated, authentikOcc, 'major');
  if (!maj.header) fail('SELF-TEST: mutated authentik major cell resolved to no emission -- resolver defect');
  else if (!breakingTreatmentFault(mutated, authentikOcc, 'major', maj.header, maj.eff, maj.applied)) {
    fail(`SELF-TEST: calver major resolving with breaking treatment was NOT caught: ${maj.header}`);
  } else { caught++; note(`self-test: matchUpdateTypes-excluding-major mutation rendered '${maj.header}' and was caught`); }
  // (b) the non-calver direction is unchanged: a module-path major resolving
  //     without '!' or a BREAKING CHANGE body must still be flagged.
  const longhornOcc = { manager: 'flux', datasource: 'helm', depName: 'longhorn', packageFile: 'infrastructure/subsystems/storage-core/longhorn/helm-release-longhorn.yaml' };
  if (!breakingTreatmentFault(rules, longhornOcc, 'major', 'feat(infra-storage-core): update longhorn (1.8.0 -> 2.0.0)', { commitBody: '' }, ['synthetic'])) {
    fail('SELF-TEST: non-calver module-path major without breaking treatment was NOT caught');
  } else caught++;
  // template-grammar injection: unknown handlebars must fail loudly, not render
  const before = failures.length;
  evalTemplate('{{#unless isMajor}}x{{/unless}}', { packageFileDir: 'a/b/c', updateType: 'minor' }, 'self-test');
  if (failures.length === before) fail('SELF-TEST: unknown handlebars construct was NOT rejected');
  else { failures.pop(); caught++; }
  return caught;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

const { configs, skippedBuiltins } = await loadClosure();
const { rootDefaults, rules, sites } = flatten(configs);
const lintHeader = await makeLinter();

console.log(`config closure: ${configs.map((c) => c.name).join(', ')}`);
console.log(`skipped built-in presets (Renovate-internal, carry no ppat scopes): ${skippedBuiltins.join(', ')}`);
console.log(`scope/type-carrying sites found mechanically: ${sites.length}`);
for (const s of sites) console.log(`  site: ${s}`);

if (selfTest) {
  const caught = await runSelfTest(lintHeader, rootDefaults, rules);
  if (failures.length) {
    console.error('\nSELF-TEST FAILURES:');
    for (const f of failures) console.error(`  ${f}`);
    process.exit(1);
  }
  console.log(`\nself-test: all ${caught} injected defects caught`);
  process.exit(0);
}

// Layer C falsifier (F12 regression): an enabled:false rule that enumerates
// matchUpdateTypes silently re-enables the package for any type it forgot
// (replacement/rollback/bump reached override-calver with automerge on).
for (const { src, rule } of rules) {
  if (rule.enabled === false && Array.isArray(rule.matchUpdateTypes)) {
    fail(`${src}: enabled:false rule enumerates matchUpdateTypes -- a novel or omitted update type falls through and re-enables the package; disable rules must match all types`);
  }
}

const allFiles = gitLsFiles();
const occupancy = detectOccupancy(configs, allFiles);
console.log(`package occupancy: ${occupancy.length} (manager, package, dir) sites from ${allFiles.length} tracked files`);

const headers = new Map(); // header -> one representative provenance
let disabledCells = 0;
for (const occ of occupancy) {
  for (const updateType of UPDATE_TYPES) {
    const { header, applied, eff } = resolveCell(rootDefaults, rules, occ, updateType);
    if (header == null) { disabledCells++; continue; }
    if (!headers.has(header)) headers.set(header, `${occ.manager}:${occ.depName}@${dirname(occ.packageFile)} [${updateType}] via ${applied.join(',') || 'root defaults'}`);
    // Layer C falsifier (breaking-treatment class, both directions -- see 6b):
    // calver-class cells must never resolve breaking; non-calver module-path
    // majors must always resolve breaking.
    const fault = breakingTreatmentFault(rules, occ, updateType, header, eff, applied);
    if (fault) fail(fault);
  }
}
for (const h of releasePleaseHeaders()) {
  if (!headers.has(h)) headers.set(h, 'release-please pull-request-title-pattern');
}

console.log(`distinct candidate headers: ${headers.size} (${disabledCells} cells disabled by rule)`);
if (dumpHeaders) {
  for (const [h, prov] of [...headers.entries()].sort()) console.log(`  header: ${h}\n    from: ${prov}`);
}
let bad = 0;
for (const [header, prov] of headers) {
  const r = await lintHeader(header);
  if (!r.valid) {
    bad++;
    fail(`emittable header fails the repo's own commitlint:\n    ${header}\n    provenance: ${prov}\n    ${r.errors.map((e) => `${e.name}: ${e.message}`).join('; ')}`);
  }
}

for (const n of notes) console.log(`note: ${n}`);
if (failures.length) {
  console.error(`\nFAIL: ${failures.length} problem(s)`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`\nOK: all ${headers.size} distinct emittable headers pass commitlint (${bad} failures)`);
console.log('limits: branch-level aggregation (grouped PR prefix selection) is not modeled here;');
console.log('the required merge-time commitlint check is the gate for that. Subjects are synthesized.');
