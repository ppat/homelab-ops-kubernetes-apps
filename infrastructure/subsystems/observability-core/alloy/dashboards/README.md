# Kubernetes Events dashboard

`kubernetes-events.json` is a Grafana dashboard that reads Kubernetes Events out of Loki instead of out of the
Event API, so the history outlives the hour the API keeps. It is built for one job: noticing that something in a
cluster is wrong, and then finding out how long it has been wrong.

This document is for whoever is *using* it. Three places carry different things, and none repeats another:

- **Each panel's `description` tooltip** — hover the ⓘ in a panel's top-left corner for guidance on the panel in
  front of you: what it shows, how to read it, what to do next. That is the fastest answer at 2am.
- **This document** — how to use the dashboard as a whole: what each row answers, how the filters compose, what
  the numbers mean, and what it cannot tell you.
- **[MAINTAINER.md](./MAINTAINER.md)** — why it is built this way: how the queries are shaped, which parts are
  load-bearing, and how to adapt it to a different cluster. Read that one before editing anything.

## Why it exists

The Kubernetes Event API keeps roughly one hour of history, so `kubectl get events` is structurally incapable of
answering the two questions that matter most after an incident — *what happened last Tuesday*, and *has this been
flaky all week*. Exporting events to a log store removes that ceiling, and this dashboard is the part that makes
the resulting history readable. Everything about it is tuned for the long horizon: the default range is 24 hours,
the interesting ranges are longer, and the flakiness panel is pinned to 7 days regardless of the time picker,
because reaching past the API's TTL is the whole point.

It reads a single Loki stream — `{job="kubernetes-events"}`, with `namespace` and `severity` as labels and every
other field of the Event carried as logfmt in the line body. Reproducing that shape is all it takes to run this
against another cluster's export; the full contract is in [MAINTAINER.md](./MAINTAINER.md#the-data-contract).

## What each row answers, and how to read it

The rows are named after questions rather than after the data they hold, and they are in priority order.

