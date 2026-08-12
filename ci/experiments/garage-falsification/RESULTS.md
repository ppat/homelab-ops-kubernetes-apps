# Results

Verdicts against the pre-registered kill criteria in `README.md`. Fail-first result reported
alongside the real result for every test that has one. Raw data in `results/`.

## Verdict summary

| Test | Verdict | Confidence |
| ------ | --------- | ------------ |
| H1 — RSS/LIST at scale | **NOT KILLED (partial) — central claim unsupported** | Real data to 500k only; 1M+ not reached; Garage used 1.81× MinIO's RSS at the only checkpoint measured on the same host for both, see below |
| H2 — unclean-shutdown durability | **NOT KILLED (pilot scale)** | 5/25 hard-reset iterations, 8/25 kill-9 iterations; H1-instance data-loss confound investigated, most plausible alternative ruled out (not independently reproduced) |
| H3 — ListObjectsV2 `db//` | **NOT KILLED — original finding was a test artifact, reversed on correction** | Raw API retest confirmed on both backends: Garage self-consistent, MinIO write-rejects; CNPG e2e still not reached |
| H4 — Expiration reclaims space | **VOID (original) → REFUTED ON RETEST** | `du` reclaims at ~602–632s once the fail-first and object-dedup defects are fixed; sub-3KB inline path (95.4% of the estate) remains untested — see "Known blind spots" |
| H5 — Longhorn restore | **SKIPPED** | Real infra blocker, documented, not worked around |
| H6 — Terraform 1.6.6 backend | **PASSED** | Full pre-registered flow, clean |

---

## Known blind spots (read before trusting a "not killed"/"cleared" reading anywhere below)

- **The sub-3KB inline path is 95.4% of this estate's objects and is untested by anything in
  this run.** Garage stores any object under `INLINE_THRESHOLD` (3072 B) inline in LMDB — no
  `Version`, no `BlockRef`, no block written to `data_dir` at all. Measured directly
  (`h4-lifecycle-expiration/h4c_inline.sh`): 20,000 × 512 B objects grew `data_dir` by
  **exactly 0 bytes**, while 200 × 1 MiB objects grew it by 209,722,600 B. Both H4's original
  run and its retest used 1 MiB objects exclusively — neither says anything about whether the
  dominant, sub-inline-threshold object shape ever reclaims. `du` on `data_dir` is
  structurally the wrong instrument for that majority: LMDB does not return freed pages to the
  filesystem, so `du` will not shrink there even when reclamation is working correctly.
  Reclamation for small objects runs through the 24h `TABLE_GC_DELAY` metadata-tombstone path
  instead; the right instruments are object count and metadata growth *rate*, not `du`. This
  needs a dedicated ≥24h, two-cycle run before it can be called either way.
- **H1 is unfinished and its central claim is on the line, not confirmed.** Only the 100k/500k
  checkpoints were reached against a 3.44M target; the RSS growth curve cannot yet be
  distinguished from superlinear with two points; and at the only checkpoint measured on the
  same host for both engines, Garage used 1.81× MinIO's RSS. See the H1 section below — do not
  read "not killed" there as "cleared."
- **A pre-registered kill criterion (H4) fired, then was invalidated by defects in the test
  itself, not by new evidence about Garage.** That sequence, not the retest's eventual RECLAIMED
  result, is the most instructive part of this run — see "The standing rule this harness is
  built around" in `README.md`.

---

## H1 — RSS and LIST latency at 3.44M sub-1KB objects

**Fail-first**: loader against a 512 MiB tmpfs `metadata_dir`, pre-filled to ~32 MiB free.
Loader correctly detected failure: `PUT #34867 raised: ... LMDB: No space left on device`.
`verdict=DETECTOR-OK`. The loader really writes what it claims and checks errors.

**Real run — checkpoints reached**:

