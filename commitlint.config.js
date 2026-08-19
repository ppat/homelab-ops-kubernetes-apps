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

// Issue #3611 is a long-running tracking epic that must stay open until its
// migration finishes. release-please (pinned via release-please-action v5.0.0,
// which locks release-please to v17.6.0 -- pre-dating the upstream fix in
// https://github.com/googleapis/release-please/pull/2851, first released in
// v17.10.4) renders *any* footer-style issue reference -- "Refs #3611",
// "Closes #3611", etc. -- as a literal ", closes #3611" in the generated
// release-PR body, regardless of which keyword was actually used. GitHub then
// auto-closes the issue when that release PR is squash-merged. This has
// closed and reopened #3611 five times. Block the bare-reference form here so
// it can't recur; require a plain issue URL instead, which no parser acts on.
const TRACKING_EPIC_ISSUE = '3611';
const noBareTrackingEpicReference = (parsedCommit) => {
  const { references } = parsedCommit
  const hasBareReference = (references || []).some(
    (reference) => reference.issue === TRACKING_EPIC_ISSUE
  )

  return [
    !hasBareReference,
    `do not reference issue #${TRACKING_EPIC_ISSUE} with a bare "#${TRACKING_EPIC_ISSUE}" -- release-please rewrites it into a closing keyword in the generated changelog, which auto-closes this long-running tracking epic when the release PR is merged. Reference it with the full URL instead: https://github.com/ppat/homelab-ops-kubernetes-apps/issues/${TRACKING_EPIC_ISSUE}`,
  ]
}

module.exports = {
  extends: ['@commitlint/config-conventional'],
  plugins: ['commitlint-plugin-function-rules'],
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

    // specify the allowed scopes
    'scope-enum': [2, 'always',
      [
        '',
        'claude',
        'dev-tools',
        'github-actions',
        'kubernetes-api',
        'renovate',
        'release',
        'apps-ai',
        'apps-bitwarden',
        'apps-coder',
        'apps-downloaders',
        'apps-harbor',
        'apps-home-automation',
        'apps-media',
        'apps-misc',
        'component-cert-issuer',
        'component-db-backups',
        'component-db-restore',
        'component-external-dns-provider',
        'component-oidc-credentials',
        'component-sso',
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
        'infra-virtualization-core'
      ]
    ],

    // don't validate case of body
    'body-case': [0, 'always'],

    // disable default 'references-empty' rule and add custom rule to block
    // bare references to the #3611 tracking epic (see comment above)
    'references-empty': [0],
    'function-rules/references-empty': [
      2,
      'always',
      noBareTrackingEpicReference
    ]
  }
}
