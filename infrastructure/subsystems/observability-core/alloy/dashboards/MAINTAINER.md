# Kubernetes Events dashboard — design notes

This document is for whoever is *editing* `kubernetes-events.json`, or adapting it to another cluster. It is the
reasoning behind the dashboard: which properties of event data forced each choice, which of those choices are
load-bearing rather than taste, and what silently breaks when they are changed. It is written to be useful to
someone who has never seen this cluster — to rebuild the dashboard elsewhere, to extend it without re-breaking a
fixed defect, or to decide that a trade-off made here is wrong for their cluster and know exactly which knob to
turn.

Three places carry different things, and none repeats another:

- **Each panel's `description` tooltip** in the JSON — point-of-use reading guidance for whoever is looking at
  that panel, plausibly at 2am and plausibly not the person who built it. It says nothing about how the query is
  built, so a reviewer working from the tooltips cannot catch anything on this page.
- **[README.md](./README.md)** — how to use the dashboard: what each row answers, how the filters compose, what
  the numbers mean, and what the dashboard cannot tell you.
- **This document** — everything behind the panels. It is the only written home for that reasoning.

Anyone editing a query is expected to have read [Extending it safely](#extending-it-safely) first.

## Why these five questions, in this order

The rows are named after the questions they answer rather than after the data they hold; [README.md](./README.md)
lists them. The order is priority order and it is deliberate. The morning scan is first because this cluster
deliberately runs no alerting, so a human scanning is the detection mechanism, not a backstop to one. Flakiness
is second because it is the capability the export uniquely unlocks — nothing else in the stack can answer it.
Triage is last in priority and first in original motivation.

The test for whether a panel belongs is whether it traces to one of those five questions. A panel that traces to
none should not exist, however interesting its data is — that is how event dashboards become inventories nobody
reads.

## The data contract

Adapting this to a different exporter means reproducing this shape, or rewriting every query. Indexed stream
labels are deliberately few:

| Label | Meaning |
| --- | --- |
| `job` | `kubernetes-events` — the selector every panel starts from |
| `namespace` | the **involved object's** namespace, absent entirely for cluster-scoped objects |
| `severity` | derived from the event's `type`: `Warning` maps to `warning`, everything else to `info` |
| `service_name` | added by Loki itself at ingest, not by the pipeline |

Everything else is in the log line, as logfmt:

```text
name=overseerr-data kind=PersistentVolumeClaim objectAPIversion=v1 objectRV=931512650 eventRV=949105935 reportingcontroller=persistentvolume-controller sourcecomponent=persistentvolume-controller reason=WaitForFirstConsumer type=Normal count=14403 msg="waiting for first consumer to be created before binding"
```

(This is the same stuck `overseerr-data` PVC that appears in
[README.md](./README.md#what-the-numbers-mean) under a lower lifetime `count` — the field only ever grows, so a
later sample reading higher than an earlier one is expected, not a discrepancy.)

Four consequences worth internalising before editing a query:

- **`reason` is not a label, on purpose.** It is the field an operator most wants to filter on, which is exactly
  why the temptation to index it is strong. It is also a free-form string any controller may extend without
  bound, so indexing it multiplies stream count by an unbounded dimension: namespaces × severities × reasons is
  four figures of near-empty streams here, against a few dozen actually stored, for a pipeline that ships a
  trickle. It stays queryable in the body via a label filter after `| logfmt`, at the cost of reading lines.
- **`kind` is a body field too**, which is why the `Kind` variable is a free-text regex box and not a dropdown —
  Loki cannot enumerate values it has not indexed.
- **Entries carry the event's own `LastTimestamp`, not the ingest time.** So the freshness panels report the age
  of the newest *event*, not of the newest write, and both are queried on that same clock. A stalled exporter and
  a genuinely silent cluster are therefore indistinguishable from the dashboard alone — neither is a normal state
  on a cluster running a GitOps controller, which is what makes the pair usable anyway.
- **`eventRV` changes on every re-emission** and `objectRV` whenever the involved object is updated, so neither
  is stable across the lines describing one fault. `| logfmt` extracts both of them, which means any
  aggregation must first collapse to a stable key — `by (namespace, kind, name, reason)` — or every single line
  becomes its own series and outer sums double-count. This is the single easiest way to write a query here that
  is confidently wrong.

## The central constraint: signal is rare, and noise is cluster-specific

The proportions here, measured: one reason alone — Kyverno `PolicyViolation`, from deliberately audit-mode
policies that re-report continuously — has run between 60% and 76% of all events depending on when you look, and
adding Flux's three success reasons takes the suppressed share to around 85%. What is left after that is mostly
pod lifecycle. [README.md](./README.md#why-so-much-is-hidden) describes what the two exclusion tiers do; this
section is why they are variables at all, and why there are two of them.

Two design consequences follow, and they are the two most transferable things in this document.

**Noise suppression is a visible control, not a hidden filter.** The noise floor could have been baked into every
query string, and that would have been shorter — but the noise set is a property of *this* cluster on *this* day.
It shrinks as the policy backlog is fixed, it grows when a new chatty controller arrives, and it is the one
mechanism on the dashboard capable of hiding a real problem. Making it a variable makes the floor
self-documenting, inspectable and portable: a reader on a different cluster changes a dropdown rather than
editing twelve queries. Its companion stat panel is part of the same commitment: a control that can hide a real
problem has to display its own size.

**A second tier hides success, and only where success is misleading.** It is separate from the noise floor
because it answers a different failure of the display: the floor removes volume that means nothing, while
`Known healthy reasons` removes evidence that is real and correct but drowns the rankings it appears in. That is
why it is applied to four panels and nowhere else, and why the reasons it holds must satisfy a stricter
membership rule than "chatty" — see [Tuning the exclusion tiers](#tuning-the-exclusion-tiers). Keeping those
reasons everywhere else is not an oversight: a lifecycle reason appearing where it never did before is itself a
symptom.

That two-tier split is what the `(healthy reasons hidden)` suffix on three row titles is telling the reader. It
is a statement about what they are looking at rather than a warning: everything left in those rows is a problem
whether it fired five times or twelve hundred, which is why the rows do not qualify it as *chronic*.

**Severity survives only as the split between the two scan panels.** Once the flood is excluded, almost
everything left is type `Normal`, chronic faults included, and the ranking and history panels therefore carry no
severity filter at all — adding one would empty exactly the panels meant to find trouble. The measured split, and
what it means for reading the two scan panels, is in
[README.md](./README.md#what-each-row-answers-and-how-to-read-it).

## Tuning the exclusion tiers

The shipped lists are one cluster's measured noise; what they encode is under
[Limits on the design itself](#limits-on-the-design-itself). Yours will be different.

**Finding yours takes two queries.** Rank reasons by volume, then re-rank with the leaders excluded and see what
surfaces:

```logql
topk(20, sum by (severity, reason) (count_over_time({job="kubernetes-events"} [24h])))
topk(20, sum by (severity, reason) (count_over_time({job="kubernetes-events"}
  | logfmt | reason !~ "^(<your candidates>)$" [24h])))
```

The second is the one that matters. A reason belongs in the exclusion list when removing it makes *other* things
visible without removing anything you would have acted on — which is a judgement about your controllers, not a
threshold. Expect audit-mode policy engines and GitOps reconcilers to dominate the first query on most clusters;
they are chatty by design and say nothing about health.

**Measure over the window you actually use.** These proportions are strongly window-dependent, and a short sample
will mislead you in a specific direction: over one hour this cluster showed a single Warning reason against
nineteen Normal ones, where the 24h figures quoted in [README.md](./README.md) hold eight times as many distinct
Warning reasons. Rare faults are precisely what a short window misses, so a one-hour sample overstates how
lopsided the split is. The conclusion drawn here survives at both scales — the chronic faults are `Normal` either
way — but do not calibrate an exclusion list on an hour of data.

**Name-based judgement is the hazard in the `Known healthy reasons` tier**, which holds pod and controller
lifecycle (`Scheduled`, `Pulled`, `Created`, `Started`, `Synced`) plus unambiguous success outcomes from other
controllers (`SawCompletedJob`, `ChartPullSucceeded`, `InstallSucceeded`, `PluginRegistered`). The boundary for
adding to it is whether a reason can *only* mean success. Deliberately absent from it, and not to be added:
`Killing` (what a crash loop looks like from the kubelet's side), the volume-cycling reasons
`Stop`/`Start`/`Attached`/`Detached` (a real storage fault is indistinguishable from routine cycling by name),
`Reloaded`, `WaitForFirstConsumer` (this dashboard's most valuable find so far — severity `info`, and
indistinguishable from lifecycle chatter by name alone), and anything matching `*Failed`. A reason belongs in
this tier only when no failure mode can produce it.

## Presence, not magnitude

When signal is that rare, any chart drawn on magnitude structurally hides it: a single `BackOff` is invisible
beside anything with double-digit volume, and `topk` would rank away precisely the one-off event the scan exists
to surface. That is why the scan panels render *that a reason fired* rather than how often.

Status history rather than state timeline is a data-driven choice, not an aesthetic one. Loki returns gaps, not
zeros, and events at this density are extremely sparse — measured over 3h at 12-minute buckets, every Warning
series outside the noise set had one sample in fifteen. A state timeline draws a region from each sample to the
next, so an isolated sample either collapses to a hairline or gets stretched to the end of the range, asserting a
state that held for hours when the truth was one event. Status history draws a fixed block per sample, which is
what "it happened here" actually means. **Sparse categorical data wants status history; state timelines are for
data that genuinely holds a value between samples.**

## Sorting the scan panels

The scan panels are `status-history` panels with one frame per `reason`, and Loki returns them as separate
frames. Neither of Grafana's two sorting transformations reorders across that frame array — `sortBy` and
`organize` both operate *within* a frame — so neither can alphabetize the panel's rows on its own. LogQL's
`sort()`/`sort_desc()` order by value, not by label, and `sort_by_label()` is unsupported on this Loki: a parse
error, confirmed live, not a runtime failure. What works is `joinByField` (outer join on Time, collapsing the
per-reason frames into one) followed by the `order` transformer with `orderByMode: "auto"`. `order` is normally
hidden from Grafana's transformation picker but functions correctly when placed directly in dashboard JSON.

## Counting occurrences, not log lines

This is the deepest trap in Kubernetes event data, and it has two halves that must be understood together,
because fixing one without the other produces a dashboard that is confidently wrong. The reader-facing half of
this — that the panels count occurrences while the stream shows re-emissions — is in
[README.md](./README.md#what-the-numbers-mean).

**Half one: log lines measure re-emission, not occurrence**, and the gap between the two reaches three orders of
magnitude. **Ranking chronic problems by line volume misses them entirely** — and the worse a fault gets, the
more aggressively the API server deduplicates it, so the measure degrades exactly where it matters most.

**Half two: `count` is a lifetime total and ignores your query window.** It says how bad something has ever been,
not whether it is still happening. Ranking on the raw value puts resolved spikes above live faults: a Flux
`DependencyNotReady` that peaked at 1,526 during one rollout and was healthy again minutes later outranks a fault
that is firing right now.

The resolution used here is the **in-window delta**: subtract the window's first observed `count` from its last,
and floor the result.

```logql
(max by (namespace, kind, name, reason) (max_over_time(… | unwrap count [$__range])))
  - (min by (namespace, kind, name, reason) (min_over_time(… | unwrap count [$__range]))) + 1
```

That yields occurrences inside the window, which is what these panels claim to show.

Note that this makes the ranking a measure of **activity, not of severity**. A chatty-but-benign controller
re-announcing a Service hundreds of times a day is the kind of case `Known healthy reasons` (above) exists to
suppress on these panels by default; a reason of that shape not yet added to that tier would still rank as
highly as a real fault. That residual case is not a defect to be patched with a heuristic — it is what the
exclusion variables are for.

## Traps that return a wrong number instead of an error

Each of these fails silently. None produces an error, an empty panel with a message, or anything else that would
prompt a second look — which is why they are listed rather than left to be rediscovered.

- **An unanchored negative label filter with an empty variable blanks everything.** Loki does not anchor label
  filter regexes applied after a parser, so `reason !~ "$var"` with nothing selected becomes `reason !~ ""`, the
  empty pattern matches every string, and the negation excludes every line. Clearing the exclusion variable is a
  supported and encouraged action — "show me what is hidden" — so it must be inert, not catastrophic. Anchoring
  to `^($var)$` makes an empty selection a no-op and, incidentally, stops a substring silently swallowing a
  longer reason name (an unanchored `PolicyViolation` entry would also exclude a future
  `PolicyViolationResolved`). Note the asymmetry that makes this so easy to get wrong: an empty **line** filter,
  `|= ""`, is genuinely inert. An empty **label filter regex** is not.
- **`unwrap` on a field that is absent drops the sample entirely.** It is treated as a parse error, not as zero
  or one. Structurally one-shot events carry no `count` at all — the scheduler's `Scheduled` event fires once, is
  never updated, and its line has no `count=` token — so they vanish from every occurrence-ranked panel. The
  triage table is where this hurts: a Warning that fired *exactly once* is precisely what you go there to find,
  and it would appear in the scan panel above (which uses `count_over_time` and is unaffected) and then be absent
  from the table below. A `label_format` stage ahead of each `unwrap` defaults a missing count to 1, which is
  what absence means. The affected set is smaller and less predictable than intuition suggests — many events that
  seem one-shot do carry `count=1`, because the controller updated the object at least once. Do not guess which
  ones; `sum by (reason) (count_over_time({job="kubernetes-events"} | logfmt | count="" [24h]))` lists exactly
  the reasons whose lines lack the field on your cluster. Here that is two reasons out of thirty-odd.
- **A delta reintroduces that same drop for single-observation objects.** If an object is observed once in the
  window, `max` equals `min` and the delta is 0, so a real single occurrence sorts below the bottom of the
  ranking and disappears. The trailing `+ 1` is a floor, not a fudge. It is arithmetic because LogQL has no
  `clamp_min` — the function is a parse error on this Loki, not merely discouraged.
- **The delta's two halves need different aggregators, and swapping them is invisible.** The subtraction is
  `max by (…) (max_over_time(…))` minus `min by (…) (min_over_time(…))`. Using `max by` on the *lower* half —
  an easy slip, since the two lines otherwise read identically — still parses, still returns numbers, and still
  ranks plausibly. It just silently understates every object that was observed more than once. Read both halves
  whenever touching these queries; the outer aggregator must match the inner one.
- **`| logfmt` fans out into per-line series.** Covered under the data contract above; it is repeated here
  because it belongs to the same family — the query runs, returns a plausible number, and the number is wrong.
- **A Loki instant query's value field is named `Value #<refId>`, not `Value`.** Grafana routes any
  `queryType: instant` metric query through `makeTableFrames`, which produces one table frame per refId whose
  value field carries the refId suffix. A transformation or field override matching the bare name `Value`
  therefore silently matches nothing — no error, just a no-op. Here that left a table column reading `Value #A`
  instead of its intended title, and separately a gauge cell style that never applied. Matchers on that field use
  the refId-suffixed form; carrying both spellings alongside each other is harmless, since an unmatched key is
  simply ignored.
- **A panel legend's `sortBy` matches a reducer's display name, not its id.** `sum` displays as `Total`, so
  `sortBy: "Sum"` matches nothing and the legend sort silently never applies; `max` happens to display as `Max`,
  so the identical mistake there is invisible. Check the reducer's display name before assuming it equals the id.

## Cluster-scoped objects are a structural trap, not an edge case

Cluster-scoped objects have no namespace to report ([README.md](./README.md#node-and-volume-events-have-their-own-panel)),
and the mechanism matters more than it looks: the exporter sends the label as an empty string, and Loki drops
empty label values on ingest — before the stream hash is computed — so those streams carry **no `namespace` label
at all** and appear in no dropdown.

That has one consequence that will bite anyone who copies this dashboard: **a namespace variable whose "All"
expands to an explicit list of namespaces silently excludes every one of them.** The list can only contain values
that exist, and none exists. The `allValue` is `.*` for that reason and must stay that way — an empty-matching
regex is the only selector that reaches label-less streams. This is invisible until someone asks why node or
volume events never show up, at which point it looks like a broken exporter.

Because those events cannot be reached through the namespace variable at all, they also get their own panel,
pinned to `namespace=""` and sliced by `Kind` instead. What that means for a reader is in
[README.md](./README.md#node-and-volume-events-have-their-own-panel).

## Why the freshness panels exist

If the exporter stops, every panel renders empty — and an empty events dashboard looks exactly like a calm
cluster. That ambiguity is fatal to a dashboard whose primary use is "is anything wrong", so a freshness
indicator leads the layout: a count of lines arriving in a fixed recent window, plus the age of the newest event.
Both deliberately ignore every dashboard variable, because a liveness check that a filter can blank is not a
liveness check, and both scan panels' "no data" messages point at it.

This is not defensive decoration. `loki.source.kubernetes_events` implements no health interface: denied the RBAC
it needs, it blocks in cache sync, logs an error, and goes on reporting `state: healthy` while shipping nothing
(checked against Alloy v1.18.1). Component health cannot distinguish a working export from a broken one; arriving
entries are the only positive signal. **Any dashboard built over a sparse stream needs this, whatever the
exporter's health endpoint claims.**

A fixed recent window works as a liveness threshold on any cluster running a GitOps controller, since source
reconciliation emits continuously; on a genuinely idle cluster it would need widening.

## Shipping it through GitOps

Relevant to anyone provisioning a dashboard from a repository rather than clicking it into Grafana. Each of these
fails silently, in the same family as the query traps above.

- **A templating engine will eat the dashboard's own variables.** Dashboard JSON is dense with bare `$` tokens —
  `$datasource`, `$__rate_interval`, `$__interval`, every template variable. Any pipeline that performs variable
  substitution on the file before applying it will expand them to empty strings, and the result is a dashboard
  that loads cleanly with every panel silently unconfigured. Here that means Flux's post-build substitution is
  disabled on the generated ConfigMap; on another stack it may be Helm's templating or `envsubst`. The failure
  looks like a Grafana problem and is not one.
- **A content-hashed resource name orphans the old dashboard on every edit.** If the ConfigMap's name changes
  with its content and the reconciler does not garbage-collect, Grafana's sidecar sees both the old and new
  copies and serves duplicates that diverge over time. Pin the name, or make sure pruning is genuinely on.
- **A data link's danger is a hardcoded uid, not the `/d/` path form.** The same file is published under a review
  uid and a provisioned one, and a link written as `/d/kubernetes-events/…` works wherever it was tested and
  silently navigates to a dashboard that does not exist everywhere else. Interpolating the uid instead —
  `/d/${__dashboard.uid}/…` — gives an absolute path that follows the dashboard wherever it is published, which
  is what a dashboard shipped through GitOps needs: it exists at a review uid and a provisioned uid and must work
  at both. `${__dashboard.uid}` is available in a data link's interpolation scope; that is confirmed by Grafana's
  own e2e test fixtures, since its documentation does not enumerate it.
- **A bare relative query string does not work at all, for a reason that is not obvious from reading it.** Grafana
  serves its app with `<base href="/">`, so a URL beginning with `?` resolves against the site root rather than
  the current path and lands on the home page with the parameters appended. It belongs in the same family as the
  query traps above — it looks correct, passes every static check, and fails only in a browser — and it is a
  Grafana-wide fact rather than anything specific to this dashboard, so it generalises to any data link.

None of this is specific to Flux. The templating and pruning hazards generalise to any environment that carries
the file through similar tooling; the link hazards generalise to any Grafana dashboard published at more than one
identity, or with any data link at all.

## Deliberately not built

- **Policy-compliance views.** Building one from events means re-importing the majority of volume this dashboard
  exists to exclude, in exchange for an answer that is structurally the wrong one — Kyverno's `PolicyReport`
  resources are where current state lives.
- **Anything a metric already answers.** The division of labour between the two is in
  [README.md](./README.md#what-it-cannot-tell-you); duplicating a metrics dashboard in events costs query time
  and delivers a worse version of the same chart.
- **Hardcoded per-reason stat panels.** The obvious design — a row of tiles for `OOMKilled`, `FailedMount`,
  `BackOff` — only ever shows the reasons somebody enumerated when they built it, and silently misses everything
  else forever. It is also the design most likely to look healthy during an outage caused by a reason nobody
  thought of. The scan panels enumerate whatever is actually present instead.
- **`reason` as an indexed label.** See the data contract above; it is a stream-cardinality decision, and the
  cost falls on the whole log store, not on this dashboard.

## Extending it safely

Nothing in CI validates the *structure* of these queries. The pre-commit gate checks that the JSON parses, and
`ci/test/infra-observability/scripts/check-event-stream-contract.sh` asserts the data contract the dashboard
depends on — the exact label set, that `reason` is absent from labels but present in the line, that both
`severity` values are produced, and the cluster-scoped no-namespace behaviour. That protects the foundation; it
does not protect the panels.

The invariants below are enforced only by review, and this list is their only written home.

Treat each of these as a defect if removed, not as cleanup:

- The `^(…)$` anchors around every `reason` and `kind` filter — removing them blanks or over-matches.
- The `label_format count=…` default ahead of every `unwrap` — removing it silently drops one-shot events.
- Both `max_over_time` and `min_over_time` in the occurrence queries, plus the `+ 1` floor — collapsing to a
  bare `max` restores lifetime-count ranking; dropping the floor discards single occurrences.
- `by (namespace, kind, name, reason)` as the inner grouping key — dropping any part of it merges distinct
  objects (two same-named objects in different namespaces collapse) or fans out per line.
- `allValue: .*` on the namespace variable — an expanded list drops all cluster-scoped events.
- `showValue: never` and the absence of `topk` on the scan panels — both reintroduce magnitude bias.
- `$__interval` as the scan panels' bucket width — a fixed width stops a single event staying a visible block
  across every time range.
- The freshness panels' independence from all variables.
- `Known healthy reasons` on the four panels under the `(healthy reasons hidden)` rows and nowhere else — applying
  it to the scan panels, the drill-down table or the event stream removes the lifecycle sequence a failure is read
  from.
- `timeFrom: 7d` on the flakiness panel — following the dashboard range instead surrenders the one capability the
  export exists for.
- The drill-down link's `/d/${__dashboard.uid}` interpolation — see the provisioning traps above; hardcoding a
  literal uid breaks every other copy of the dashboard, and a bare query string does not navigate at all. Note
  that a link narrowing the event stream *alone* is not available to build: a data link can only navigate, and a
  variable is dashboard-wide by construction, so the click necessarily narrows the table with it.
- The refId-suffixed `Value #<refId>` matchers on instant-query panels — collapsing them to the bare `Value`,
  as an apparent duplicate, silently reverts the fix described in the traps above.

When adding a panel, state which of the five questions it answers first. If the answer is "it's interesting",
that is a reason not to add it.

**Verify by disagreement, not by inspection.** Every trap on this page returns a plausible number, so a query
that looks right and runs without error is no evidence at all. What actually caught each of them was computing
the same quantity a second way and finding the two disagreed — line counts against `count` deltas, one reason in
isolation against the whole stream, a filter's output against the same filter removed. Two habits follow:

- **Run the exact shipped expression**, variables interpolated as Grafana would, rather than a simplified version
  of it. A hand-reconstructed query is evidence about the reconstruction; more than one apparent defect here
  turned out to be a transcription slip in the check rather than a fault in the dashboard.
- **Test in the failing direction.** Before believing a fix, construct the input that should break it and confirm
  it does. A green result from a check that cannot go red proves nothing — and several of the traps above were
  originally introduced by changes whose authors had verified them only in the passing direction.

Panel `description` tooltips are part of the change, not documentation of it: a panel whose query changes shape
usually needs its tooltip re-read, since the tooltip is the only guidance most readers will ever see.

## Limits on the design itself

What constrains a *reader's* conclusions — ranking measuring activity, a new fault scoring 1, the pinned 7-day
window — is in [README.md](./README.md#what-it-cannot-tell-you). What constrains an editor:

- **The exclusion defaults are ours.** They encode a Kyverno audit backlog and a Flux installation, measured on
  one small cluster. On another cluster they are at best a starting point and at worst actively wrong — a cluster
  with no Kyverno excludes a reason that never occurs, and gains nothing. See
  [Tuning the exclusion tiers](#tuning-the-exclusion-tiers).
- **Per-namespace suppression is not offered**, and the cost of that is a reader's, not an editor's
  ([README.md](./README.md#what-it-cannot-tell-you)). Reason granularity is what keeps the control simple enough
  to be read and trusted at a glance, and that simplicity is the trade.
- **The export bounds the history, not the dashboard.** History starts when the exporter started, replay after a
  restart is bounded by the Event API TTL, and the exporter's `emptyDir` positions file means a restart re-ships
  whatever the API server still holds. See the module [README](../../README.md#notes) for what that costs and why
  it is accepted.
- **Not validated across Grafana versions or on very large clusters.** The sparse-data reasoning that selects
  status history over state timeline is specific to a cluster whose signal is a trickle; at a scale where every
  bucket holds events for every reason, a magnitude view may serve better and the scan panels may need `topk`
  after all.