1. **Is anything wrong I haven't noticed?** The daily scan. Two freshness stats confirm events are still
   arriving and a third shows how much the noise floor is hiding, then one panel per severity shows which reasons
   fired and when. Read those two scan panels for **rows you have not seen before**, not for big blocks — see
   [what the numbers mean](#what-the-numbers-mean) below. Nearly empty is the normal, healthy state. Most of the
   signal is in the Normal panel rather than the Warning one: in a measured 24h window here, 8 distinct Warning
   reasons against 31 Normal ones, and every standing fault worth fixing was in the second group.
2. **Has this been flaky, and for how long?** One 7-day panel, read left to right rather than by height. A band
   reaching the right-hand edge is still happening; one that stops partway is resolved, and where it stops is
   roughly when; where it starts is roughly how long it has been going on. Height is intensity and is the least
   interesting of the three.
3. **Which parts are unhealthy?** Two rankings — namespaces, then individual object and reason pairs — by how
   many times something happened inside the dashboard's time range. This is the "what do I fix next" row.
4. **Why did this node or volume misbehave?** Events about objects that belong to no namespace. They need their
   own panel, for the reason [below](#node-and-volume-events-have-their-own-panel).
5. **Something broke — what happened?** Triage: a sortable drill-down table, and the event stream beneath it,
   which is the only panel that shows an event's message.

In practice, work top to bottom. Confirm the pipeline is fresh, scan for an unfamiliar reason, take it down to
the drill-down table, sort by occurrences, then click the object name to narrow the stream below and read the
message.

## What the numbers mean

The API server does not write a fresh log line every time the same thing happens. It deduplicates, incrementing a
`count` field on the existing Event object instead. Two different quantities follow, and mistaking one for the
other is the easiest way to misread this dashboard:

- The **ranking panels and the drill-down table count occurrences** inside your time range — how many times the
  thing actually happened.
- The **event stream shows lines**. Consecutive lines about one object are re-emissions of a single Event with a
  rising `count`, not separate occurrences. Expand a line and read the field.

So a fault reading 200 occurrences in the table can sit above only ten lines in the stream, each carrying its own
`count` of 13,783. Three numbers, one fault: lifetime total, occurrences in your window, and re-emissions. The
middle one is the one that answers "is this happening now", and it is what the panels rank on.

The two scan panels at the top are the exception: they show **that** a reason fired, not how often. One block per
time bucket in which it fired at all, nothing ranked, nothing truncated, no value drawn — so a single `BackOff`
is exactly as visible as a reason with a thousand occurrences, which is the entire point. Counts are still in the
tooltip, and bucket width follows the time range, so one event stays a visible block whether the range is 6 hours
or 30 days.

## Why so much is hidden

On any real cluster the event stream is dominated by benign chatter — audit-mode policy engines and GitOps
reconcilers re-reporting continuously. Here that is around 85% of all volume, and events indicating something is
actually wrong are a fraction of a percent. Two variables hold that back, and both are visible controls rather
than filters baked into the queries:

- **`Noisy reasons excluded`** is the noise floor. It applies to every panel except the two freshness stats. A
  stat panel next to it shows how many lines it is currently removing, so the suppression cannot quietly grow
  without anyone noticing.
- **`Known healthy reasons`** hides reasons that can only mean a thing *worked* — pod and controller lifecycle,
  and unambiguous success outcomes. It applies only to the four panels under the three `(healthy reasons hidden)`
  row headings: the 7-day panel, both rankings, and the cluster-scoped panel. Those rank on activity, and a
  perfectly successful deploy produces a great deal of it, so without this tier the top of every ranking is
  whichever workload restarts most often. The scan panels, the drill-down table and the event stream keep every
  one of those reasons on purpose — the same lifecycle sequence is how a failure tells its story.

**Clearing either field shows exactly what it was hiding**, and that is a supported move, not a dangerous one. If
a panel looks suspiciously quiet, empty the variable and look again.

The defaults shipped here are one cluster's noise on one day, and they are examples of the shape rather than a
recommendation. Expect to tune them: the list shrinks as a policy backlog is worked through and grows when a new
chatty controller arrives. [MAINTAINER.md](./MAINTAINER.md#tuning-the-exclusion-tiers) has the two queries that
derive the list for your cluster, and the rule for deciding what belongs in the second tier.

## How the filters compose

`Namespace` (most panels) → `Noisy reasons excluded` (every panel except the two freshness stats) →
`Known healthy reasons` (the four panels under the `(healthy reasons hidden)` rows) → `Kind` (everything except
the scan panels) → `Search` (drill-down table and event stream only).

`Kind` is a regex typed into a text box rather than a dropdown, matched whole: `Node`, or
`Node|PersistentVolume|Replica`. `Search` is a plain substring filter over the whole event line, so it takes an
object name, a controller name, or any phrase from a message.

`Kind` and `Search` deliberately do not reach the two scan panels, and the freshness stats ignore every variable:
a filter someone forgot they set must never be able to make the cluster look quiet.

Clicking an object name in the drill-down table sets `Search` to that name and carries the current time range
across. That narrows the event stream below to the object — and, because the table reads `Search` too, narrows
the table with it. The click focuses rather than previews; clearing `Search` is how you get back.

## Node and volume events have their own panel

The `namespace` label comes from the involved object, and a Node, PersistentVolume, StorageClass or ClusterPolicy
belongs to no namespace. Events about them carry no namespace at all, appear in no dropdown, and **cannot be
reached through the `Namespace` variable** — selecting namespaces does not narrow that panel, which is correct.
Use `Kind` to slice it instead. Between a fifth and a third of all event volume lands here, so it is not an edge
case.

The noise floor matters more on that panel than anywhere else: nearly all of that volume is cluster-wide policy
chatter, so a panel that looks almost empty is the exclusion list working rather than a broken query.

## An empty dashboard is not proof of health

If the export stops, every panel renders empty — which looks exactly like a calm cluster. The exporter cannot
close that gap itself: denied the permissions it needs, it goes on reporting itself healthy while shipping
nothing, so arriving entries are the only positive signal there is.

That is what the two freshness stats at the top are for, and why they ignore every dashboard variable. **Read
them first.** If the pipeline is silent, everything below is empty for the wrong reason.

## What it cannot tell you

- **The rankings measure activity, not importance.** A benign controller that re-announces something hundreds of
  times a day outranks a genuine fault that fired twice. The exclusion variables are the intended remedy, which
  means the ranking panels are only as good as those lists are maintained.
- **A brand-new fault scores 1** and will not reach a top-15 whose floor is in the hundreds. The scan panels are
  what catch that case; the rankings are the complement, not a replacement. Neither alone is sufficient, which is
  why both exist.
- **A resolved fault falls off the rankings** while still being visible in the 7-day panel. That is intended, but
  it means the rankings are not an incident history.
- **The 7-day panel ignores the time picker.** Zooming into a 30-minute incident window elsewhere on the
  dashboard leaves it showing 7 days.
- **Its top ten is recomputed per bucket**, because LogQL evaluates `topk` per step rather than over the whole
  range. A series can enter or leave the ten mid-range, so where a band *ends* is a reliable reading and where it
  *starts* is not always one: a line beginning partway across may mean the fault started then, or only that it
  climbed into the top ten then.
- **A reason can only be excluded cluster-wide**, not per namespace. Something that is noise in one namespace and
  signal in another cannot be suppressed in just the first.
- **History begins when the export began.** A blank stretch at the left-hand edge of the 7-day panel means the
  exporter was not running yet, not that the cluster was quiet.
- **Current policy compliance is not here.** Kyverno's `PolicyReport` resources carry that state; events only
  ever show violation re-reports. Nor is anything a metric already answers — restart counts, pod phases, volume
  capacity all belong on a metrics dashboard. What events carry that metrics cannot is the *reason*, the
  control-plane decision, and the failures that have no metric at all.

## Adapting it

Every default in here — the exclusion lists, the noise floor, the 7-day window — is calibrated on one small
cluster and is expected to be changed. If you are running this somewhere else, you are also its maintainer:
[MAINTAINER.md](./MAINTAINER.md) covers the data contract the queries depend on, how to derive your own exclusion
lists, which parts of a query are load-bearing, and the traps in Kubernetes event data that return a plausible
wrong number rather than an error.
