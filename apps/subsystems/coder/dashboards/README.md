# Coder Workspace Memory dashboard

`coder-workspace-memory.json` answers one question about a Coder workspace: **is it in trouble right now, and if
so why**. It exists because every stock memory reading disagrees with reality on these pods, and the disagreement
runs in the dangerous direction — the numbers look alarming when the workspace is fine, and they look no worse
than usual when it is about to lose a process.

This document is for whoever is *using* it. Three places carry different things, and none repeats another:

- **Each panel's `description` tooltip** — hover the ⓘ in a panel's top-left corner for guidance on the panel in
  front of you: what it shows, how to read it, what to do next. That is the fastest answer when something is
  wrong.
- **This document** — how to use the dashboard as a whole: what each row answers, how to read the numbers, and
  what it cannot tell you.
- **[MAINTAINER.md](./MAINTAINER.md)** — why it is built this way: how the queries are shaped, which parts are
  load-bearing, and what silently breaks when they change. Read that one before editing anything.

## The reading this dashboard exists to correct

Measured on an idle workspace: the cgroup's `memory.current` was **97%** of its limit, Coder's own workspace tile
said **63%**, and genuinely unreclaimable memory — the part the kernel cannot take back when something asks — was
**23%**. The rest was page cache and reclaimable slab, handed straight back on demand. A second measurement taken
while this dashboard's queries were being validated showed **79%** working set against **28%** unreclaimable, the
difference being 3.9 GB of page cache.

Every stock Kubernetes memory panel shows the first number. Acting on it means restarting workspaces that are
perfectly healthy, and — worse — learning to ignore a reading that is nearly always high, including on the
occasions when it means something.

So this dashboard shows both numbers side by side, deliberately, and adds the one measurement that reports
**harm** rather than **level**: pressure stall information. Full is not the same as suffering, and PSI is what
tells them apart.

## What each row answers, and how to read it

The rows are named after questions rather than after the data they hold, and they are in priority order.

1. **Is this workspace in trouble right now?** Five small tiles across the top, then three gauges. Read the tiles
   first — they are the freshness and honesty checks, and they ignore the `Workspace` filter. Then read the three
   gauges *as a set*: unreclaimable %, working-set % and memory PSI. Unreclaimable high is the one to act on;
   working-set high on its own is not; PSI above zero means the workspace is already paying for it.
2. **How much genuine headroom is there, and how fast could it go?** The composition behind those gauges — where
   the memory actually is — plus the distance to the limit and the rate at which that distance is closing. This
   is the row that distinguishes a leak from a spike. The investigation behind this dashboard found spikes:
   70–220 MB/s, 8 GiB reached in as little as 43 seconds, with flat steady-state growth.
3. **Is it suffering, or merely full?** Per-container PSI for memory, CPU and I/O, plus node-level reclaim
   underneath. A workspace at 95% of its limit with PSI flat at zero is fine. The same workspace with PSI in the
   tens of percent is being destroyed by reclaim.
4. **What is the standing population doing over days?** Process and thread counts, two panels pinned to 7 days
   regardless of the time picker, and CPU. A workspace is not one program: editor servers, language servers,
   agents and MCP servers all stay running once started, and one MCP server measured during the investigation
   held 1.66 GB by itself. That standing population is what erodes the runway a spike has to cross.