| Checkpoint | Garage RSS | Garage LIST p50 / p99 | MinIO RSS | MinIO LIST p50 / p99 |
| --- | --- | --- | --- | --- |
| 100,000 | 217.9 MiB | 7.4 ms / 64.4 ms | 522.2 MiB | 2.2 ms / 92.1 ms |
| 500,000 | 947.1 MiB | 11.8 ms / 91.1 ms | 523.4 MiB | 4.4 ms / 110.0 ms |
| 500,000 (post-restart)† | — | — | 425.8 MiB | 3.9 ms / 79.9 ms |
| 1,000,000 | **not reached — see below** | | | |
| 2,000,000 | not reached | | | |
| 3,439,460 | not reached | | | |

† The Docker VM had to be repeatedly hard-reset for H2's mechanic (see "What broke" in
README). H1's containers died at the *first* reset and sat idle through H2's remaining 4
resets before being noticed and restarted — a real operational mistake in how this session
sequenced two experiments on one host, not a Garage/MinIO property. The 500,000 checkpoint
was re-measured after that restart (cold containers) as a sanity check.

**The resumption attempt itself stopped partway to 1,000,000, for a reason that turned out to
be directly relevant to H2**: partway through re-loading toward 1M, `h1-garage`'s bucket and
access key had silently vanished — `garage repair --yes tables` reported no errors, but
`garage bucket list`/`garage key list` came back completely empty even though the node's own
identity and cluster layout survived intact. This is the exact same reset event H2's iteration
1 used, and `h1-garage` runs Garage's *default* config (`metadata_fsync` unset → `false`,
matching production) — see the H2 section below ("An unplanned, large-scale counterexample")
for the full account. Rather than silently re-bootstrap and keep going as if nothing had
happened, the H1 run was stopped here: continuing past an unexplained metadata loss on the
very instance being measured would have produced RSS/latency numbers of unknown provenance
(new cluster? partially-recovered one? unclear), which is worse than honestly reporting the
checkpoint this run actually reached under real conditions.

**What the 100k→500k trend already shows**: Garage's RSS **more than quadrupled** (217.9 →
947.1 MiB) between the two lowest checkpoints while the object count only grew 5×. That is
**not** superlinear: 5× objects → 4.35× RSS is an exponent of ln(4.35)/ln(5) ≈ **0.913**,
marginally *sub*linear. (An earlier reading of this same data called the trend "trending
slightly superlinear" — corrected here; that reading was simply wrong about the arithmetic.)
The real concern here is the *level*, not the curvature: MinIO's RSS was flat (~523 MiB)
across both checkpoints, so at the only checkpoint measured for both engines on the same host
(500,000 objects), **Garage used 1.81× MinIO's RSS (947.1 vs 523.4 MiB)**. H1's whole claim is
that Garage holds this workload at *materially lower* RSS than MinIO — that claim is currently
**unsupported** by this run's data, and this document should say so plainly rather than let
the "not killed" verdict below read as vindication.

**Extrapolating to 3.44M against the 6 GiB kill criterion** (labelled as extrapolation, not
measurement — two points cannot distinguish between these models): proportional-from-500k →
6.36 GiB (breaches the criterion); two-point linear fit → 6.16 GiB (breaches); power-law fit
at the measured exponent 0.913 → 5.38 GiB (clears). All three land within ±10% of the 6 GiB
threshold, and the three models disagree on whether it's breached — this run's two data points
genuinely cannot settle it. The 1M/2M/3.44M checkpoints this run did not reach are what would.

**A new sizing input worth recording**: `metadata_dir` runs roughly **1.6–2.6 KiB/object**
across the measurements this run happened to take (the inline-object probe: 32.5 MB for 20k
objects ≈ 1.6 KiB/object; the H1 Garage instance itself: ~1.4 GB at ~550k objects ≈ 2.5
KiB/object). Extrapolated to 3.44M objects, that's **~5.6–9 GB of `metadata_dir`** — a real
sizing input for `garage_metadata_size` regardless of how the RSS question resolves.

**Verdict**: **NOT KILLED, but NOT CLEARED either, and the central claim is currently
unsupported** — the pre-registered kill criteria (RSS > 6 GiB at 3.44M; p99 LIST > 1s at
1.86/s; superlinear 1M→3.44M growth) were not reachable in the time available, and the growth
exponent measured so far does not itself indicate superlinearity. But H1's claim was never "not
superlinear" — it was "materially lower RSS than MinIO," and on the one apples-to-apples
checkpoint this run has, Garage used *more* RSS, not less. Do not read "not killed" here as
"cleared."

**Keyspace**: synthetic (see README "Environment constraints") — no read-only production
credentials were obtainable in this session. Shape (prefix-clustered, two key families,
matched size distribution) reproduces the documented pattern; absolute latency numbers are
indicative of relative Garage-vs-MinIO behavior on the same host, not of production latency.

**Rerun to complete this test**: `bash h1-rss-list/loader.py` resumes from
`h1-rss-list/{minio,garage}-state.json` automatically — just relaunch both loaders per
`h1-rss-list/run.sh`'s pattern and let them run uninterrupted (do NOT run H2's hard-reset
mechanic on the same host concurrently) until the 3,439,460 checkpoint completes.

