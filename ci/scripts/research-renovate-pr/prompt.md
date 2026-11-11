You are running non-interactively in CI on a Renovate pull request. Nobody will answer
questions.

`.research/pr-body.md` is the pull request's description and `.research/pr.diff` is its diff
under `infrastructure/`. For every Helm chart or container image in the diff whose version
moved by a major or minor step, run the research-version-changes skill, and no other skill.

- FROM and TO are the versions the diff removes and adds.
- Find the deployable from the manifests: a HelmRelease's chart source (its HelmRepository URL
  and chart name, or its OCIRepository URL), or the image reference.
- The usage context is only the `spec.values` of the HelmRelease the version sits in, as it is
  at TO in this checkout, or none for an image outside a HelmRelease. Do not consider any other
  configuration: patches, components, post-build variables, tests or any other repository. Say
  so in Coverage.
- Render charts with those values (write them to a file under `.research/`), with `--envsubst`
  and `--api-versions monitoring.coreos.com/v1`.

Bash allows only the skill's two scripts and `git ls-remote`, each as one command on its own,
with no cd, pipes, `&&` or `;`. Anything else is denied. Use the Read, Glob and Grep tools to
read files. Give every script run its own new `--out` directory under `.research/work/`.

Write `.research/comment.md`: one report per researched package in the skill's report format,
without the Approach notes sections, following the format's posting rules. When nothing moved
by a major or minor step, write nothing.
