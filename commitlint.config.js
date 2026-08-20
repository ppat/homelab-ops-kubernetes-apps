const { maxLineLength } = require('@commitlint/ensure');

const validateBodyMaxLengthIgnoringDeps = (parsedCommit) => {
  const { type, scope, body } = parsedCommit
  const isDepsCommit = type === 'chore' && scope === 'deps'

  const bodyMaxLineLength = 120;

  return [
    isDepsCommit || !body || maxLineLength(body, bodyMaxLineLength),
    `commit message body line length must not exceed ${bodyMaxLineLength}`,
  ]
}

// ---------------------------------------------------------------------------
// Commit taxonomy (see .analysis / the taxonomy design docs for derivation).
//
// Scope names the released artifact whose directory the diff touches -- or,
// when the diff touches no artifact directory, which internal surface it
// maintains. Type states the kind of change. The release machinery listens to
// neither (release-please routes by path, sizes the bump by type), so the
// header is a claim about the diff, checked here for vocabulary and below
// (pairing rules) for internal consistency.
// ---------------------------------------------------------------------------

// The 21 released modules: their scope is a shipped claim.
const moduleScopes = [
  'apps-ai',
  'apps-bitwarden',
  'apps-coder',
  'apps-downloaders',
  'apps-harbor',
  'apps-home-automation',
  'apps-media',
  'apps-misc',
  'infra-bootstrap-crds',
  'infra-clusterops-core',
  'infra-database-core',
  'infra-kubernetes-core',
  'infra-kubernetes-extra',
  'infra-networking-core',
  'infra-networking-extra',
  'infra-observability-core',
  'infra-observability-extra',
  'infra-security-core',
  'infra-security-extra',
  'infra-storage-core',
  'infra-virtualization-core',
];

// Shipped, non-module surfaces.
const shippedSurfaceScopes = [
  'components',      // shared kustomize components: ship by proxy via each consuming module
  'kubernetes-api',  // a Kubernetes apiVersion bumped, anywhere
];

// Internal surfaces: never ship; take chore/ci/test/docs.
const internalScopes = [
  'agents',                 // .claude/**, CLAUDE.md, other AI-coding-agent instruction surfaces
  'github-actions',         // a uses:/action ref bumped or re-pinned, anywhere
  'internal-dependencies',  // toolchain/dev dependency moves, tooling config files
  'internal-workflows',     // this repo's own CI + release machinery, shared test harness, linter configs
  'release',                // release cuts: commits authored by release-please
  'renovate',               // this repo's Renovate configuration
];

// Transitional entries: accepted while pre-migration emissions and open PRs
// flush; retire at migration step E7. Do not use in new commits.
//   dev-tools    -> internal-dependencies / internal-workflows
//   claude       -> agents
//   component-*  -> components
const transitionalInternalScopes = [
  'claude',
  'dev-tools',
];
const transitionalComponentScopes = [
  'component-cert-issuer',
  'component-db-backups',
  'component-db-restore',
  'component-external-dns-provider',
  'component-oidc-credentials',
  'component-sso',
];

// The empty scope: repo-level docs/policy belonging to no single surface,
// atomic changes spanning >=2 modules, fan-in ci/test/ group changes, the
// repo-root/dot-directory residue -- and grouped bot branches that resolve
// through ci/test/**.
const emptyScope = [''];

// Types whose commits claim shipped behaviour changed. They pair only with
// scopes that can carry that claim (modules, components, kubernetes-api, the
// empty scope for multi-module changes) -- never with internal surfaces.
const shippedTypes = ['feat', 'fix', 'perf', 'refactor'];
const shippedScopes = [
  ...moduleScopes,
  ...shippedSurfaceScopes,
  ...transitionalComponentScopes,
  '',
];

const validateTypeScopePairing = (parsedCommit) => {
  const type = parsedCommit.type || '';
  const scope = parsedCommit.scope || '';
  if (!shippedTypes.includes(type)) {
    return [true];
  }
  return [
    shippedScopes.includes(scope),
    `type '${type}' claims shipped behaviour changed; it pairs only with a module scope, ` +
    `'components', 'kubernetes-api', or the empty scope -- not '(${scope})'. ` +
    `Internal surfaces take chore/ci/test/docs.`,
  ];
};

// Breaking marker: '!' cuts a minor at 0.x and is rendered in the changelog
// regardless of the type's hidden flag -- so 'chore(x)!:' would cut a release
// while claiming to be inert. Only shipped types may carry it.
const validateBreakingTypeRestriction = (parsedCommit) => {
  const header = parsedCommit.header || '';
  const hasBang = /^\w+(\([^)]*\))?!:/.test(header);
  if (!hasBang) {
    return [true];
  }
  const type = parsedCommit.type || '';
  return [
    shippedTypes.includes(type),
    `'!' marks a breaking change, which is release-operative (it bumps and renders even for ` +
    `hidden types); it may only pair with ${shippedTypes.join('/')}, not '${type}'.`,
  ];
};

module.exports = {
  extends: ['@commitlint/config-conventional'],
  plugins: [
    'commitlint-plugin-function-rules',
    {
      rules: {
        'local/type-scope-pairing': validateTypeScopePairing,
        'local/breaking-type-restriction': validateBreakingTypeRestriction,
      },
    },
  ],
  rules: {
    // increase max line length for header
    'header-max-length': [2, 'always', 120],

    // disable max line length for footers
    'footer-max-line-length': [0, 'always'],

    // disable default 'body-max-line-length' rule and add custom rule for body-max-line-length
    'body-max-line-length': [0],
    'function-rules/body-max-line-length': [
      2,
      'always',
      validateBodyMaxLengthIgnoringDeps
    ],

    // specify the allowed types: build and style are deliberately absent
    // (style cut real patch releases; build has no emitter here)
    'type-enum': [2, 'always',
      ['chore', 'ci', 'docs', 'feat', 'fix', 'perf', 'refactor', 'revert', 'test']
    ],

    // specify the allowed scopes
    'scope-enum': [2, 'always',
      [
        ...emptyScope,
        ...moduleScopes,
        ...shippedSurfaceScopes,
        ...internalScopes,
        ...transitionalInternalScopes,
        ...transitionalComponentScopes,
      ].sort()
    ],

    // scope/type pairing and the '!' restriction (see comments above)
    'local/type-scope-pairing': [2, 'always'],
    'local/breaking-type-restriction': [2, 'always'],

    // don't validate case of body
    'body-case': [0, 'always']
  }
}