---

## H2 — unclean-shutdown metadata durability (the most important test here)

### Fail-first: two findings, not one

**First run, as literally specified ("dd the last 4KiB off data.mdb")**: `verdict=DETECTOR-BROKEN`
on 11 of 12 cells (came back CLEAN, not CORRUPT). **This is not a Garage durability result —
it's an artifact of testing a near-empty database.** LMDB's meta pages live at the head of the
file; a freshly-bootstrapped test cell's tail 4 KiB is very likely never-written free space.
Root-caused, documented in `h2-durability/corrupt_cell.sh`, fixed to corrupt head+tail.

**Second run, after the fix**: all 12 cells correctly report `verdict=CORRUPT`, all via a
genuine `garage repair --yes tables` failure (container crash-loop / RPC refused), not the
substring-match false positive that had briefly masked the real result one debugging step
earlier (see README). `verdict=DETECTOR-OK` for all 12 cells. **This is the run that
establishes the detector can be trusted** — see `results/h2-failfirst.jsonl`.

### Real matrix results

**Scale actually completed vs pre-registered 25 iterations/cell/mechanic** — reported exactly,
not rounded:

| Mechanic | Iterations completed | Cells × iterations checked | CLEAN | DATA-LOSS | CORRUPT |
| --- | --- | --- | --- | --- | --- |
| `kill -9` mid-PUT-stream | ~8 (stopped early, see below) | 91 | 90 | 0 | 1 |
| Hard reset (`sysrq b`) | 5 | 60 | 45 | 15 | 0 |

**kill-9's one CORRUPT** (`nfsv4.1__sqlite-fsync`, iteration 6): `garage repair --yes tables`
logged `ERROR ... DB error: Sqlite: timed out waiting for connection`. The very next iteration
(7) on the same cell came back CLEAN. Read as likely a transient SQLite connection-pool
contention event under NFS latency immediately after a kill-9 restart, not confirmed file
corruption — but it is the *only* engine/substrate pairing that produced any anomaly at all
under either mechanic, worth specific attention in a longer run rather than dismissing as
noise.

**kill-9 stopped at ~8/25 iterations deliberately**, to free the VM's 4 vCPUs for the
hard-reset mechanic before running out of session time — the brief itself says the hard-reset
mechanic is the one that actually tests `fsync` and kill-9 "demonstrates nothing" on its own;
getting hard-reset done at a smaller N was judged more valuable than a complete kill-9 run
plus a rushed or truncated hard-reset run.

**Hard-reset's every DATA-LOSS is on `tmpfs-loop`, and only `tmpfs-loop`** (15 = 3 engine
configs × 5 iterations, exactly). This is the fast negative control working exactly as
designed: a hard reset genuinely destroys a tmpfs-backed substrate's contents, which is the
proof this mechanic really does drop the page cache rather than merely killing a process (see
"A finding about this VM itself" below for the much larger, unplanned proof of the same thing
this session got for free). **Zero corruption and zero data loss on ext4-local, ext4-iscsi,
or NFSv4.1, at any engine config, across all 5 hard-reset iterations** — including
`lmdb`+`metadata_fsync=false`, the documented-risky default.

