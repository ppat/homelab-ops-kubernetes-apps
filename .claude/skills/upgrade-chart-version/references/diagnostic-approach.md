# Diagnosing a failing upgrade

This is deliberately not a symptom → fix lookup table. The specific failure you
hit — a signature mismatch, a webhook rejecting a CR, a probe timing out — is
different every time, and you're already equipped to reason about a specific
error once you can see it clearly. What this file covers is the part that *is*
transferable: how to get clear evidence fast using the tooling actually available
here, and the general shape of narrowing a diagnosis instead of guessing at one.

## Tooling assumption

`git`, `gh`, `kubectl`, `helm`, `yq`, `jq`, `kubeconform`, `kustomize`, `rg`/`grep`
are all installed locally already — use them freely for both research and
diagnosis, with no setup cost to account for. The one thing genuinely
unavailable locally is a live cluster, and that rules out more than it might
seem: `kubectl explain` queries a live API server's OpenAPI schema, not a local
CRD file, so it needs a cluster too. `helm template`/`helm show values`/
`kustomize build` work fine locally since they only need the CLI and files on
disk. `kubectl describe`/`get`/`logs`/`events` against a real resource, and
`kubectl explain`, only become available inside CI (a chainsaw test running
against its kind cluster) or if you stand up a kind cluster yourself locally —
see the next section for what that means for where diagnostic evidence actually
comes from.

## Narrow before you fix

Treat each failed CI run as a hypothesis-elimination step, not a "try something
and see." Before changing a manifest in response to a failure, be able to state:
*what specific evidence, from this failure, points at this specific cause, and
rules out the other plausible ones?* If you can't yet — because two causes would
produce the same symptom — that's the sign to gather more evidence before editing,
not after.

A concrete shape this takes often enough to name: an error message that's a
catch-all covering multiple root causes (a generic non-zero exit code, a generic
auth failure) can look identical whether the fault is credentials, network
reachability, or request signing. When you're staring at one of these, resist
patching the first plausible cause — add a step that distinguishes between the
candidates (e.g., decode and directly compare two secrets byte-for-byte instead of
assuming they differ) so the next failure, if any, is diagnosing something new
rather than re-litigating a cause you already had evidence against.

## Getting evidence out of this repo's CI — and keeping it out of your own context

Since you have no local cluster, `gh run view <id> --log-failed` is your only
window onto anything a chainsaw test's `catch:` block captured — `describe`,
`get`, `podLogs`, `events` all only exist as output baked into that CI log, not
as commands you can run directly against something live. That log is almost
always richer than the chainsaw assertion failure alone — errors from a
sidecar/plugin container often surface in that container's own log lines, not in
the assertion message itself. But that richness is exactly why it doesn't belong
inline in the main conversation: a failed suite's log dump easily runs to
hundreds or thousands of lines, most of which is irrelevant to the one line you
need, and once it's in context it stays there (full price, non-cacheable — it's
new content every run) until a compaction eventually discards detail you might
still have wanted.

**Delegate the fetch-and-filter to a subagent, and have it return both the
extracted answer and its own read of anything else in the log that looked
notable.** This is a different reason to delegate than the cheap-model coverage
fan-out in the main skill file — it's not about the task being easy enough for a
weaker model, it's about keeping a large, one-time, non-cacheable payload out of
the thread that's actually doing the reasoning. Give the subagent the run ID and
a specific question ("find the actual error from the barman-cloud sidecar
container, and the endpoint URL it used"), but don't ask it to answer *only*
that — a `gh run view --log-failed` subagent has already paid the cost of
reading the whole dump, so ask it to also flag anything else that looked
relevant that you didn't think to ask about (a second, unrelated warning; a
resource that never became ready; a retry loop). Otherwise a real second signal
sitting three lines from the one you asked about gets silently discarded along
with the rest of the log. If the diagnosis itself needs real judgment, that's
still fine to run on the main/reasoning model — the delegation is about
isolating the noisy fetch, not about downgrading who interprets it.

## A chainsaw `catch:` block only captures what you told it to

If a failure's first appearance doesn't give you enough to diagnose it, that's a
sign the test's `catch:` needs another `describe`/`get`/`podLogs`/`events` entry
for next time — capturing more permanently (in the committed test) beats
re-running with ad hoc `kubectl` commands you'll throw away, because the next
person (or your next session) hits the same gap.

## Reproducing locally before pushing again

A `kustomize build` on the exact directory Flux would build (including the
`components/` your test wires in) or a `helm template` with this module's actual
values (see `research-and-diagnosis.md`) runs in seconds and answers "does this
patch actually match/apply" or "does this render with what I expect" — without
waiting on a CI round trip. This is especially worth doing when a
patch/substitution silently no-ops rather than erroring (see
`config-surfaces.md` on patch/substitute ordering) — the local build shows you
the literal resolved YAML, which either confirms your patch landed or makes the
no-op obvious immediately.

## Recognizing a pre-existing or unrelated CI failure

Not every red check is caused by your change. This is a check the subagent
watching your run makes as part of diagnosing *its* failure (see "Delegate the
whole watch, not just the failure" in the main skill file) — not a reason to
go browsing other runs' history speculatively before you have a failure of
your own to explain (see `research-and-diagnosis.md`'s "Historical CI runs are
not research material"). Before spending a diagnostic cycle on a failure,
check whether it was already failing before your branch (a quick `gh run list`
against the base branch, or checking the check's failure reason against
something structurally unrelated to what you touched — e.g. a workflow config
gap that predates your commit, or a diff/comparison job that trips over
resource-name collisions between fixtures that both existed before you
started).
Fixing or working around an unrelated failure is a legitimate task, but it's a
different task from the upgrade — don't let it consume diagnostic effort you
haven't confirmed is actually about your change, and confirm with whoever's
directing the work before spending time on it.

A faster complementary check, when available: if the failure occurs in a stage
that's shared boilerplate across every module's chainsaw suite (bootstrapping
Flux, reconciling shared prerequisites like MinIO or external-secrets) and
happens *before* the stage that actually exercises your module's own changes,
that stage boundary alone is usually sufficient evidence of unrelatedness — no
base-branch comparison needed to conclude it.
