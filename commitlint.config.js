const validateBodyMaxLengthIgnoringDeps = async (parsedCommit) => {
  const { maxLineLength } = await import('@commitlint/ensure');

  const { type, scope, body } = parsedCommit
  const isDepsCommit = type === 'chore' && scope === 'deps'

  const bodyMaxLineLength = 120;

  return [
    isDepsCommit || !body || maxLineLength(body, bodyMaxLineLength),
    `commit message body line length must not exceed ${bodyMaxLineLength}`,
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
        'dev-tools',
        'github-actions',
        'renovate',
        'release',
        'apps-helm-repositories',
        'infra-bootstrap-crds',
        'infra-helm-repositories',
        'infra-clusterops-core',
        'infra-clusterops-extra',
        'infra-database-core',
        'infra-kubernetes-core',
        'infra-kubernetes-extra',
        'infra-networking-core',
        'infra-networking-extra',
        'infra-observability-core',
        'infra-secrets-core',
        'infra-storage-core'
      ]
    ],

    // don't validate case of body
    'body-case': [0, 'always']
  }
}