### An unplanned, large-scale counterexample: H1's own Garage instance lost its metadata to the same reset

While recovering from H2's iteration-1 reset, H1's `h1-garage` container (default config,
`metadata_fsync` unset → `false`, exactly matching production) was found to have survived the
node identity/cluster layout intact but with **`garage bucket list` and `garage key list` both
completely empty** — the bucket holding ~550,000+ real PUT objects and its access key were
both gone. `garage repair --yes tables` reported no errors and no ERROR/PANIC log lines
(engine healthy) — by this harness's own H2 classification, that's **(a) process starts: yes,
(b) repair clean: yes, (c) acknowledged writes readable: no → DATA-LOSS**, at a scale (an
entire bucket + key + every object in it, after roughly 40 minutes of uptime and continuous
write activity) vastly larger than anything the small, short-window H2 iterations above
exercised. This happened by accident, to infrastructure that was never intended as a H2 test
cell, on the exact same reset event that left every deliberate H2 ext4/NFS cell CLEAN. It is
the single strongest piece of evidence in this entire run that `metadata_fsync=false` is a
real, live risk, not a theoretical one — and it directly contradicts a naive reading of H2's
"5/5 clean" result above. Weigh this anecdote, not the small-scale 5/5, as the more reliable
signal about `fsync=false` from this session.

**The obvious alternative explanation was checked and ruled out.** The alternative reading of
this counterexample is that nothing was actually lost — Docker auto-created an empty
bind-mount source after the reset (the exact failure mode `post_hardreset_recover.sh` exists
to guard against, see "A finding about this VM itself" below) and Garage simply bootstrapped a
brand-new, empty cluster there, which would misreport as "everything survived, empty" rather
than real data loss. If that had happened, the node's identity (`node_key`) would necessarily
have been regenerated. It was not: `node_key`'s mtime is 02:43:58, matching the instance's
original bootstrap time, and `cluster_layout` likewise carries the original timestamp; there is
no shadow directory under the mountpoint holding a second, fresh dataset; and the 1.4 GB LMDB
file plus 2.7 GB of now-orphaned blocks are still on disk. So this was reading the same,
original metadata store the whole time, and that store lost its bucket and access-key tables
while plain files written 20+ minutes earlier on the same host survived the same reset — the
signature of an LMDB write that was acknowledged but never `fsync`'d, not of a fresh bootstrap.
The deliberate H2 cells' much shorter ~7s write-to-reset gap, against a 5s kernel background
writeback interval (`dirty_writeback_centisecs`), is exactly why they were too loose a race to
catch the same failure (see the caveat immediately below). **This was not independently
reproduced** — it is a single accidental occurrence, and its most plausible alternative
explanation is what was checked and ruled out, not a second confirming instance.

### Read the 5/5 hard-reset cell result carefully — it is weaker evidence than it looks

**Do not read "5/5 clean, including fsync=false" as "fsync=false is safe"** — see the H1
counterexample immediately above for why. This harness's
per-iteration write window is short (~15s) and the reset lands ~7s in; a real gap of several
seconds elapses between the small "acknowledged" writes and the reset trigger. Linux's own
background writeback (`dirty_writeback_centisecs`, default 5s intervals) can flush dirty pages
to disk on its own, with no `fsync` call from Garage at all, well within that gap. **This
run's design may not create a tight enough race to actually stress the `fsync=false` gap** —
it's entirely possible ordinary kernel writeback flushed the exact bytes this harness checks
before the reset landed, regardless of what Garage's own `metadata_fsync` setting was. A
harder version of this test would trigger the reset within milliseconds of the acknowledged
write, not seconds. This caveat is exactly why this verdict is "NOT KILLED (pilot scale)" and
not "PASSED" — the claim under test needs a materially tighter race before 0/5 corruption
means anything definitive about `fsync=false`.

### A finding about this VM itself, discovered mid-run (real, and directly relevant to using this VM for repeated hard resets)

