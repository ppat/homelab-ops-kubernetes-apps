#!/usr/bin/env node
// Emission-closure check for the commit taxonomy.  See ./README.md for how to
// maintain this script; .claude/rules/commits.md for the taxonomy it defends.
//
// WHY THIS EXISTS
// ---------------
// Nothing this repository can emit automatically may be a commit header its own
// commitlint config would reject.  Renovate and release-please compile headers
// from configuration; commitlint only ever sees headers that already exist.  So
// there is no natural moment at which the two are compared -- a config that can
// emit an out-of-enum scope stays green until the bot actually opens that PR,
// which may be months later and on someone else's schedule.  This script closes
// that gap by generating the emittable set and linting it.
//
// The most common way the gap opens is NOT a bad edit to commitlint.config.js.
// It is adding a module or a component and forgetting to update
// commitlint.config.js + release-please-config.json, because the Renovate scopes
// are TEMPLATED ("apps-{{dir}}"): the set of headers the config can emit is a
// function of repo state, so a new directory with a manifest in it mints a new
// scope with no config edit anywhere and nothing for commitlint to catch.
// Renaming or moving a package does the same in reverse.
//
// WHAT IT ASSERTS
// ---------------
// Every commit header this repo's configuration CAN emit -- Renovate (all
// managers, all update types, over the package occupancy the repo actually has)
// and release-please (its pull-request-title-pattern) -- passes the repo's own
// commitlint config.  The scope-carrying site list is derived MECHANICALLY by
// walking the resolved Renovate config closure (renovate.json -> extends ->
// local sub-configs + remote presets fetched at their pinned ref) and collecting
// every field that can place a type, scope or '!' into a header:
// semanticCommitScope, semanticCommitType, semanticCommits, commitMessagePrefix.
// There is no hand-maintained list of files or rules; adding a preset or a rule
// extends the closure automatically.
//
// Package occupancy is resolved from `git ls-files` (never a filesystem walk:
// .claude/worktrees/ can contain full checkouts), honouring each manager's
// managerFilePatterns and its *effective* ignorePaths.  Occupancy is repo state:
// a new directory, a moved package or a new image can mint a new cell with no
// config change, which is why this runs per-commit in CI rather than once, and
// why the CI job is deliberately NOT path-gated -- gating it on the config files
// would skip exactly the case it exists to catch.
//
// WHAT IT DOES NOT ASSERT
//   - It closes PER-UPGRADE resolution: (manager x packageFile x package x update
//     type) -> one rendered header, judged by commitlint itself (type, scope and
//     '!', not scope alone).
//   - It does NOT model branch-level aggregation (which upgrade's prefix a grouped
//     multi-upgrade branch emits).  That is unbounded repo state; the merge-time
//     commitlint check is the gate there, and this script's guarantee for grouped
//     branches is only that every CANDIDATE prefix on such a branch is in-enum.
//   - It does not model every Renovate manager.  Occupancy is enumerated only for
//     the managers that have packages here (see detectOccupancy); notably the
//     kustomize manager is not modelled.  An unmodelled manager is a silent
//     coverage gap, not a failure -- adding one is a README-documented task.
//   - Renovate built-in presets (":ignoreModulesAndTests" etc.) are not fetched;
//     they are Renovate-internal and carry no ppat scopes.  The only semantics that
//     matter here are the ones that set ignorePaths; those are encoded below with
//     their source cited, and WHICH of them applies is read off the closure's
//     extends lists rather than assumed -- so removing (or re-adding) such a preset
//     moves package occupancy here exactly as it moves it in Renovate.
//   - Subjects are synthesized ("update <dep> (1.0.0 -> 2.0.0)"); commitMessage
//     Action/Topic/Extra cannot place a scope or type (they render after the
//     prefix), so this loses nothing the check cares about.
//   - Where it cannot model a construct it FAILS rather than guesses: an unknown
//     handlebars helper, an unsupported match* key on a scope-carrying rule, or a
//     brace-expansion glob outside the one idiom implemented below.
//
// Usage:
//   node ci/scripts/commit-taxonomy/verify-commit-taxonomy.mjs \
//        [--self-test] [--dump-headers] [--offline-presets DIR]
//
// --self-test injects known-bad synthetic cells and templates and exits non-zero
// unless every one of them is caught: a zero-defect result from a checker that
// cannot see an injected defect is vacuous, so CI runs this mode first.
// --dump-headers prints every candidate header with its provenance.
// --offline-presets uses pre-downloaded preset files (dir containing <name>.json)
// instead of fetching from raw.githubusercontent.com. The live fetch carries a
// per-attempt timeout and retries transient failures (network errors, timeouts,
// 5xx, 429) with backoff; a 404 is terminal and fails on the first attempt,
// because at a pinned ref it means the pin, the preset name, or the file is
// wrong -- the very conditions the check exists to catch.

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Repo root from git, not from this file's depth: the script has moved once already
// and a hardcoded '../..' is the kind of assumption that breaks on the next move.
const repoRoot = execFileSync('git', ['-C', dirname(fileURLToPath(import.meta.url)),
  'rev-parse', '--show-toplevel']).toString().trim();