5. **Did something die, and what was it?** The kernel journal, via Loki. See [below](#why-deaths-come-from-the-kernel-journal) —
   this is now the only place a container OOM is recorded at all. Two of the four panels are scoped to the
   `Workspace` selection and two are deliberately not; read them as a set.

In practice, work top to bottom. Confirm the tiles are green, read the three gauges together rather than
individually, and go down a row only if one of them says to.

## The tiles at the top, and why they are there

An empty panel and a healthy workspace look identical. If the pod is gone or a scrape has stopped, every chart
below renders empty and the dashboard reads as calm. The first three tiles are the only thing that separates
those cases, and they ignore the `Workspace` filter for the same reason.

| Tile | Reads | Means |
| --- | --- | --- |
| `Workspace containers scraped` | `NONE` | No workspace running, or cAdvisor has stopped returning them. Everything below is empty for the wrong reason. |
| `Newest sample age` | more than a minute or two | The scrape is degraded; the charts below are history, not now. |
| `Nodes not reporting cAdvisor` | non-zero | A node's cAdvisor endpoint is failing. A workspace scheduled there is invisible here while still running. |

The last two tiles keep the dashboard honest about itself:

- **`Containers this dashboard cannot attribute`** should always be `0`. Every per-workspace panel resolves a pod
  to a readable workspace name through a recording rule; a pod that rule has not caught up with drops silently
  out of the result rather than erroring. Non-zero for a minute after a workspace starts is that rule catching up.
  Non-zero persistently means a running workspace is missing from every chart below.
- **`Workspaces hidden by the Workspace filter`** is the size of the one control here that can hide a real
  problem. If it is non-zero, there are workspaces you are not looking at. Set `Workspace` to `All`.

## How to read the three gauges together

They are three views of the same container and they routinely disagree. The disagreement is the information.

| Unreclaimable | Working set | Memory PSI | Reading |
| --- | --- | --- | --- |
| low | low | 0 | Idle. Nothing to do. |
| low | **high** | 0 | **The common case, and it is fine.** The gap is page cache. Stock tooling would call this an emergency. |
| **high** | high | 0 | Genuinely full but not yet hurting. Watch the headroom and fill-rate row. |
| **high** | high | **non-zero** | Actively suffering. Reclaim is running and the workspace is losing time to it. Expect a kill. |
| low | high | **non-zero** | Look at node-level reclaim in row 3 — the pressure is probably coming from the node, not from this cgroup. |

## Why deaths come from the kernel journal

`singleProcessOOMKill: true` is set on every node in this cluster, which sets `memory.oom.group = 0`. A cgroup
OOM now kills the single offending process instead of the whole cgroup. The consequence is that **Kubernetes no
longer notices at all**: the container does not terminate, the pod never reports `OOMKilled`, the restart counter
does not move, and `container_oom_events_total` reads 0 through confirmed kills.

The kernel journal is the only remaining record. Row 5 reads it out of Loki. The victim's process name is the
finding — the investigation that produced this dashboard expected the editor server and found agent processes
instead.

The line names no namespace and no pod, only a cgroup path — but that path contains the pod UID, and row 5 reads
it back out and matches it against the pods of the workspaces you have selected. So the two headline panels
**are** about your workspace. The other two exist to stop you trusting them blindly:

| Panel | Scoped? | How to read it |
| --- | --- | --- |
| `Cgroup OOM kills in this workspace` | yes | The number you came for. Red at 1 or more. |
| `OOM victims in this workspace` | yes | Which process the kernel picked, and when. |
| `Cgroup OOM kills anywhere in the cluster` | **no** | Every namespace, every node. A big number here next to a `0` on the left is the normal case — most cgroup OOM kills in this cluster belong to workloads that have nothing to do with Coder. |
| `Pod generations this filter can see` | yes | How many of your pods the scoping can actually match. **If it reads `BLIND`, the two scoped panels are empty because they cannot see, not because nothing died.** |
| `Kernel OOM lines` | **no** | Raw lines from everywhere, with the pod UID parsed onto each one. The fallback when the tiles disagree. |

To resolve a UID from the raw lines by hand, expand a line, take its `pod_uid` field, and run
`kube_pod_info{uid="…"}` in Explore for the namespace and pod name.

Before this row was scoped it was cluster-wide throughout, which read as "your workspace was killed *n* times"
when the great majority of those kills belonged to an unrelated workload in another namespace. If you remember
that behaviour, the `anywhere in the cluster` tile is where that number now lives, correctly labelled.

## What it cannot tell you

- **The unreclaimable number is a floor, not a measurement.** True unreclaimable memory is
  `anon + shmem + unevictable + slab_unreclaimable + kernel_stack + pagetables + sec_pagetables + percpu + sock`.
  Prometheus exposes only `container_memory_rss` (≈ `anon`). Everything on this dashboard that says
  "unreclaimable" is that proxy, and it under-counts — real headroom is somewhat *less* than the headroom panel
  shows. This is stated rather than smoothed over because a precise-looking wrong number is worse than an
  admittedly approximate one.
- **It cannot tell you which process is using the memory.** Prometheus stops at the container boundary. The
  standing-population row shows you *how many* processes there are, and row 5 shows you which one the kernel
  eventually chose, but attributing a live gigabyte to a specific helper needs a look inside the workspace.
- **It attributes a kill to a workspace, but it cannot prove it saw every one.** The scoping matches the pod UID
  in the kernel line against the UIDs of your workspace's pods, and it can only match pods Prometheus still has a
  record of within the time picker's range. A kill against a pod that has aged out is absent rather than flagged.
  `Pod generations this filter can see` is there to bound that: read it before reading a `0`, and fall back to
  the raw, unfiltered lines at the bottom of the row when in doubt.
- **It cannot see a burst shorter than a scrape interval.** cAdvisor samples periodically; an allocation that
  starts and ends between two samples leaves no trace on any chart here except, possibly, a line in row 5.
  `Fastest fill observed in range` is a floor on the true peak for the same reason.
- **The two 7-day panels ignore the time picker.** Zooming into a 30-minute incident window elsewhere leaves them
  showing 7 days. That is intended — the long horizon is the one thing the rest of the dashboard cannot give you.
- **There is no CPU or memory limit context beyond the memory limit itself.** The workspace template sets no CPU
  limit, and throttling metrics are dropped upstream of Prometheus.
- **It says nothing about disk, network, or the Coder control plane.** coderd has its own metrics and its own
  alert conditions; see [`../README.md`](../README.md).

## Adapting it

The thresholds, the 6-hour default range and the 7-day pinned windows are calibrated on one small cluster running
one or two workspaces at 4–8 GiB limits. If you are running this somewhere else you are also its maintainer:
[MAINTAINER.md](./MAINTAINER.md) covers the metric contract the queries depend on, which parts are load-bearing,
and the traps that return a plausible wrong number rather than an error.
