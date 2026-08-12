# Results

Verdicts against the pre-registered kill criteria in `README.md`. Fail-first result reported
alongside the real result for every test that has one. Raw data in `results/`.

## Verdict summary

| Test | Verdict | Confidence |
| ------ | --------- | ------------ |
| H1 — RSS/LIST at scale | **NOT KILLED (partial)** | Real data to 500k only; 1M+ not reached, see below |
| H2 — unclean-shutdown durability | **NOT KILLED (pilot scale)** | 5/25 hard-reset iterations, 8/25 kill-9 iterations |
| H3 — ListObjectsV2 `db//` | **KILLED-ISH — Garage is worse than MinIO here** | Raw API confirmed; CNPG e2e not reached |
| H4 — Expiration reclaims space | **KILLED** | `du` never dropped — same bug as the MinIO incumbent |
| H5 — Longhorn restore | **SKIPPED** | Real infra blocker, documented, not worked around |
| H6 — Terraform 1.6.6 backend | **PASSED** | Full pre-registered flow, clean |

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
947.1 MiB) between the two lowest checkpoints while the object count only grew 5×, i.e. its
early growth is *roughly linear, trending slightly superlinear* on this small a sample —
consistent with, but nowhere near confirming, the brief's concern about an unsharded index
that "collapses around 10M" (issue #1222). Two points is not enough to call superlinearity
with confidence; that call needs the 1M/2M/3.44M points this run did not reach in time.
MinIO's RSS was flat (~523 MiB) across both checkpoints — for MinIO, 500k objects clearly
isn't yet enough to see its curve either.

**Verdict**: **NOT KILLED, but NOT CLEARED either** — the pre-registered kill criteria (RSS
> 6 GiB at 3.44M; p99 LIST > 1s at 1.86/s; superlinear 1M→3.44M growth) were not reachable in
the time available. Garage's RSS growth 100k→500k is a real yellow flag worth extending this
run to confirm or refute — do not read "not killed" here as "cleared."

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

**Reproduced against MinIO first** (required by the brief): `ListObjectsV2(Prefix="db//")`
raises `ClientError: XMinioInvalidObjectName ... Object name contains unsupported characters`
(HTTP 400) — confirms the documented bug and confirms this test's detector can catch it.

**Against Garage v2.3.0**: `ListObjectsV2(Prefix="db//")` returns **HTTP 200, `KeyCount=0`,
empty `Contents`** — even though `ListObjectsV2(Prefix="db/")` on the identical bucket
returns the 3 seeded objects. This is the third, explicitly-flagged-as-worst outcome in the
brief: **not** parity, **not** a fix — a silent no-op that a retention/pruning job would read
as "nothing here to delete" with no error anywhere to catch. Draft upstream issue at
`h3-listobjectsv2-barman/UPSTREAM_ISSUE_DRAFT.md`, not yet filed.

**CNPG + barman-cloud-plugin end-to-end assertion (real deletions under a retention policy)
was NOT attempted** — descoped for time, per the brief's own Pareto guidance (H1/H2 first).
The raw-API-level result above is the load-bearing finding (it's what would actually break a
retention job); the CNPG layer would confirm the same thing end-to-end but is secondary
confirmation, not a different question. **Marked not-reached, not silently downgraded.**

**Verdict**: Garage is measurably *worse* than MinIO on this specific, real operational
pattern. Not immediately disqualifying (barman-cloud can likely be configured to avoid ever
constructing a `//`-containing prefix), but it is a concrete defect that should be filed
upstream and tracked before this reaches production, and it means any retention/pruning
automation must be positively verified against Garage, not assumed to behave like MinIO.

---

## H4 — plain `Expiration` on a non-versioned bucket actually reclaims space

**Fail-first**: PUT 200×1MiB objects, snapshot all 3 assertions before applying any rule.
`list=200 bucket_objects=200 du_bytes=1048677` — correctly NOT-RECLAIMED (nothing has run
yet). `failfirst_ok: true`.

**Real run**: applied `Expiration.Date=<yesterday>`, triggered Garage's lifecycle worker (see
below for how), waited, then ran `garage repair --yes blocks` and waited again (60s
automated, up to 2.5+ minutes during manual investigation).

| Snapshot | list KeyCount | bucket object count | `du` on data_dir |
| --- | --- | --- | --- |
| before rule | 200 | 200 | 1,048,677 B |
| after worker run | **0** | **0** | **1,048,677 B (unchanged)** |
| after `repair --yes blocks` | 0 | 0 | **1,048,677 B (unchanged)** |

**Verdict: NOT-RECLAIMED.** Assertions (1) and (2) — the same two the incumbent MinIO bug
already satisfies while still leaking 44GB — both flip to "reclaimed" immediately. Assertion
(3), the one the brief specifically says would have caught the incumbent bug, **never
changes**. `garage stats` after the worker run showed `object`/`version`/`block_ref` tables
all stuck at `GcTodo: 200` with zero progress after 2.5+ minutes of manual observation past
the automated 60s wait — this is not "just needs a bit longer," it looks stalled. **This is
the same failure class as the MinIO bug this whole project exists to fix, reproduced on
Garage.** This is a hard, direct, disqualifying-unless-explained finding for the "plain
Expiration reclaims space" claim as tested.

**Timing method, a real deviation from both of the brief's suggested options**: neither
"offset the container clock" nor "accept a 26h wait" was used. Garage's lifecycle worker runs
once per calendar day and persists a `last_completed: <date>` marker in
`<meta>/lifecycle_worker_state`; a plain `docker restart` on the same day does **not**
re-trigger it (first assumption, wrong — see README). Deleting that state file before restart
does force a fresh run in seconds. Documented in `h4-lifecycle-expiration/lifecycle_check.py`.

**Caveat**: this result should be reproduced with a longer wait (tens of minutes, not just
2.5) before treating it as fully dispositive — but a stalled `GcTodo` queue with zero movement
over 2.5 minutes is already well past "needs a moment," and it is exactly the assertion the
brief pre-registered as the falsifier.

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
4. **H4 reproduces the exact incumbent MinIO bug this whole migration exists to fix** — plain
   `Expiration` metadata-deletes cleanly (list/count both drop to zero) but never reclaims the
   underlying blocks even after a `repair --yes blocks` pass and multiple minutes of
   observation. If this holds up under a longer wait, it is a serious, direct hit against one
   of the stated reasons for migrating away from MinIO in the first place.
5. **Garage is measurably worse than MinIO, not just different, on the Barman trailing-slash
   case** (H3): a silent HTTP-200-empty instead of an error is the worst of the three possible
   outcomes the brief called out in advance, and it was the one that happened.