const args = process.argv.slice(2);
const selfTest = args.includes('--self-test');
const offlineIdx = args.indexOf('--offline-presets');
const offlinePresets = offlineIdx >= 0 ? args[offlineIdx + 1] : null;
const dumpHeaders = args.includes('--dump-headers');

const failures = [];
const notes = [];
const fail = (msg) => failures.push(msg);
const note = (msg) => notes.push(msg);

// --- Global `ignorePaths`. Renovate's built-in default, plus the internal presets
// that replace it (ignorePaths is non-mergeable, so a preset REPLACES, never adds).
// Internal presets ship inside Renovate and are not fetched, so the ones that matter
// are encoded here; WHICH of them applies is derived from the resolved closure's
// extends lists (see globalIgnorePaths), never assumed -- dropping
// ':ignoreModulesAndTests' from extends must move occupancy, and it does.
// Source: renovatebot/renovate lib/config/presets/internal/{default,config}.ts and
// lib/config/options/index.ts (ignorePaths: mergeable false, default as below).
const RENOVATE_DEFAULT_IGNORE_PATHS = ['**/node_modules/**', '**/bower_components/**'];
const IGNORE_MODULES_AND_TESTS = [
  '**/node_modules/**', '**/bower_components/**', '**/vendor/**', '**/examples/**',
  '**/__tests__/**', '**/test/**', '**/tests/**', '**/__fixtures__/**',
];
// config:* all extend :ignoreModulesAndTests transitively, so re-adding any of them
// would silently restore the eight globs; they are listed so that cannot go unseen.
const IGNORE_PATHS_BY_BUILTIN = new Map([
  [':ignoreModulesAndTests', IGNORE_MODULES_AND_TESTS],
  ['config:recommended', IGNORE_MODULES_AND_TESTS],
  ['config:best-practices', IGNORE_MODULES_AND_TESTS],
  ['config:js-app', IGNORE_MODULES_AND_TESTS],
  ['config:js-lib', IGNORE_MODULES_AND_TESTS],
  [':includeNodeModules', []],
]);

// Effective global ignorePaths for this repo, from the closure that was actually
// resolved: built-in default, then each built-in preset named in an extends list,
// then any config in the closure that sets a top-level ignorePaths. Every step
// REPLACES, because the option is non-mergeable.
function globalIgnorePaths(configs, builtins) {
  let ignore = RENOVATE_DEFAULT_IGNORE_PATHS;
  for (const b of builtins) if (IGNORE_PATHS_BY_BUILTIN.has(b)) ignore = IGNORE_PATHS_BY_BUILTIN.get(b);
  for (const { config } of configs) if (config.ignorePaths) ignore = config.ignorePaths;
  return ignore;
}

// All ten Renovate update types.
const UPDATE_TYPES = [
  'major', 'minor', 'patch', 'pin', 'pinDigest', 'digest',
  'lockFileMaintenance', 'rollback', 'bump', 'replacement',
];

// ---------------------------------------------------------------------------
// 1. Load the config closure, in extends order.
// ---------------------------------------------------------------------------

