# Coder Workspace Memory dashboard — design notes

This document is for whoever is *editing* `coder-workspace-memory.json`, or rebuilding it against another
cluster. It is the reasoning behind the dashboard: which properties of cgroup memory accounting and of this
cluster's metric pipeline forced each choice, which of those choices are load-bearing rather than taste, and what
silently breaks when they are changed.

Three places carry different things, and none repeats another:

- **Each panel's `description` tooltip** in the JSON — point-of-use reading guidance for whoever is looking at
  that panel. It says nothing about how the query is built, so a reviewer working from the tooltips cannot catch
  anything on this page.
- **[README.md](./README.md)** — how to use the dashboard: what each row answers, how to read the gauges
  together, and what the dashboard cannot tell you.
- **This document** — everything behind the panels. It is the only written home for that reasoning.

Anyone editing a query is expected to have read [Extending it safely](#extending-it-safely) first.

## Why these five questions, in this order

The rows are named after the questions they answer rather than after the data they hold;
[README.md](./README.md#what-each-row-answers-and-how-to-read-it) lists them. The order is priority order.
"Is it in trouble right now" is first because that is the only question this dashboard is opened to answer at
speed; the long-horizon standing-population row is fourth because it is the one that pays off weeks later.

The test for whether a panel belongs is whether it traces to one of those five questions. A panel that traces to
none should not exist, however interesting its data is. Two metrics were dropped on exactly that test — see
[Deliberately not built](#deliberately-not-built).

## The measurement problem this dashboard exists for

Every stock memory reading disagrees with reality on these pods, in the direction that causes harm. The measured
numbers are in [README.md](./README.md#the-reading-this-dashboard-exists-to-correct). The mechanism:

`container_memory_working_set_bytes` is `memory.current` minus inactive file cache. It still counts active page
cache and reclaimable slab, both of which the kernel returns the instant anything needs them. On a workspace
doing ordinary development work — compiling, indexing, reading a repository — that is a large and permanently
high number that means nothing.

What actually gets a process killed is memory the kernel *cannot* reclaim:

```text
anon + shmem + unevictable + slab_unreclaimable + kernel_stack + pagetables + sec_pagetables + percpu + sock
```

cAdvisor exports exactly one of those nine terms: `container_memory_rss`, which is approximately `anon`. **The
honest number is therefore not reconstructible from Prometheus at all.** The design decision that follows is the
most important one on this page: rather than compute a plausible-looking composite from the terms that happen to
be available, the dashboard ships the single available term, labels it as a proxy in every tooltip, and states
the under-count in [README.md](./README.md#what-it-cannot-tell-you). A precise-looking wrong number is worse than
an admittedly approximate one, and the whole point of this dashboard is that it does not lie about memory.

**PSI is what closes the gap.** `container_pressure_memory_stalled_seconds_total` measures time during which
every runnable task in the cgroup was blocked on memory — harm, directly, rather than a level from which harm is
inferred. It is the discriminator between "at the limit and fine" (high page cache, PSI zero) and "at the limit
and suffering" (reclaim thrashing, PSI non-zero), and no level-based metric can make that distinction at all.
An earlier version of the umbrella issue claimed per-container PSI needed a Kubernetes ≥1.33 feature gate. That
was wrong: all six `container_pressure_*` series are present and working today, verified live.

## The data contract

Rebuilding this elsewhere means reproducing this shape, or rewriting every query.

| Source | Series used | Notes |
| --- | --- | --- |
| cAdvisor (kubelet `/metrics/cadvisor`) | `container_memory_rss`, `container_memory_working_set_bytes`, `container_memory_cache`, `container_cpu_usage_seconds_total`, `container_processes`, `container_threads`, `container_pressure_{memory,cpu,io}_{waiting,stalled}_seconds_total` | No pod labels. `name` is the container ID, `instance` is the kubelet target address. |
| kube-state-metrics | `kube_pod_container_resource_limits{resource="memory"}`, `kube_node_info`, `kube_pod_info` | The only source of the memory limit — see below. `kube_pod_info` is used solely for its `uid` label, which is what bridges the kernel journal to a workspace. |
| kube-prometheus-stack recording rules | `namespace_workload_pod:kube_pod_owner:relabel` | The entire attribution mechanism. |
| node-exporter | `node_vmstat_pgscan_direct`, `node_vmstat_pgscan_kswapd`, `node_pressure_memory_stalled_seconds_total` | The two `pgscan` fields require a widened `--collector.vmstat.fields`; they are not collected by chart defaults. |
| Loki | `{job="systemd-journal", syslog_identifier="kernel"}` | The only record of an OOM kill. |

Four consequences worth internalising before editing a query:

- **`container_spec_memory_limit_bytes` is dropped** by the k3s ServiceMonitor's `metricRelabelings`
  (`infrastructure/subsystems/observability-core/k3s-monitoring/servicemonitor-k3s.yaml`). Every "% of limit" and
  "headroom" query therefore joins `kube_pod_container_resource_limits` from kube-state-metrics instead. If that
  drop is ever reconsidered, the queries here still work — but do not "simplify" them back to the cAdvisor series
  without checking that it is being kept.
- **coderd and workspace pods share the `coder` namespace**, so a pod-name prefix regex like `pod=~"coder.*"`
  matches both. Every query here separates them on `container="workspace"`, which is the workspace pod's only
  container and is not a name coderd's container uses. A `namespace` label filter alone is not sufficient and
  neither is a pod-name pattern.
- **cAdvisor carries no workspace identity.** Workspace pod names used to be opaque UUIDs and the Deployment name
  with them. That is now fixed at the source: the workspace template in `ppat/coder` names the Deployment after
  the workspace, so `namespace_workload_pod:kube_pod_owner:relabel`'s `workload` label is human-readable, and
  attribution costs one join and no new series. Pods created before that landed still carry the old
  `coder-<uuid>` form until they restart; both shapes match the `coder-.+` pattern the dashboard uses.
- **The `workload` label contains the workspace owner's username**, since workspace Deployments are named after
  owner and workspace. That is fine at runtime and must not appear in this repository — no dashboard JSON, no
  documentation and no PR description here should quote a real value.

## Attribution, and the way it fails silently

Every per-workspace panel has this shape:

```promql
sum by (workload) (
  <cadvisor series>{namespace="$namespace", container="workspace"}
  * on (namespace, pod) group_left(workload)
  namespace_workload_pod:kube_pod_owner:relabel{namespace="$namespace", workload_type="deployment", workload=~"$workspace"}
)
```

`group_left` against a recording rule is an inner join. A pod that exists in cAdvisor but not yet in the
recording rule — the rule evaluates on its own interval, downstream of kube-state-metrics, so a pod that has just
started or just restarted is briefly absent — **drops out of the product entirely**. It does not error and it
does not render a gap: the workspace simply is not on the chart, which looks exactly like a workspace that is
behaving.

The same silent drop happens if a workspace Deployment is ever named outside the `coder-.+` pattern the
`Workspace` variable's `regex` and `allValue` both use.

`Containers this dashboard cannot attribute` is the panel that catches both, and it is the single most important
panel on the dashboard for a reviewer to understand:

```promql
(count(container_memory_rss{namespace="$namespace", container="workspace"}) or vector(0))
-
(count(
  container_memory_rss{namespace="$namespace", container="workspace"}
  and on (namespace, pod)
  namespace_workload_pod:kube_pod_owner:relabel{namespace="$namespace", workload_type="deployment", workload=~"coder-.+"}
) or vector(0))
```

The left-hand count deliberately depends on **nothing** — no recording rule, no naming convention, no dashboard
variable — so it cannot be blanked by whatever broke the right-hand one. Verified in the failing direction by
substituting a pattern that matches no workload: the tile went from `0` to the full count of running workspace
containers, as it must.

Note also that `and on (...)` is used rather than `*` wherever the value is not wanted; unlike `group_left` it
keeps the left operand's labels and cannot fan out.

## Why the `Workspace` variable is a regex over `coder-.+`

The `workload` dimension in that recording rule includes coderd itself, whose Deployment is named exactly
`coder`. Selecting it would produce empty panels rather than wrong ones — coderd's container is `coder`, not
`workspace` — but an entry in the dropdown that can only ever return nothing is a trap. The variable's
`regex: /^coder-.+$/` removes it, and `allValue: coder-.+` mirrors that so the `All` option cannot reintroduce
it.

`allValue` is deliberately not `.*`. The two must stay in step: an `allValue` looser than the variable's `regex`
means `All` shows workspaces the dropdown cannot select individually.

## How deaths are attributed to a workspace

`singleProcessOOMKill: true` is rolled out to every node, setting `memory.oom.group = 0`. The consequences are
covered in [README.md](./README.md#why-deaths-come-from-the-kernel-journal); what matters to an editor is that
`container_oom_events_total` **exists, is scraped, and reads 0 through confirmed kills** (tracked in
ppat/homelab-ops-kubernetes-apps#3754, not being fixed soon). It is not a fallback. Do not add a panel for it.

Row 5 therefore reads the kernel journal. The log line carries no namespace and no pod name — only a cgroup path:

```text
oom-kill:constraint=CONSTRAINT_MEMCG,...,oom_memcg=/kubepods.slice/.../kubepods-burstable-pod<uid>.slice/cri-containerd-<container-id>.scope,task_memcg=...,task=<victim>,pid=<n>,uid=<n>
```

The path does spell the pod UID, with underscores where the Kubernetes UID has dashes. **The row shipped
cluster-wide in the first version on the belief that this could not be bridged. It can.** The bridge is three
pieces, and each one was checked live before being relied on:

1. **LogQL restores the UID.** `regexp` lifts the underscored UID out of `task_memcg=`, and `label_format` with
   Go template `replace` turns it back into a Kubernetes UID. This is the step the first version assumed did not
   exist — the substitution happens on the *log* side, so Grafana never needs a string function.
2. **Two hidden chained variables carry the workspace's UIDs.** `workspace_pods` resolves the `Workspace`
   selection to pod names through the same recording rule everything else here uses; `workspace_pod_uids`
   resolves those to `kube_pod_info`'s `uid`. Both are `label_values`, which Grafana evaluates over the
   **dashboard time range** rather than at `now` — so a pod deleted an hour into a six-hour window is still in
   the set, and the "a variable can only see pods that still exist" objection does not apply. It would apply to
   `query_result`, which is an instant query; do not switch them.
3. **The panels match one against the other**, anchored, with the unfiltered count and a coverage tile beside
   them so the match can be checked rather than trusted.

Two narrowings that genuinely do not work, and should not be re-attempted:

- **By namespace, or "all Coder pods as a class".** The cgroup path names the QoS class and the pod UID and
  nothing else. There is no namespace in it, so "every `kubepods` cgroup in the `coder` namespace" is not
  expressible — `kubepods` is every pod on the node. Scoping is per-pod-UID or it is nothing.
- **By Unix `uid=`.** Checked live and rejected on evidence: the workspace user's numeric UID is shared by
  unrelated workloads elsewhere in this cluster, so it is not a discriminator at all.

Container ID would also match exactly, but the pod UID is strictly better: it survives a container restart within
the same pod, and it is what `kube_pod_info` already carries.

### What the scoping can still miss, and why the row has three panels rather than one

The exposure is real and it is the invisible kind: a kill whose pod UID is not in `workspace_pod_uids` is not
*flagged*, it is simply not in the count, which is indistinguishable from no kill. That happens when the pod has
aged out of `kube_pod_info`, or when the `workload` recording rule never caught it. Measured over a 30-day window
during validation, 2 of the 95 cluster-wide kill lines belonged to pods Prometheus no longer had any series for
at all.

Munger's inversion is the whole design of the row: silently dropping a real kill for the reader's own workspace
is worse than showing kills that are not theirs, because the first failure is invisible and the second is merely
noisy. So the scoped count never stands alone:

| Panel | Filtered by `Workspace` | What it is for |
| --- | --- | --- |
| `Cgroup OOM kills in this workspace` | yes | The answer to the question the reader came with. |
| `Cgroup OOM kills anywhere in the cluster` | **no** | The old cluster-wide number, kept, and now labelled as what it is. It bounds the scoped one: if it is 0 there was nothing to hide. |
| `Pod generations this filter can see` | yes | The size of the filter's match set. `0` renders as `BLIND`, in red. A scoped `0` next to a `BLIND` coverage tile is not evidence of health. |
| `Kernel OOM lines` | **no** | Every line, every namespace, with `pod_uid` parsed onto it. The escape hatch when the tiles above disagree. |

Removing any one of the unfiltered panels turns a checkable filter back into an unfalsifiable one.

### Validation, in the failing direction

Run against live Loki and Prometheus over a 30-day window, with the variables interpolated exactly as Grafana
emits them:

- Cluster-wide, unfiltered: **95** kill lines across 8 distinct pods. **78 of those belonged to a DNS resolver in
  an unrelated namespace** — this is the misreading the row shipped with, sitting under a `Workspace` selector.
- Scoped to `Workspace = All`: **15**. Every Coder workspace kill, and nothing else.
- Scoped to a workspace that had been killed: **8**, matching the sum of that workspace's pod UIDs counted
  independently; victims resolved to a single process name.
- Scoped to a second workspace that had been killed: **7**, likewise matching, across two pod generations.
- **Failing direction — scoped to a workspace that has never OOMed: `0`**, rendered as `0` rather than "No data"
  because of the `or vector(0)`. Two such workspaces were checked.
- **Failing direction — the empty-variable case**, see the trap below.

## Presence, not magnitude, for the OOM panel

OOM kills are sparse and Loki returns gaps rather than zeros. A `state-timeline` draws a region from each sample
to the next, so an isolated kill either collapses to a hairline or gets stretched to the end of the range,
asserting a state that held for hours when the truth was one event. `status-history` draws a fixed block per
sample, which is what "it happened here" means. **Sparse categorical data wants status history; state timelines
are for data that genuinely holds a value between samples.** `showValue: never` keeps a single kill exactly as
visible as a run of twenty.

Grafana returns one frame per `victim`, and neither `sortBy` nor `organize` reorders across the frame array. The
`joinByField` (outer, on Time) followed by the `order` transformer with `orderByMode: "auto"` is what alphabetises
the rows; the same pattern, and the same reasoning, as
`infrastructure/subsystems/observability-core/alloy/dashboards/`.

## Traps that return a wrong number instead of an error

Each of these fails silently. None produces an error or an empty panel with a message.

- **`min(up{job="kubelet", metrics_path="/metrics/cadvisor"})` is the obvious scrape-health query and is unusable
  here.** This cluster's kubelet ServiceMonitor carries a target for a node that no longer exists: five targets,
  four nodes, and the fifth has been down 100% of the last 24 hours. `min` reads DOWN forever, and a warning that
  is always on is worse than no warning — a reader learns to ignore it, including on the day it means something.
  The shipped form counts *healthy targets against real nodes*
  (`count(kube_node_info) - count(up{...} == 1)`), which ignores a target that is never up and still goes red the
  moment a real node stops reporting. That stale target is a pre-existing cluster fault, not something this
  dashboard introduced, and this query stops depending on whether it is ever cleaned up.
- **An instant query cannot see past Prometheus' 5-minute staleness window.** A naive
  `time() - max(timestamp(container_memory_rss{...}))` freshness panel reads "no data" for a scrape that stopped
  an hour ago — indistinguishable from a workspace that was never running. The subquery form
  (`max_over_time(timestamp(...)[6h:1m])`) is what makes the panel able to report a large age rather than no age.
- **`deriv()` flattens a spike shorter than its window.** `deriv(...[5m])` fits a line across five minutes, so a
  30-second burst is averaged down by an order of magnitude. That is why the fill-rate row carries both a
  timeseries and a `max_over_time(...[$__range:5m])` stat: the stat is a floor on the true peak, and both are
  floors, and both tooltips say so.
- **`or vector(0)` matters more than it looks on the freshness tiles.** Without it, a count that matches nothing
  renders as "No data" rather than as `0` — and "No data" on a panel whose whole job is to distinguish "nothing
  is running" from "nothing is arriving" is precisely the ambiguity it exists to remove.
- **The two halves of the "hidden by filter" difference must use the same inner shape.** The left counts
  workspaces matching `coder-.+`, the right counts workspaces matching `$workspace`. Both are gated on
  `and on (namespace, pod) container_memory_rss{...}` so that stopped workspaces do not inflate the number.
  Dropping that gate from only one half still parses, still returns a number, and quietly reports workspaces as
  "hidden" that are simply not running.
- **A Grafana multi-value variable interpolated into `=~"$workspace"` becomes `(a|b)`, but a custom `allValue` is
  inserted verbatim.** That asymmetry is why `allValue` is written as a bare regex (`coder-.+`) and not as an
  escaped literal, and why it must be kept in step with the variable's `regex`.
- **LogQL's `=~` label filter is not anchored, and an empty alternation therefore matches every line.** This is
  the sharpest trap on the page, because it fires exactly when the filter has nothing to filter with. Checked
  live: a `pod_uid` filter against the empty alternation `()` returned **95 of 95** lines — the whole cluster —
  while the same filter against `^()$` returned `0`. An empty `workspace_pod_uids` (no workspace selected, recording rule cold, kube-state-metrics
  down) is exactly how that empty alternation arises, so **the `^` and `$` around `${workspace_pod_uids:pipe}`
  are the difference between failing closed and silently reverting the panel to the cluster-wide count this
  change exists to remove.** They are not stylistic.
- **`${var:pipe}` is used rather than bare `$var` for the same reason.** Loki's default multi-value formatter
  already wraps values in parentheses, so `(${workspace_pod_uids})` would nest them; `:pipe` emits a bare
  `a|b|c` and the parentheses in the query are the query's own. Either works today, but only one of them is
  obvious about where the grouping comes from.
- **`allValue` on the two hidden variables must stay `null`.** With `allValue: null`, `$__all` expands to the
  concrete list of matching values. Setting it to `.*`, by analogy with the `Workspace` variable, would make
  `All` interpolate as `^(.*)$` and quietly restore the cluster-wide behaviour — the same defect, reintroduced
  through a field that looks like tidying.
- **The pod-UID regex must not assume a QoS class or a cgroup driver.** `kubepods-burstable-pod<uid>.slice` is
  what this cluster happens to emit; Guaranteed pods sit at `kubepods-pod<uid>.slice` with no QoS segment, and a
  cgroupfs driver writes `pod<uid>` with dashes intact. The shipped regex matches the UUID *shape* after a
  literal `pod`, accepting `_` or `-` as the separator, so all three forms parse. A tighter regex written
  against the observed path would silently drop every Guaranteed workspace.

## Shipping it through GitOps

- **A templating engine will eat the dashboard's own variables.** Dashboard JSON is dense with bare `$` tokens —
  `$datasource`, `$logs`, `$namespace`, `$workspace`, `$workspace_pods`, `$workspace_pod_uids`,
  `$__rate_interval`, `$__range`, `$__interval`. Flux's
  post-build substitution expands bare `$name` as well as `${name}`, so without
  `kustomize.toolkit.fluxcd.io/substitute: disabled` on the generated ConfigMap every one of them becomes an
  empty string and the dashboard loads cleanly with every panel silently unconfigured. The failure looks like a
  Grafana problem and is not one.
- **A content-hashed ConfigMap name orphans the old dashboard on every edit.** Flux prune is disabled
  cluster-wide here, so `disableNameSuffixHash: true` is mandatory; without it the sidecar sees both copies and
  serves duplicates under the same uid.
- **The label and the folder annotation fail silently when wrong.** The sidecar discovers dashboards purely by
  label, so a typo applies cleanly and the dashboard simply never appears. `ci/test/apps-coder/validate-coder-metrics.yaml`
  asserts the ConfigMap by unsuffixed name, with the label and both annotations, for that reason.
- **`dashboards/` is its own kustomization, not a `configMapGenerator` entry in the parent.** `generatorOptions`
  is file-global: in the parent it would label every generated ConfigMap in this module as a dashboard for the
  sidecar to parse, and strip the name-suffix hash from any that needs it.

## Deliberately not built

- **A panel for `container_oom_events_total`.** It exists, it is scraped, and it reads 0 through confirmed kills.
  A panel showing it would be a permanently green "no OOMs here" tile that is wrong exactly when it matters —
  the single most harmful thing this dashboard could contain.
- **A panel for `container_ulimits_soft`.** Checked live: this cluster exports only `ulimit="max_open_files"`.
  There is no process-count rlimit series, so it answers nothing about the standing-population question it looks
  like it should answer, and it traces to none of the five questions.
- **A composite "true unreclaimable" figure.** Summing the terms Prometheus happens to expose and calling the
  result unreclaimable memory would produce a number that looks authoritative and is wrong by an unknown margin.
  The single-term proxy plus an explicit statement of the under-count is the deliberate choice; see
  [the measurement problem](#the-measurement-problem-this-dashboard-exists-for).
- **A "time to exhaustion" tile.** Headroom divided by fill rate is arithmetic anyone can do from two panels that
  are already here, and rendering it as a countdown gives a hostage-to-fortune prediction the underlying data
  cannot support. The two inputs are shown; the division is left to the reader, and the README explains it.
- **`coderd_*` metrics.** The Coder ServiceMonitor is deployed and 1,700-odd `coderd_*` series are flowing, but
  the `coderd_agentstats_*` family is network and session activity — `execution_seconds`, `tx_bytes`, `rx_bytes`,
  `connection_count`, `connection_median_latency`, per-IDE `session_count_*`. There is no CPU or memory gauge in
  it. Nothing there belongs on a memory dashboard.
- **Alerting rules.** This estate deliberately runs no AlertManager routing; a human reading this dashboard is
  the detection mechanism. If that changes, the thresholds encoded in the gauges are the starting point, and PSI
  is the condition to alert on rather than any level.
- **A workspace-name label on the kernel log lines.** Resolving `pod_uid` to a readable workspace name inside the
  panel would need a join across two datasources, which Grafana cannot do in a query and which a transformation
  can only fake by re-querying. The UID is printed on every line and `kube_pod_info{uid="..."}` resolves it in
  Explore; a homegrown lookup would be one more thing that can be stale without saying so.
- **Removing the OOM row rather than scoping it.** This was the alternative if the scoping had not held up, and
  it is the right answer to a panel that cannot be made correct — the same reasoning that keeps
  `container_oom_events_total` off the dashboard. It is recorded here because the scoping *did* hold up, and the
  bar it had to clear was "better than nothing at all", not "better than what shipped".
- **Data links.** There is no second dashboard worth navigating to and no drill-down that a link could narrow
  usefully. A link added later must use `/d/${__dashboard.uid}/…` rather than a hardcoded uid or a bare `?` query
  string; see the alloy dashboard's MAINTAINER for why both of those fail.

## Extending it safely

Nothing in CI validates the *structure* of these queries. The pre-commit gate checks that the JSON parses, and
the chainsaw suite asserts the ConfigMap's name, label and annotations. That protects the delivery path; it does
not protect the panels.

The invariants below are enforced only by review, and this list is their only written home.

Treat each of these as a defect if removed, not as cleanup:

- **`container="workspace"` on every cAdvisor selector.** It is the only thing separating workspace pods from
  coderd and from the Postgres cluster in the same namespace.
- **`Containers this dashboard cannot attribute`, and its left-hand count depending on nothing.** Removing it, or
  "simplifying" it to use the same join as everything else, removes the dashboard's only check on its own
  attribution.
- **`Workspaces hidden by the Workspace filter`.** A control that can hide a real problem has to display its own
  size.
- **The three freshness tiles' independence from the `Workspace` variable.** A liveness check a filter can blank
  is not a liveness check.
- **`or vector(0)` on every freshness and difference tile.** See the traps above; without it those panels report
  "No data" for the state they exist to distinguish from "No data".
- **Both the unreclaimable gauge and the working-set gauge, side by side.** Dropping the working-set one as
  redundant removes the comparison the dashboard was built to show; dropping the unreclaimable one reproduces the
  lie.
- **The unreclaimable panels being labelled as a proxy in their tooltips.** The under-count is the honest part.
- **The PSI row.** It is the only thing on the dashboard that measures harm rather than level, and it is what
  makes a high working-set reading safe to ignore.
- **`timeFrom: 7d` on the two standing-population panels.** Following the dashboard range instead surrenders the
  one capability the rest of the dashboard cannot provide.
- **The OOM row's two scoped panels being scoped, and its two unscoped panels being unscoped.** Four panels, two
  of each, and the pairing is the design: the scoped ones answer the reader's question and the unscoped ones are
  what make a `0` on them falsifiable. Filtering `Kernel OOM lines` removes the escape hatch; dropping
  `Cgroup OOM kills anywhere in the cluster` or `Pod generations this filter can see` removes the check. See
  [above](#how-deaths-are-attributed-to-a-workspace).
- **The `^` and `$` anchoring `${workspace_pod_uids:pipe}`.** Without them an empty variable matches every line
  in the cluster. See [the traps](#traps-that-return-a-wrong-number-instead-of-an-error).
- **`allValue: null` on `workspace_pods` and `workspace_pod_uids`**, which is the opposite of what the
  `Workspace` variable needs and for the opposite reason.
- **`status-history` rather than `state-timeline`** on the victims panel — see
  [presence, not magnitude](#presence-not-magnitude-for-the-oom-panel).
- **`allValue: coder-.+` in step with `regex: /^coder-.+$/`** on the `Workspace` variable.
- **`kustomize.toolkit.fluxcd.io/substitute: disabled` and `disableNameSuffixHash: true`** on the ConfigMap.

When adding a panel, state which of the five questions it answers first. If the answer is "it's interesting",
that is a reason not to add it.

**Verify by disagreement, not by inspection.** Every trap on this page returns a plausible number, so a query
that looks right and runs without error is no evidence at all. Two habits follow:

- **Run the exact shipped expression**, variables interpolated as Grafana would, rather than a simplified version
  of it. A hand-reconstructed query is evidence about the reconstruction.
- **Test in the failing direction.** Before believing a panel, construct the input that should break it and
  confirm it does. Every panel here was checked that way: the attribution tile against a pattern matching no
  workload, the hidden-by-filter tile against a `Workspace` selection matching nothing, the two memory gauges
  against each other. The last of those is the one that keeps paying — the gap between them was 79% against 28%
  at the moment of validation, and a change that closes that gap has broken one of them.

Panel `description` tooltips are part of the change, not documentation of it: a panel whose query changes shape
usually needs its tooltip re-read, since the tooltip is the only guidance most readers will ever see.

## Limits on the design itself

What constrains a *reader's* conclusions is in [README.md](./README.md#what-it-cannot-tell-you). What constrains
an editor:

- **The thresholds are one cluster's.** 60/75/90% on the unreclaimable gauge and 1/5/20% on the PSI gauge are
  judgement calls calibrated against workspaces with 4–8 GiB limits. They are a starting point elsewhere.
- **Everything here stops at the container boundary.** The question "which process is holding the memory" is
  genuinely unanswerable from Prometheus, and the standing-population row is the closest approximation available
  — a count, not an inventory. In-workspace tooling is the right instrument for that, and lives in `ppat/coder`.
- **The node-level reclaim panel is cluster-wide.** node-exporter series carry `instance`, not `node`, and
  nothing joins them to the node a given workspace is scheduled on. Reading it requires knowing which node the
  workspace is on, which this dashboard does not tell you.
- **The `pgscan_*` fields are a local configuration.** They are absent from node-exporter's default
  `--collector.vmstat.fields` regex and exist here only because that was widened for this investigation. On
  another cluster that panel will be empty until the same change is made; its `noValue` says so.
