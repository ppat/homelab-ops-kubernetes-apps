# Garage falsification harness

This harness tries to break the (already-approved) decision to replace MinIO with Garage
(`dxflrs/garage:v2.3.0`) for the `storage-core` module's object storage component, before
that decision is committed to. It is not a demo of Garage working — it is six tests whose
job is to produce a **no**, run against the real measured production baseline:

- 13.58 GB live across **3,439,460 objects**, 95.4% under 1 KB, mean 3.9 KB
- ~2.17 ops/sec total, **LIST is 86%** of it (`listobjectsv2` 1.858/s, `deleteobject` 0.191/s,
  `putobject` 0.073/s, `getobject` 0.043/s)
- MinIO's measured cost: 52–59m CPU, ~12,344 MiB RSS, and **~44 GB on disk against 13.58 GB
  live (3.2× amplification)** — versioning is on, only plain `Expiration` rules exist, so
  deletes leave delete markers and noncurrent versions are never reclaimed

## The standing rule this harness is built around

**A test that passes before the thing under test is applied proves nothing.** Every check
here has a fail-first run: a state deliberately constructed so the detector MUST report a
failure, run and observed to actually report it, before any real result from that detector is
trusted. A fail-first run that comes back clean means the detector is broken and every
downstream result from it is **void**, not "probably fine" — this happened twice during
development of this harness (see "What broke and what it means" below) and both times
changed the test before any real result was trusted.

Pattern followed throughout (same idiom as
`homelab-ops-kubernetes-clusters/clusters/homelab/services/sandbox-*/scripts/falsifiability-check.sh`):
a warm-up/fail-first gate that proves the detector works, positive and negative controls
alongside the real check, explicit `SKIP` kept distinct from "checked, no violation found",
and a single greppable `SUMMARY ... verdict=` line per test.

## Where results live

- `results/` — raw output (JSONL per-iteration records, JSON summaries) from every test run,
  including fail-first runs.
- `RESULTS.md` — the verdict per test against the pre-registered kill criteria below, with
  fail-first and real results reported side by side, and the two design-assumption-overturning
  findings this run surfaced.

## Environment this ran on (read before comparing numbers to anything else)

- **Docker VM** (`docker-vm.sandbox-docker.svc.cluster.local`, H1/H2/H3/H4/H6): 4 vCPU, 15 GiB
  RAM, root disk (`/dev/vda`, ext4) only ~19 GiB — too small for this harness's data — but
  `/var/lib/docker` and all container data volumes live on a separate 200 GiB volume
  (`/dev/vdb`, mounted at `/opt/build-scratch`), which is what actually made the H1/H2 data
  volumes fit. Rebuilt weekly; disposable by design.
- **sandbox-talos** (H5): single-node Talos v1.13.8 Kubernetes cluster, ~8 GiB memory / ~40
  GiB ephemeral storage allocatable. Also rebuilt weekly.
- The 12,344 MiB MinIO RSS baseline figure came from **different hardware** (the real
  production cluster) **under different page-cache pressure**, so it is not a valid absolute
  comparator against numbers measured here — H1 runs MinIO and Garage side by side on the
  *same* host specifically so the Garage-vs-MinIO comparison is apples-to-apples even though
  neither number is directly comparable to the 12,344 MiB figure in isolation.

## Environment constraints and honest deviations (read before trusting any result)

- **No read-only credentials to the live production bucket.** The `homelab`/`nas` kubectl
  contexts require interactive OIDC login, unavailable in this non-interactive session. H1's
  keyspace is therefore **synthetic**, not sampled from live data — see
  `h1-rss-list/../lib/keygen.py`'s module docstring for the exact scheme used to reproduce
  the documented Loki prefix-clustering shape (two key families: `fake/<fp>/...` chunk keys,
  95.4% of objects, small; `index_<period>/...` index keys, 4.6%, large) and the size
  distribution (blended mean ≈ 3.9 KB, matching the baseline).
