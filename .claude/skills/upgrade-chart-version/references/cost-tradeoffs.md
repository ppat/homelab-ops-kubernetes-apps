# When upfront investment lowers total cost

The question this file answers: when is it worth spending more tokens/time now
(reading more release notes, building a local repro, writing a diagnostic
instrumentation commit) to avoid spending more later (another CI round trip,
another guess)? This isn't "be thorough" as a virtue — it's a real trade-off with
a right answer that depends on how expensive the *next* feedback loop is.

## What actually drives cost: payload size and cacheability, not which tool

The tool you're running is a rough proxy for cost, but the real drivers are (a)
how much text comes back and lands in context, and (b) whether that text is the
kind of thing prompt caching can discount on a retry. Rank actions by those two
things, not by tool name alone:

- **Cheap: local, deterministic, small-or-filterable output.** `kustomize build`,
  `helm template`, `jq`/`yq` queries, `git clone`/local `diff`, `rg`/`grep`, plain
  file reads, and any `kubectl`/`helm` subcommand that only needs the CLI itself
  (no live cluster) — these run in seconds, and you control the output size (pipe
  through `jq`/`yq`/`grep` to keep only what matters). Being wrong here costs
  nothing but re-running it.
- **Medium: small structured remote calls, or the cost is latency more than
  payload.** `git ls-remote --tags`, `gh release view`/`gh api
  repos/.../releases` (structured, usually short), a single `WebFetch`/web
  search — these leave the machine, so they're slower than the cheap tier and
  return content you didn't author, but the response itself is normally short
  and targeted.
- **Expensive: large, non-cacheable payloads landing directly in context.**
  `gh run view --log-failed` on a real CI run is the main one — since there's no
  local cluster, that log is also the only place a chainsaw `catch:` block's
  `describe`/`get`/`podLogs`/`events` output shows up at all. These dumps can run
  to hundreds or thousands of lines, every run's content is new (never a cache
  hit), and once it's in context it stays there until compaction discards
  detail you might still have needed. The expense here isn't really the tool
  call — `gh run view` itself is fast — it's what reading the result costs the
  session afterward.

The practical upshot mirrors `diagnostic-approach.md`'s subagent-delegation
point: expensive-tier reads are exactly the ones worth having a subagent fetch
and filter down to just the answer, rather than pulling the raw payload into the
main thread yourself.

## Prompt caching only rewards *unchanged* re-sends

Caching amortizes content you send again **unchanged**, on a short TTL — it does
nothing for content that's genuinely new each time. A second `gh run view
--log-failed` on a *different* failed run is not a cache hit just because the
first one was similar; it's full-price new context. So "read more upfront, in
one pass" beats "read a little, guess, get a new failure, read a little more"
not only because it avoids wall-clock round trips, but because each new
round trip's log dump is full-price growth, not a discount on the last one.

## Where this actually bites: the ambiguous-failure case

| Situation | Cost per wrong guess | Upfront investment worth buying |
| --- | --- | --- |
| A cheap-tier local check (`kustomize build`, `helm template`) | Seconds — just re-run it | Little; try it directly |
| A medium-tier lookup (release notes, a tag list) came back incomplete | One more targeted fetch | Read one version further back, or check one more source, before concluding |
| An expensive-tier CI failure whose cause is ambiguous between 2+ hypotheses | A full CI round trip, **per wrong guess**, each one a large non-cacheable payload | An instrumented diagnostic commit that resolves the ambiguity in **one** push — see below |

That last row is the highest-leverage case. When a failure's error message is a
catch-all consistent with more than one root cause, the "cheap-looking" move —
patch the first plausible cause and re-push — is actually the expensive path if
you're wrong, because being wrong costs a full expensive-tier cycle to find out.
Spending one such cycle upfront on a commit whose only purpose is "produce the
evidence that tells these hypotheses apart" (e.g., decode and directly compare
two secrets, rather than assume) converts an unbounded guess-and-check loop into
a bounded one: exactly one more informed cycle, regardless of how many
hypotheses you started with.

## Applying this without a formula

There's no fixed rule for exactly how much upfront research is "enough" — that
depends on the specific upgrade's complexity, which you can't know before
starting. The heuristic that generalizes: before you push a change that depends
on a hypothesis, ask whether a wrong hypothesis would cost you *one more
iteration of the loop you're about to run*, or several. If several, that's the
signal to spend more now — reading further into the release notes, or building
one more piece of local repro, or writing the instrumentation — until a wrong
answer only costs one more iteration, not an open-ended number of them.

The same logic is why research fan-out to a cheap subagent (see the main skill
file) is a cost win specifically for *coverage* tasks and not for *diagnosis*
tasks: a coverage gap found late just means another cheap subagent call, but a
wrong diagnosis found late means another expensive-tier cycle. Spend the cheaper
resource (a fast model, parallelized, or a subagent isolating a noisy fetch) on
the failure mode that's cheap to retry, and spend the more careful resource (the
reasoning model, sequential) on the one that isn't.