The Docker VM's `/opt/build-scratch`, `/opt/docker-install`, and `/var/lib/containerd` are
bind-mounted from subdirectories of the PVC-backed `/var/lib/docker` by cloud-init's
`runcmd` — which is a **first-boot-only** cloud-init stage. A genuine reboot (this VM's own
provisioning script's comments make clear this was known to be a first-boot mechanism, but
its interaction with a mid-session in-guest reboot specifically had not been exercised
before) does not re-run `runcmd`, so **every one of the 5 hard resets in this run broke
Docker** (`dockerd`'s binary lives behind one of the missing bind mounts) and required manual
recovery: restore the 3 bind mounts, restart `docker`, and — this is the part that would have
silently corrupted the whole H2 result set if missed — **stop any auto-restarted containers
before re-establishing the H2 substrate mounts** (iSCSI login, NFS mount, tmpfs+loop),
because Docker auto-creates empty directories at missing bind-mount sources and Garage will
happily bootstrap a brand-new empty cluster there, which would misreport as "everything
survived, empty" rather than "the real data is sitting inaccessible behind a mount that
hasn't come back yet." This is now `h2-durability/post_hardreset_recover.sh`'s entire reason
for existing, and it means **this VM's own provisioning is not currently reboot-safe** —
worth fixing upstream in `homelab-ops-kubernetes-clusters` regardless of the Garage decision,
since any future test needing a real reboot on this VM will hit the same trap.

One more, smaller instance of the same underlying phenomenon happened to this harness's own
tooling: a script (`post_hardreset_recover.sh`) `scp`'d to the VM's root ext4 filesystem
seconds before triggering a reset came back as a file of all zero bytes — a live, unplanned
demonstration of exactly the "unclean shutdown loses recently-written, non-fsynced data"
mechanism this entire test exists to characterize, just happening to the harness instead of
to Garage.

### What the outcomes mean (per the pre-registered interpretation)

- **NFSv4.1 passing → would cancel the substrate workstream, IF this were a confirmed result.**
  It is not confirmed at this scale/iteration count/race-tightness — see the caveat above.
  Treat as a promising early signal that justifies extending this exact test, not as
  license to skip the substrate workstream.
- **No cell surviving the power-loss variant** did not happen (ext4/NFS all survived) — so
  this run does not support "Garage is unsuitable at any substrate."
- **`lmdb`+`fsync=true` on ext4-iscsi corrupting above the local-disk control rate** did not
  happen (0 corruption on either substrate) at this iteration count.

**Rerun to strengthen this result**: extend `h2-durability/run_kill9.sh` to the full 25
iterations, and repeat the `hardreset_prep.sh`/manual-reset/`post_hardreset_recover.sh`/
`hardreset_verify.sh` cycle to 25 iterations, ideally shortening the write-to-reset gap
(reduce `--large-duration-s` and the prep-to-trigger sleep in `hardreset_prep.sh`) specifically
to close the writeback-timing gap described above.

---

## H3 — `ListObjectsV2` and the Barman trailing-slash prefix

**This section's original verdict was reversed on correction. Read the retest below, not the
original probe, as the finding.**

**Original probe (kept here for the record, reclassified)**: reproduced against MinIO first,
`ListObjectsV2(Prefix="db//")` raised `ClientError: XMinioInvalidObjectName` (HTTP 400).
Against Garage v2.3.0, the identical call returned **HTTP 200, `KeyCount=0`, empty
`Contents`**, even though `ListObjectsV2(Prefix="db/")` on the same bucket returned the 3
seeded objects. This was originally read as Garage silently no-opping a retention job. It is
not: the probe seeded keys with a **single** slash (`db/base/...`) and then listed with a
**double**-slash prefix (`Prefix="db//"`). S3 keys are opaque byte strings with no path
normalization — `db//base/x` and `db/base/x` are different keys, so a `db//` prefix genuinely
matches nothing when only single-slash keys exist. HTTP 200 with an empty list is **correct
AWS behavior** for that mismatched pairing, not a defect. The original classifier hardcoded
that pairing as "worse than MinIO," which is what produced the wrong verdict.

**The real barman scenario is different**: a trailing slash in `destinationPath` makes
barman-cloud both **write and list** with the doubled separator — the actual question is
whether a backend that wrote `db//base/...` can also find it again under `Prefix="db//"`.
Retested on both backends with that corrected pairing (`h3-listobjectsv2-barman/h3b_probe.py`,
driven by `h3b_run.sh`):

- **Garage**: `PUT db//base/...` succeeds → `ListObjectsV2(Prefix="db//")` returns all 3
  objects → `DeleteObjects` on the listed keys prunes them → re-list is empty.
  **`verdict=SELF-CONSISTENT`.**
- **MinIO**: the same `PUT db//base/...` is **rejected outright**
  (`XMinioInvalidObjectName`), and the same list call throws. **`verdict=WRITE-REJECTED`.**

So on the scenario that actually matters — a doubled-separator misconfiguration reaching the
S3 API — **Garage handles it correctly end-to-end, and MinIO is the non-conformant backend**,
not the other way around.

**`UPSTREAM_ISSUE_DRAFT.md` has been deleted, not filed.** It would have reported
AWS-conformant behavior as a Garage bug, and it was internally incoherent on its own terms: its
"Expected" section listed the observed HTTP-200-empty-on-a-mismatched-prefix outcome as one of
its own two acceptable outcomes, while the rest of the draft called that same outcome the
defect.

**The one-character `destinationPath` fix identified during this exercise is still correct**
— but for the opposite of the original reason. It matters for **MinIO's** sake, on the
non-migrating `nas` instance: MinIO is the backend that write-rejects a doubled separator
outright, which is the operationally worse failure mode (backup writes fail loudly) if
`destinationPath` is ever misconfigured there. It is not needed to protect Garage from this
particular failure.

**Caveat, unchanged by the correction**: both the original probe and the retest verify the raw
S3 API layer, not barman-cloud's actual path-construction logic — confirming barman-cloud
itself never produces a doubled separator (or always produces one consistently on write and
list) is a separate, not-yet-done check. The CNPG + barman-cloud-plugin end-to-end assertion
(real deletions under a retention policy) was **still not attempted**, descoped for time per
the brief's own Pareto guidance (H1/H2 first). **Marked not-reached, not silently downgraded.**

**Verdict**: **NOT KILLED.** The originally reported "Garage worse than MinIO" finding was a
test-construction artifact, not a Garage defect. On the corrected, operationally realistic
pairing, Garage is the backend that behaves correctly and MinIO is the one that fails
(loudly, which is the safer failure mode of the two, but a failure nonetheless).

---

## H4 — plain `Expiration` on a non-versioned bucket actually reclaims space

**This section's original verdict (NOT-RECLAIMED / KILLED) was VOID, not negative — see the
three defects below — and the corrected retest REFUTES it: reclamation works, at ~602–632s.**

### Why the original result is void, not negative

Three independent defects in the original test, each sufficient on its own to invalidate the
result:

1. **The `du` detector was never validated.** The original fail-first only asserted
   `du_bytes > 0` *before* the rule was applied — true by construction, since nothing had run
   yet. It never demonstrated the probe could register a *drop*. By this harness's own
   governing rule ("a fail-first that comes back clean means the detector is broken and every
   downstream result from it is void, not 'probably fine'" — see `README.md`), that makes the
   original result void.
2. **The 200 test objects deduplicated into a single block.** `lifecycle_check.py` called
   `os.urandom(...)` **once** and PUT that same body 200 times. Garage is content-addressed,
   so 200 MiB of PUTs stored as one ~1 MiB block — visible in the recorded `du` of
   1,048,677 B (1 MiB + 101 B of directory overhead, not the 200 MiB actually PUT). That
   number was itself evidence the probe wasn't measuring what the test assumed.
3. **The wait was structurally too short, and `repair blocks` cannot shorten it.** Garage
   v2.3.0 hardcodes `BLOCK_GC_DELAY = 600s` (`src/block/manager.rs:44`); `block_decref`
   schedules the deleting resync at `now + BLOCK_GC_DELAY + 10s` (`:490`). `garage repair
   blocks` is *exclusively* `put_to_resync(hash, 0)` (`src/block/repair.rs:92-150`), and
   `resync_block` no-ops on a block whose `at_time` hasn't elapsed. Upstream removed
   repair-triggered deletion **deliberately** in PR #135 to fix data-loss issue #39 — so
   `repair blocks` was never going to shorten the wait, no matter how many times it was run.
   The original run waited ~3.5 minutes total against a 610s floor.

**The "`GcTodo: 200` stalled" reading in the original run was also a misdiagnosis.** That
counter is governed by `TABLE_GC_DELAY = 86400s` (`src/table/gc.rs:30`) — a 24-hour *metadata
tombstone* timer touching `metadata_dir` only, not the disk-reclamation path `du` measures. A
constant `GcTodo` on `version`/`block_ref` is actually positive evidence the deletion
propagated correctly through the metadata layer; it says nothing about block-level reclamation
timing one way or the other.

**`block_gc_delay` is not a configuration key**, worth recording explicitly so it isn't
re-investigated as a fix: it does not appear in `src/util/config.rs` or the config docs;
`BLOCK_GC_DELAY` is a compile-time `pub(crate) const` with no env var, admin endpoint, or
`garage worker set` knob. So there is no tuning tradeoff to weigh here — the correct posture is
simply to size for a ~610s reclamation lag. At this estate's measured delete rate (0.191
deletes/s × ~3.9 KB mean object size), that's roughly **450 KB of transient lag** — a
non-issue at this estate's scale.

### Retest, actually run

Two arms on the same image/config, with the control the original run lacked
(`h4-lifecycle-expiration/h4b_retest.py`, driven by `h4b_run.sh`):

| arm | after PUT | at original stop point (~3.5 min) | final |
| --- | --- | --- | --- |
| A: plain `DeleteObject` (control) | 52,430,714 B | 52,430,714 B | **64 B @ +632.4s** |
| B: `Expiration` lifecycle rule (treatment) | 52,430,714 B | 52,430,714 B → NOT-RECLAIMED | **64 B @ +602.3s** |

`SUMMARY verdict=RECLAIMED control_arm=RECLAIMED treatment_arm=RECLAIMED
original_window_verdict=NOT-RECLAIMED`. Arm B reproduces the original run's exact result at
the original run's exact stopping point (`NOT-RECLAIMED`), then goes on to reclaim at 602.3s —
matching the ~610s prediction from the source analysis above almost exactly. The lifecycle
worker's execution was confirmed directly in container logs (`Lifecycle: expiring 1 object in
bucket 43a53bff71055904` × 200; `lifecycle-last-completed` updated to the retest's own run
date), and `expirationDate` was set to yesterday exactly as the original brief specified.

### The gap that survives the correction

**This retest, like the original, used 1 MiB objects — it says nothing about the 95.4% of
this estate's objects that are under 1 KB and stored inline, below Garage's inline threshold.**
See "Known blind spots" above and `h4-lifecycle-expiration/h4c_inline.sh` for that separate,
genuinely open question: `du` is structurally blind to that majority regardless of whether
block-level GC (what this section tests) works correctly.

**Verdict: VOID (original) → REFUTED ON RETEST, for the block-storage path only.** Plain
`Expiration` on a non-versioned bucket does reclaim space, once the fail-first and dedup
defects in the original test are fixed and the wait respects Garage's real GC delay. This does
**not** extend to the inline/sub-3KB object path, which remains untested.

---

## H5 — Longhorn backup restore round-trip

**Verdict: SKIPPED.** `sandbox-talos`'s node image lacks the `siderolabs/iscsi-tools` Talos
system extension Longhorn's engine requires (`longhorn-manager` crash-loops:
`nsenter: failed to execute iscsiadm: No such file or directory`, confirmed directly on the
node). Fixing it requires `talosctl upgrade` + a full node reboot — and the node was found to
be shared with other active tenants (a live chainsaw test run, plus `litellm-audit` and
`mise-poc` workloads) not mentioned in the original environment description. Rebooting a
shared single-node cluster unilaterally to unblock one test was judged not acceptable; per
this project's own rule ("mark SKIPPED with the reason; do not quietly substitute a weaker
test"), that's what happened here. Real work was still completed and left in
`h5-longhorn-restore/`: Garage deployed and bootstrap-tested (found and fixed two real
idempotency bugs along the way), the exact-region-match behavior confirmed with real traffic
(`AuthorizationHeaderMalformed` on mismatch, with a caveat that `GetBucketLocation` itself is
exempt and that botocore's automatic retry can mask a rejected region if not checked for
specifically), and the byte-diff checker fail-first-proven independent of Longhorn (flipped a
byte, checker correctly reported MISMATCH). The backup/restore round trip itself was not
executed. All resources created on the shared sandbox were cleaned up afterward.

---

## H6 — Terraform 1.6.6 S3 backend against Garage

**Full pre-registered flow completed, no shortcuts.** `init`+`apply` against a local backend
(baseline, 3 dummy resources, `plan` confirms 0 diff) → `terraform init -migrate-state
-force-copy` against the Garage S3 backend (`force_path_style`, all `skip_*` flags, throwaway
workspace, dummy resources only, no real state touched) → `plan` against the migrated state.

| Step | Result |
| --- | --- |
| Baseline plan (local backend) | exit 0 — no changes |
| `init -migrate-state -force-copy` (Garage backend) | exit 0 — succeeded |
| Plan after migration (Garage backend) | exit 0 — no changes, matches baseline |

**Verdict: PASS.** Two real snags hit and fixed along the way, both harness bugs rather than
Garage defects: `-input=false` combined with piping `"yes"` to stdin does not work for the
state-migration confirmation prompt (Terraform refuses to prompt at all with input disabled)
— fixed with `-force-copy`, which auto-confirms non-interactively. And this backend version
warns `force_path_style` is deprecated in favor of `use_path_style` — kept as the brief names
it explicitly (still functions, just emits a warning) rather than silently swapped.

---

## What contradicted this project's design assumptions (the most valuable output of this run)

1. **The brief's own H2 fail-first mechanic doesn't reliably work as literally specified.**
   Tail-only 4KiB corruption of `data.mdb` missed LMDB's meta pages on a small/near-empty
   database 11 times out of 12. Not a Garage property — a test-design gap that would have
   invalidated every downstream H2 result if the fail-first discipline hadn't caught it
   before any real iteration ran.
2. **H4's "restart the container" lifecycle-worker trigger doesn't work on a second same-day
   restart** — caught because the harness's own before/after snapshots came back completely
   unchanged, which shouldn't happen for a working trigger. The actual fix (clear
   `lifecycle_worker_state`) is a third, previously-undocumented-in-the-brief method, faster
   than either of the brief's two suggested options.
3. **This Docker VM is not reboot-safe** — cloud-init's `runcmd` bind-mounts are first-boot
   only, so every hard reset in H2 broke Docker and required a specific, order-sensitive
   manual recovery (documented in `h2-durability/post_hardreset_recover.sh`'s header) to avoid
   silently corrupting the result set with fresh-empty-cluster false CLEAN readings. This is
   an environment finding independent of Garage, worth fixing upstream regardless of this
   project's outcome.
4. **H4's own fail-first didn't validate what it needed to, and the "incumbent bug reproduced"
   finding it produced was void, not negative.** The fail-first only proved `du_bytes > 0`
   before the rule ran — true by construction — never that the probe could register a *drop*;
   and a single random body reused across all 200 PUTs meant the "underlying blocks" being
   measured were one deduplicated block, not 200 objects' worth. Once both defects were fixed
   and the wait respected Garage's real ~610s block-GC delay, reclamation worked. This is now
   the clearest instance in this whole harness of the standing rule it's built around (see
   `README.md`): a fail-first that cannot fail makes everything downstream void, not negative.
5. **The Barman trailing-slash finding was reversed on correction, not confirmed** (H3): the
   original probe paired single-slash writes with a double-slash list — a mismatch for which
   HTTP-200-empty is correct S3 behavior, not a defect. On the pairing that actually matches
   barman-cloud's real doubled-write-then-list behavior, Garage handles it correctly
   end-to-end and MinIO is the backend that rejects the write outright.