- **No second physical host for iSCSI/NFS.** H2's `ext4-iscsi` and `nfsv4.1` substrates are
  real protocol stacks (LIO/`targetcli` kernel target + `iscsiadm` initiator; real
  `nfs-kernel-server` + NFSv4.1 client) but loopback on the same VM, per the brief's own
  fallback ("if you cannot stand up a real iSCSI target, use a locally-hosted one such as
  tgt/LIO on the VM and say so"). This still exercises the real SCSI/NFS command path
  (`SYNCHRONIZE_CACHE`/FUA on `fsync`, real `COMMIT` semantics on NFS) — what it does NOT
  exercise is network-partition/latency behavior a second host would add.
- **H2 iteration count**: pre-registered at 25 per cell per mechanic. See `RESULTS.md` for
  what was actually completed in the time available — recorded exactly, not rounded up.
- **H1 checkpoint reach**: see `RESULTS.md` for exactly which of 100k/500k/1M/2M/3.44M were
  reached with real measurements vs extrapolated.

## What broke and what it means (the most valuable part of this exercise)

Two things overturned an assumption made in this harness's own design, both caught by the
fail-first-first discipline rather than by a real iteration silently producing a wrong
number. Full detail in `RESULTS.md`; summary:

1. **The brief's exact H2 fail-first mechanic ("dd the last 4KiB off data.mdb") does not
   reliably corrupt LMDB on a small/near-empty database.** LMDB's meta pages live at the
   START of the file; on a freshly-bootstrapped test cell the tail is unused/free space.
   11 of 12 cells' fail-first runs came back CLEAN with the brief's literal instruction — not
   because Garage is more durable than expected, but because the corruption never touched
   anything LMDB reads. Fixed by corrupting both head and tail; re-verified all 12 cells then
   correctly report CORRUPT. See `h2-durability/corrupt_cell.sh`'s header comment.
2. **"Restart the container to trigger Garage's lifecycle worker" (an alternative to the
   brief's two suggested options for H4's 26h wait) does not work on a second restart the
   same day.** Garage persists a `last_completed: <date>` marker in
   `<meta>/lifecycle_worker_state` and skips re-running once it's already run today. First
   assumption ("every restart re-triggers it," from watching one cold start) was wrong;
   caught because the harness's own `du`/list/count snapshots came back completely unchanged
   after the "trigger," which shouldn't happen for a working trigger. Fixed by clearing that
   state file before restart. See `h4-lifecycle-expiration/lifecycle_check.py`'s comment.

Also caught and fixed pre-real-run: the (b) "repair reports no errors" check originally did
a substring search for the word "error" across raw container logs, which false-matched
Garage's own benign shutdown message "S3 API server exited **without error**." Fixed to match
the tracing level field specifically (`ERROR`/`PANIC`) after stripping ANSI color codes. This
was caught because fixing an unrelated bug caused 11/12 fail-first cells to flip from CORRUPT
to CLEAN — which is what surfaced finding #1 above.

## Re-running this harness

Each `hN-*/` directory is self-contained with its own `run.sh` (or documented multi-step
runbook for H2's hard-reset mechanic, which cannot be one unattended script because the host
being rebooted cannot supervise its own reboot). See each directory's own script comments —
they carry the "why", not just the "what". `lib/keygen.py` is shared between H1 and any test
that needs the same synthetic Loki-shaped keyspace.

Everything here targets the Docker VM (`docker-vm.sandbox-docker.svc.cluster.local`, SSH key
`~/.ssh/sandbox_docker_vm`) or `sandbox-talos` (`kubectl --context sandbox-talos`), both
described above. Nothing here writes to `homelab`/`nas`.

## The six tests and their pre-registered kill criteria

### H1 — RSS and LIST latency at 3.44M sub-1KB objects

**Claim**: Garage holds this object count under LIST-dominated access at materially lower RSS
than MinIO. **Kill if any one holds**: RSS > 6 GiB at 3.44M objects; p99 `ListObjectsV2` > 1s
at 1.86 LIST/s; RSS growth 1M→3.44M is superlinear in object count.
**Fail-first**: loader against a 512 MiB tmpfs `metadata_dir` must ENOSPC/OOM.

### H2 — unclean-shutdown metadata durability (the most important test here)

**Claim under test (corrected during design)**: LMDB corruption after unclean shutdown is a
property of the *engine and its defaults* (`metadata_fsync` defaults to `false`), not of the
filesystem underneath — so swapping NFS for iSCSI does not help unless the engine actually
calls `fsync`. Matrix: 4 substrates (ext4-local, ext4-iscsi, nfsv4.1, tmpfs-loop) × 3 engine
configs (`lmdb`+`fsync=false`, `lmdb`+`fsync=true`, `sqlite`+`fsync=true`), pre-registered 25
iterations/cell, two kill mechanics (`kill -9` mid-PUT-stream — does not lose page cache; a
real hard reset via `echo b > /proc/sysrq-trigger` — does).
**Per-iteration verdict**: (a) process starts, (b) `garage repair --yes tables` reports no
errors, (c) every acknowledged PUT is readable, (d) no object returns wrong bytes. **CORRUPT**
= (a) or (b) or (d) fails. **DATA-LOSS** (distinct from CORRUPT) = only (c) fails — the engine
is healthy but silently dropped acknowledged writes, exactly what `fsync=false` predicts.
Loss of *unacknowledged* writes is expected and not counted against either.
**Fail-first**: every cell's iteration 0 runs against a deliberately damaged metadata store
(see "What broke" above for why this needed head+tail corruption, not tail-only).

### H3 — `ListObjectsV2` and the Barman trailing-slash prefix

Reproduce `ListObjectsV2(Prefix="db//")` failing against MinIO first (proves the detector can
catch the bug at all), then the same call against Garage. Three possible outcomes, all
informative: same error (parity), correct listing (better), or **HTTP 200 + empty list**
(worse — silent no-op, no error to catch). Then assert the *outcome* (objects actually
deleted under a retention policy), not just the API call.

### H4 — plain `Expiration` on a non-versioned bucket actually reclaims space

Three assertions in ascending strength: (1) LIST no longer returns the objects, (2) Garage's
own object-count metric drops, (3) **`du` on `data_dir` drops**. (1)+(2) without (3) is
precisely the MinIO delete-marker bug wearing different clothes.
**Fail-first**: all three must report NOT-RECLAIMED before the rule is applied.
**Falsifier**: `du` doesn't drop within one worker cycle + one `garage repair blocks` pass.

### H5 — Longhorn backup restore round-trip

979 `Backup` CRs in production; this is the DR path for every PVC. Garage enforces exact
`s3_region` match (unlike MinIO's leniency). **The assertion is the restore, not the
backup.** **Falsifier**: any restore mismatch, or any restore requiring a manual step.

### H6 — Terraform 1.6.6 S3 backend against Garage

Four workspaces' state must move before MinIO can be decommissioned. `terraform init
-migrate-state` against a Garage bucket with `force_path_style` + the usual `skip_*` flags,
then `plan` must show no diff. Throwaway workspace, dummy resources only.
**Falsifier**: any state operation failing, or a plan differing from the baseline.