// Preset resolution is this script's only network access, and it rides on
// someone else's CDN. A transient blip there must cost seconds, not a red
// check -- so transient failures (network errors, per-attempt timeouts, 5xx,
// 429) are retried with backoff, bounded far below the CI job's timeout.
// Terminal failures are NOT retried: a 404 at the pinned ref means the pin is
// wrong, the preset was renamed, or the file does not exist at that tag --
// exactly the conditions this check exists to catch at a preset bump, and
// retrying them would make a real configuration error look like flakiness.
// (A JSON parse failure at the call site is terminal the same way: the fetch
// already succeeded, so the body itself is what is wrong.) The stub-injection
// points exist for the self-test, which falsifies both directions of the
// classification; production callers pass only the url.
const FETCH_TIMEOUT_MS = 10_000;
const FETCH_BACKOFF_MS = [1000, 2000]; // attempts = backoffs + 1
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const fetchText = async (url, { fetchImpl = fetch, backoffMs = FETCH_BACKOFF_MS } = {}) => {
  for (let attempt = 1; ; attempt++) {
    let res, failure;
    try {
      res = await fetchImpl(url, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
    } catch (e) {
      failure = e.message; // network unreachable or per-attempt timeout: transient
    }
    if (res) {
      if (res.ok) return res.text();
      if (res.status !== 429 && res.status < 500) {
        throw new Error(`fetch ${url}: HTTP ${res.status} (terminal after ${attempt} attempt(s), not retried)`);
      }
      failure = `HTTP ${res.status}`;
    }
    if (attempt > backoffMs.length) throw new Error(`fetch ${url}: ${failure} (gave up after ${attempt} attempts)`);
    console.log(`fetch ${url}: ${failure} -- transient, retrying (attempt ${attempt} of ${backoffMs.length + 1})`);
    await sleep(backoffMs[attempt - 1]);
  }
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
        // Brace expansion: Renovate's matcher is minimatch, which expands '{a,b}';
        // the primitives below model exactly one brace form, the '<name>{/,}**'
        // idiom, and treat every other '{' literally. A pattern this resolver reads
        // literally and Renovate expands would resolve the cell differently here
        // than in production, and would do so silently -- the same silent-mismatch
        // class this check exists to close. Fail rather than guess.
        for (const k of ['matchPackageNames', 'matchFileNames']) {
          for (const pat of rule[k] ?? []) {
            if (pat.includes('{') && !pat.endsWith('{/,}**')) {
              fail(`${name}#${i}: ${k} pattern '${pat}' uses brace expansion this resolver does not model (only the '<name>{/,}**' idiom is) -- extend matchesPackageName/globToRegex before trusting this run`);
            }
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

function evalTemplate(tpl, { packageFileDir, updateType, semanticCommitType, semanticCommitScope }, src) {
  let out = tpl;
  // {{semanticCommitType}}{{#if semanticCommitScope}}({{semanticCommitScope}}){{/if}}!:
  // -- the breaking-marker prefix ppat/renovate-presets sets on its major rule.
  // Renovate exposes semanticCommitType/semanticCommitScope to templates
  // (util/template/index.ts exposedConfigOptions) and compiles commitMessage three
  // times with noEscape, so a scope that is ITSELF a template resolves on a later
  // pass; that is why the caller passes the already-resolved scope in here.
  out = out.replace(
    /\{\{#if semanticCommitScope\}\}(.*?)\{\{\/if\}\}/g,
    (_, a) => (semanticCommitScope ? a : ''));
  out = out.replace(/\{\{semanticCommitType\}\}/g, () => semanticCommitType ?? '');
  out = out.replace(/\{\{semanticCommitScope\}\}/g, () => semanticCommitScope ?? '');
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
  // depType is set only by managers that have one (npm/bun read it off the
  // package.json section a dependency sits in). A cell with no depType cannot
  // match a matchDepTypes rule, which is also how Renovate behaves.
  if (rule.matchDepTypes && !rule.matchDepTypes.includes(cell.depType)) return false;
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

function detectOccupancy(configs, allFiles, builtins) {
  const rootConfig = configs[configs.length - 1].config; // renovate.json
  const globalIgnore = globalIgnorePaths(configs, builtins);
  const cells = []; // {manager, datasource, depName, packageFile, depType?}
  const add = (manager, datasource, depName, packageFile, depType) =>
    cells.push({ manager, datasource, depName, packageFile, depType });

  const managerFiles = (managerName, defaultPatterns) => {
    const managerCfg = rootConfig[managerName] ?? {};
    const patterns = (managerCfg.managerFilePatterns ?? defaultPatterns).map(regexFromSlashes);
    // manager-level ignorePaths REPLACES the global list for that manager
    // (non-mergeable option); otherwise the global list applies.
    const ignore = managerCfg.ignorePaths ?? globalIgnore;
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

  // custom.regex managers: the annotation grammars from custom-managers.json
  // (all share 'datasource=... depName=...')
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

  // npm/bun managers: the repo's own toolchain manifest. Modelled under BOTH
  // manager names on purpose -- which one claims a package.json depends on
  // whether a bun lockfile sits beside it, and the answer is Renovate-version
  // dependent. Both resolve identically here (the shared dev-tools preset lists
  // both in matchManagers), so covering both is free and cannot go stale.
  // depType is carried because the scope-setting rule matches on it: packages in
  // devDependencies are internal tooling, packages in dependencies are not, and
  // moving one between sections changes the header the bot emits.
  for (const f of allFiles.filter((x) => /(^|\/)package\.json$/.test(x))) {
    let pkg;
    try { pkg = JSON.parse(readFileSync(join(repoRoot, f), 'utf8')); } catch { continue; }
    const hasBunLock = allFiles.includes(join(dirname(f), 'bun.lock').replace(/^\.\//, '')) ||
      allFiles.includes(join(dirname(f), 'bun.lockb').replace(/^\.\//, ''));
    const managers = hasBunLock ? ['npm', 'bun'] : ['npm'];
    for (const depType of ['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies']) {
      for (const dep of Object.keys(pkg[depType] ?? {})) {
        for (const m of managers) add(m, 'npm', dep, f, depType);
      }
    }
  }

  // renovate-config manager: Renovate manages this repo's OWN preset pins. Every
  // pinned `github>owner/repo#tag` in .github/renovate.json's extends is a
  // github-tags dep it can bump, which is how the shared-preset pin moves without
  // anyone typing it (observed live: each pinned ppat/renovate-presets ref is
  // such a dep, offering minor and major). The unpinned local refs
  // (github>ppat/homelab-ops-kubernetes-apps//...) extract with skipReason
  // 'unspecified-version' and yield no update, so they are not cells.
  for (const f of allFiles.filter((x) => /^(\.github\/)?renovate\.json5?$|^\.renovaterc(\.json5?)?$/.test(x))) {
    for (const line of readLines(f)) {
      const pm = line.match(/["']github>([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)(?::[A-Za-z0-9_.-]+)?#/);
      if (pm) add('renovate-config', 'github-tags', pm[1], f);
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
    const k = `${c.manager}|${c.datasource}|${c.depName}|${c.depType ?? ''}|${dirname(c.packageFile)}`;
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
  // Renovate builds the semantic prefix ONLY when no commitMessagePrefix is in
  // effect: `if (semanticCommits === 'enabled' && !commitMessagePrefix)` in
  // renovatebot/renovate lib/workers/repository/updates/generate.ts. So an explicit
  // prefix wins whether or not semanticCommits is disabled alongside it. This IS
  // load-bearing at the current pin: ppat/renovate-presets' major rule sets the
  // breaking-marker prefix WITHOUT disabling semantic commits, so this condition is
  // what decides whether '!' appears on every major in the repo.
  const scope = evalTemplate(String(eff.semanticCommitScope ?? ''), cell, applied.join(','));
  if (scope == null) return { cell, header: null, applied, eff };
  // Renovate treats an EMPTY prefix as no prefix: the semantic branch is guarded by
  // `!config.commitMessagePrefix`, so '' and null take the same path. Modelling ''
  // as a prefix would render a header with a leading space and no type at all.
  if (eff.commitMessagePrefix) {
    const prefix = evalTemplate(eff.commitMessagePrefix,
      { ...cell, semanticCommitType: eff.semanticCommitType, semanticCommitScope: scope },
      applied.join(','));
    if (prefix == null) return { cell, header: null, applied, eff };
    header = `${prefix} ${subject}`;
  } else {
    header = scope === '' ? `${eff.semanticCommitType}: ${subject}` : `${eff.semanticCommitType}(${scope}): ${subject}`;
  }
  return { cell, header, applied, eff };
}

// ---------------------------------------------------------------------------
// 6b. Calver classification + breaking-treatment predicate.
//
// Calver-class = matched by any override-calver.json rule with matchUpdateTypes
// ignored. Ignoring that field is deliberate: the defect this predicate exists to
// catch IS matchUpdateTypes being (wrongly) added to those rules, and a classifier
// that consulted it would go blind to exactly that mutation. A calver "major" is a year rollover -- calver
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
// 6c. Unscoped-module falsifier. A module-path cell losing its scope is SILENT:
// the shared preset's breaking-marker template guards the scope segment
// ('{{#if semanticCommitScope}}({{semanticCommitScope}}){{/if}}!:'), and the
// per-update-type defaults render 'feat:'/'fix:' when the scope is empty -- all
// in-enum, all untrue (the empty scope means 'spans modules or belongs to
// none', which a single-module dependency bump never does). commitlint cannot
// object, so this predicate does. No config spelling ever made this loud: the
// local majors rule deleted when the preset took over module-path majors was
// deliberately unguarded so a missing scope would render 'feat()!:', believed
// off-enum -- MEASURED FALSE 2026-08: commitlint parses empty parens as no
// scope and accepts 'feat()!:' and 'feat():' here, so the loudness that rule
// claimed to provide never existed. This predicate is the first real guard for
// the class, and it covers every rule and update type rather than one rule's
// majors.
// ---------------------------------------------------------------------------

function unscopedModuleFault(occ, updateType, header, applied = []) {
  if (!/^(apps\/subsystems|infrastructure\/subsystems|infrastructure\/bootstrap\/crds)\//.test(occ.packageFile)) return null;
  if (/^\w+\([^)]+\)!?:/.test(header)) return null;
  const prov = `${occ.manager}:${occ.depName}@${dirname(occ.packageFile)} [${updateType}] via ${applied.join(',')}`;
  return `module-path cell resolves to an UNSCOPED header (in-enum, so commitlint cannot catch it; the scope-naming rule for this path is missing or renders empty):\n    ${header}\n    ${prov}`;
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
// 8. release-please: the one scope-carrying site outside Renovate. Its rendered
//    PR titles land on main as squash commits, so they must pass commitlint too
//    or releases stop.
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

async function runSelfTest(lintHeader, rootDefaults, rules, configs, builtins) {
  const injected = [
    ['feat(infra-crds)!: update longhorn (1.8.0 -> 1.9.0)', 'off-enum scope: a templated scope rendered from a path outside the module layout'],
    ['feat(infra-)!: update fluxcd/flux2 (2.3.0 -> 2.4.0)', 'degenerate render: the templated path segment was absent, leaving an empty suffix'],
    ['chore(apps-ai)!: breaking chore', "'!' on a type that does not claim shipped behaviour changed"],
    ['feat(internal-workflows): shipped type on internal scope', 'pairing violation'],
    ['style: address markdown linting errors', 'removed type'],
  ];
  let caught = 0;
  for (const [header, why] of injected) {
    const r = await lintHeader(header);
    if (r.valid) fail(`SELF-TEST: injected defect NOT caught (${why}): ${header}`);
    else caught++;
  }
  // resolution-stage injection through a calver cell: the calver prefix
  // references {{semanticCommitScope}} rather than re-deriving the scope from
  // the path (the old doubled-scope render 'feat(infra-infra-networking):' is
  // structurally impossible now), so what needs falsifying is the REFERENCE:
  // an off-enum value in organize-semantic-scope must flow through the calver
  // prefix template into a rejected header. If the prefix silently stopped
  // reading the scope, or calver cells stopped reaching commitlint, this
  // passes without checking anything.
  const calverOcc = { manager: 'flux', datasource: 'helm', depName: 'authentik', packageFile: 'infrastructure/subsystems/security-extra/authentik/helm-release-authentik.yaml' };
  const offEnumScope = rules.map((e) => e.src.includes('organize-semantic-scope') && typeof e.rule.semanticCommitScope === 'string' && e.rule.semanticCommitScope.startsWith('infra-')
    ? { ...e, rule: { ...e.rule, semanticCommitScope: e.rule.semanticCommitScope.replace(/^infra-/, 'infrastructure-') } }
    : e);
  const calverLeak = resolveCell(rootDefaults, offEnumScope, calverOcc, 'minor');
  if (!calverLeak.header) fail('SELF-TEST: authentik minor resolved to no emission -- resolver defect');
  else {
    const r = await lintHeader(calverLeak.header);
    if (r.valid) fail(`SELF-TEST: off-enum scope reference through the calver prefix was NOT caught: ${calverLeak.header}`);
    else { caught++; note(`self-test: off-enum scope flowed through the calver prefix as '${calverLeak.header}' and was caught`); }
  }
  // breaking-treatment injections, both directions:
  // (a) re-apply the mutation this predicate was written against -- matchUpdateTypes
  //     excluding major on the override-calver rules. A calver major then falls through to
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
  // occupancy-coverage assertion for the node toolchain manifest. This is not a
  // defect injection but a vacuity guard: if detectOccupancy stopped enumerating
  // package.json, every npm/bun verdict below would be about an empty set and the
  // injection that follows would pass without checking anything.
  const occ = detectOccupancy(configs, gitLsFiles(), builtins);
  const nodeCells = occ.filter((c) => /(^|\/)package\.json$/.test(c.packageFile));
  if (nodeCells.length === 0) {
    fail('SELF-TEST: no npm/bun occupancy found for a tracked package.json -- the node manifest ' +
         'is unmodelled and every npm/bun verdict is vacuous');
  } else {
    caught++;
    note(`self-test: ${nodeCells.length} npm/bun cells enumerated from the node toolchain manifest`);
    // resolution-stage injection through that cell: rewrite the scope every rule
    // assigns to the toolchain manifest to an off-enum value. If the cell were not
    // actually flowing through resolveCell + commitlint, this would pass silently.
    const offEnum = rules.map((e) => e.rule.semanticCommitScope === 'internal-dependencies'
      ? { ...e, rule: { ...e.rule, semanticCommitScope: 'internal-deps' } }
      : e);
    const injected2 = resolveCell(rootDefaults, offEnum, nodeCells[0], 'major');
    if (!injected2.header) fail('SELF-TEST: node manifest cell resolved to no emission -- resolver defect');
    else if ((await lintHeader(injected2.header)).valid) {
      fail(`SELF-TEST: off-enum scope on the node toolchain manifest was NOT caught: ${injected2.header}`);
    } else { caught++; note(`self-test: off-enum node-manifest scope rendered '${injected2.header}' and was caught`); }
  }

  // renovate-config occupancy pair. Renovate bumps this repo's own preset pins, so
  // the pin-moving pull request is itself an emission -- and the surface it names is
  // this repo's bot configuration, not anything shipped. Vacuity guard first:
  const cfgCells = occ.filter((c) => c.manager === 'renovate-config');
  if (cfgCells.length === 0) {
    fail('SELF-TEST: no renovate-config occupancy found for a pinned preset ref -- the manager ' +
         'that moves the shared-preset pin is unmodelled and every verdict about it is vacuous');
  } else {
    caught++;
    note(`self-test: ${cfgCells.length} renovate-config cells enumerated from pinned preset refs`);
    // ... then an injection through it: rewrite the scope those cells resolve to into
    // an off-enum value. If they were enumerated but never resolved or linted, this
    // would pass silently.
    const offEnumCfg = rules.map((e) => e.rule.semanticCommitScope === 'renovate'
      ? { ...e, rule: { ...e.rule, semanticCommitScope: 'renovate-config' } }
      : e);
    const leaked = resolveCell(rootDefaults, offEnumCfg, cfgCells[0], 'major');
    if (!leaked.header) fail('SELF-TEST: renovate-config cell resolved to no emission -- resolver defect');
    else if ((await lintHeader(leaked.header)).valid) {
      fail(`SELF-TEST: off-enum scope on a renovate-config cell was NOT caught: ${leaked.header}`);
    } else { caught++; note(`self-test: off-enum renovate-config scope rendered '${leaked.header}' and was caught`); }
  }

  // breaking-marker pair. The shared preset attaches '!' through a handlebars
  // prefix on its major rule, and .github/renovate/override-breaking-changes.json
  // strips it back off the surfaces that reach no consumer. Both halves need
  // falsifying, and either alone is vacuous: a template that silently rendered
  // nothing would make the strip rule look load-bearing when it is not, and a
  // strip rule that matched nothing would leave the marker unopposed.
  // (i) vacuity guard -- the marker template must actually render a marker.
  const markerTpl = '{{semanticCommitType}}{{#if semanticCommitScope}}({{semanticCommitScope}}){{/if}}!:';
  for (const [ctx, want] of [
    [{ semanticCommitType: 'chore', semanticCommitScope: 'github-actions' }, 'chore(github-actions)!:'],
    [{ semanticCommitType: 'feat', semanticCommitScope: '' }, 'feat!:'],
  ]) {
    const got = evalTemplate(markerTpl, { packageFileDir: '.github/workflows', updateType: 'major', ...ctx }, 'self-test');
    if (got !== want) fail(`SELF-TEST: breaking-marker template rendered ${JSON.stringify(got)}, expected '${want}' -- every marker verdict below is vacuous`);
    else caught++;
  }
  // (ii) injection through it -- remove the strip rule and the same cell must
  //      render an internal-scope '!' header that commitlint rejects.
  const actionsOcc = { manager: 'github-actions', datasource: 'github-tags', depName: 'actions/checkout', packageFile: '.github/workflows/lint.yaml' };
  const stripped = resolveCell(rootDefaults, rules, actionsOcc, 'major');
  if (!stripped.header || !(await lintHeader(stripped.header)).valid) {
    fail(`SELF-TEST: a .github/workflows major does not resolve to an acceptable header: ${stripped.header}`);
  } else caught++;
  const unstripped = rules.filter((e) => !(e.src.includes('override-breaking-changes') && e.rule.commitMessagePrefix === ''));
  const marked = resolveCell(rootDefaults, unstripped, actionsOcc, 'major');
  if (!marked.header) fail('SELF-TEST: unstripped .github/workflows major resolved to no emission -- resolver defect');
  else if ((await lintHeader(marked.header)).valid) {
    fail(`SELF-TEST: the breaking marker on an internal surface was NOT caught: ${marked.header}`);
  } else { caught++; note(`self-test: dropping the internal-surface marker strip rendered '${marked.header}' and was caught`); }

  // unscoped-module pair (see 6c). Mutation: empty every path-derived scope, so a
  // module-path major renders through the preset's GUARDED marker template as
  // 'feat!:' -- in-enum, so commitlint accepts it and only the falsifier can
  // object. Both directions: the mutation must fire, the real config must not.
  const scopelessRules = rules.map((e) => e.src.includes('organize-semantic-scope') && typeof e.rule.semanticCommitScope === 'string' && /^(apps|infra)-\{\{/.test(e.rule.semanticCommitScope)
    ? { ...e, rule: { ...e.rule, semanticCommitScope: '' } }
    : e);
  const unscoped = resolveCell(rootDefaults, scopelessRules, longhornOcc, 'major');
  if (!unscoped.header) fail('SELF-TEST: scope-stripped longhorn major resolved to no emission -- resolver defect');
  else if (!(await lintHeader(unscoped.header)).valid) {
    fail(`SELF-TEST: the unscoped-module injection was rejected by commitlint itself (${unscoped.header}) -- ` +
         'the silent-failure premise of the 6c falsifier no longer holds; re-derive whether it is still needed');
  } else if (!unscopedModuleFault(longhornOcc, 'major', unscoped.header, unscoped.applied)) {
    fail(`SELF-TEST: module-path cell resolving to an unscoped header was NOT caught: ${unscoped.header}`);
  } else { caught++; note(`self-test: scope-stripped module major rendered '${unscoped.header}' (commitlint-valid) and was caught by the unscoped-module falsifier`); }
  const scoped = resolveCell(rootDefaults, rules, longhornOcc, 'major');
  if (!scoped.header) fail('SELF-TEST: longhorn major resolved to no emission -- resolver defect');
  else if (unscopedModuleFault(longhornOcc, 'major', scoped.header, scoped.applied)) {
    fail(`SELF-TEST: the unscoped-module falsifier fires on a correctly scoped header: ${scoped.header}`);
  } else caught++;

  // template-grammar injection: unknown handlebars must fail loudly, not render
  const before = failures.length;
  evalTemplate('{{#unless isMajor}}x{{/unless}}', { packageFileDir: 'a/b/c', updateType: 'minor' }, 'self-test');
  if (failures.length === before) fail('SELF-TEST: unknown handlebars construct was NOT rejected');
  else { failures.pop(); caught++; }

  // fetch-classification injections (see fetchText). The failure taxonomy is
  // behaviour worth guarding in both directions: retrying a terminal failure
  // would disguise a wrong pin as flakiness, and not retrying a transient one
  // would let a CDN blip redden the check. A stub fetch stands in for the
  // network; zero backoff keeps the self-test fast without changing the
  // control flow under test.
  const stubOk = (body) => ({ ok: true, status: 200, text: async () => body });
  const stubStatus = (status) => ({ ok: false, status });
  {
    // (a) transient failure, then success: must retry through to the body
    let calls = 0;
    const flaky = async () => (calls++ === 0 ? stubStatus(503) : stubOk('preset-body'));
    const got = await fetchText('stub://transient-then-ok', { fetchImpl: flaky, backoffMs: [0, 0] }).catch((e) => e.message);
    if (got !== 'preset-body' || calls !== 2) {
      fail(`SELF-TEST: transient fetch failure was not retried to success (calls=${calls}, got=${got})`);
    } else caught++;
  }
  {
    // (b) 404: terminal, must fail on the first attempt with no retry
    let calls = 0;
    const notFound = async () => { calls++; return stubStatus(404); };
    const err = await fetchText('stub://terminal-404', { fetchImpl: notFound, backoffMs: [0, 0] }).then(() => null, (e) => e);
    if (!err || calls !== 1) fail(`SELF-TEST: terminal 404 was retried or not raised (calls=${calls})`);
    else caught++;
  }
  {
    // (c) total outage: must give up after the bounded attempts, never hang
    let calls = 0;
    const outage = async () => { calls++; throw new TypeError('fetch failed'); };
    const err = await fetchText('stub://total-outage', { fetchImpl: outage, backoffMs: [0, 0] }).then(() => null, (e) => e);
    if (!err || calls !== 3) fail(`SELF-TEST: total outage did not give up after the bounded attempts (calls=${calls})`);
    else caught++;
  }
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
  const caught = await runSelfTest(lintHeader, rootDefaults, rules, configs, skippedBuiltins);
  if (failures.length) {
    console.error('\nSELF-TEST FAILURES:');
    for (const f of failures) console.error(`  ${f}`);
    process.exit(1);
  }
  console.log(`\nself-test: all ${caught} injected defects caught`);
  process.exit(0);
}

// Falsifier: an enabled:false rule that enumerates
// matchUpdateTypes silently re-enables the package for any type it forgot
// (replacement/rollback/bump reached override-calver with automerge on).
for (const { src, rule } of rules) {
  if (rule.enabled === false && Array.isArray(rule.matchUpdateTypes)) {
    fail(`${src}: enabled:false rule enumerates matchUpdateTypes -- a novel or omitted update type falls through and re-enables the package; disable rules must match all types`);
  }
}

const allFiles = gitLsFiles();
const occupancy = detectOccupancy(configs, allFiles, skippedBuiltins);
console.log(`effective global ignorePaths: ${JSON.stringify(globalIgnorePaths(configs, skippedBuiltins))}`);
console.log(`package occupancy: ${occupancy.length} (manager, package, dir) sites from ${allFiles.length} tracked files`);

const headers = new Map(); // header -> one representative provenance
let disabledCells = 0;
for (const occ of occupancy) {
  for (const updateType of UPDATE_TYPES) {
    const { header, applied, eff } = resolveCell(rootDefaults, rules, occ, updateType);
    if (header == null) { disabledCells++; continue; }
    if (!headers.has(header)) headers.set(header, `${occ.manager}:${occ.depName}@${dirname(occ.packageFile)} [${updateType}] via ${applied.join(',') || 'root defaults'}`);
    // Falsifier (breaking-treatment class, both directions -- see 6b):
    // calver-class cells must never resolve breaking; non-calver module-path
    // majors must always resolve breaking.
    const fault = breakingTreatmentFault(rules, occ, updateType, header, eff, applied);
    if (fault) fail(fault);
    // Falsifier (unscoped-module class -- see 6c): a module-path cell must
    // always carry a scope; losing one renders in-enum and lands silently.
    const scopeFault = unscopedModuleFault(occ, updateType, header, applied);
    if (scopeFault) fail(scopeFault);
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
