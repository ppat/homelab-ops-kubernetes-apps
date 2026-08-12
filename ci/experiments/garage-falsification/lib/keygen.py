#!/usr/bin/env python3
"""Deterministic Loki-shaped keyspace + object-size generator, shared by H1 (and any other
test that needs a realistic corpus) so MinIO and Garage are loaded with byte-identical
keys/sizes for a fair comparison.

WHY THIS EXISTS (read this before trusting H1's numbers): the brief for H1 explicitly warns
that a uniform-random keyspace is a materially *easier* LIST workload than Loki's real one,
which is prefix-clustered (`index_<period>/...` and `fake/<fp>/<from>:<through>:<checksum>`
chunk keys). We attempted to seed this from a real `ListObjectsV2` dump of the production
bucket (kubectl context `homelab`) and could not obtain read-only credentials cleanly: that
context requires interactive OIDC login, which is not available in this non-interactive
session. So this is a SYNTHETIC generator that reproduces the documented shape (two key
families, prefix-clustered by fingerprint/period, size distribution skewed the same way) --
it is NOT sampled from live data. Treat H1's absolute numbers as indicative, not exact; the
shape (sub-linear vs super-linear growth) is the load-bearing observation, and that is a
property of the clustering pattern, which this does reproduce.

Key families (matches the measured baseline: 95.4% of objects < 1KB, mean 3.9KB overall):
  - "chunk" keys (95.4% of objects, small): fake/<fp:016x>/<from>:<through>:<checksum:08x>
    <fp> is drawn from a fixed-size pool (NUM_FINGERPRINTS) so many chunks share a directory
    prefix, the way many chunks of one Loki stream share a fingerprint -- this is what makes
    LIST-by-prefix (retention/compaction) expensive to get right.
  - "index" keys (4.6% of objects, large): index_<period>/<tenant>_<uploader:04x>-<seq>.tsdb
    <period> drawn from a fixed pool (NUM_INDEX_PERIODS), clustering many files per period
    the way Loki's index buckets by day.

Both families are used by every checkpoint size (100k/500k/1M/2M/3.44M): the loader just
grows `count`, and this generator is a pure function of the absolute index `i`, so re-running
the loader up to a bigger `count` reproduces the exact same keys/sizes for the objects already
written -- checkpoints are cumulative, not independent samples.
"""
import hashlib
import random
import struct
import sys

CHUNK_FRACTION = 0.954
NUM_FINGERPRINTS = 40_000   # fixed pool -> ~82 chunks/fingerprint at the full 3.44M scale
NUM_INDEX_PERIODS = 400     # fixed pool -> ~396 index files/period at the full 3.44M scale
BASE_TS_NS = 1_700_000_000_000_000_000
CHUNK_SPAN_NS = 90_000_000_000  # ~90s chunks, typical Loki chunk target span

# Size distribution: chosen so the blended mean lands at ~3.9KB overall, matching the
# measured baseline. 0.954 * 500 + 0.046 * 74_500 ~= 3908.
CHUNK_SIZE_MEAN = 500
CHUNK_SIZE_MIN = 64
CHUNK_SIZE_MAX = 1000
INDEX_SIZE_MIN = 1024
INDEX_SIZE_MAX = 148_000


def _h64(*parts: object) -> int:
    """Stable 64-bit hash, independent of PYTHONHASHSEED (unlike builtin hash())."""
    b = "|".join(str(p) for p in parts).encode()
    digest = hashlib.sha256(b).digest()[:8]
    return struct.unpack(">Q", digest)[0]


def key_and_size(i: int) -> tuple[str, int]:
    """Return (object_key, object_size_bytes) for absolute object index i (0-based),
    deterministic in i alone so it's reproducible across independent loader runs/targets.
    """
    r = random.Random(_h64("key", i))
    is_chunk = r.random() < CHUNK_FRACTION
    if is_chunk:
        fp = _h64("fp", i % NUM_FINGERPRINTS) & 0xFFFF_FFFF_FFFF_FFFF
        bucket = i // NUM_FINGERPRINTS
        frm = BASE_TS_NS + bucket * CHUNK_SPAN_NS
        through = frm + CHUNK_SPAN_NS
        checksum = _h64("chk", i) & 0xFFFF_FFFF
        key = f"fake/{fp:016x}/{frm}:{through}:{checksum:08x}"
        size = max(CHUNK_SIZE_MIN, min(CHUNK_SIZE_MAX, int(r.gauss(CHUNK_SIZE_MEAN, 250))))
    else:
        period = 19700 + (i % NUM_INDEX_PERIODS)
        uploader = _h64("up", i) & 0xFFFF
        key = f"index_{period}/fake_{uploader:04x}-{i}.tsdb"
        size = r.randint(INDEX_SIZE_MIN, INDEX_SIZE_MAX)
    return key, size


def content_for(i: int, size: int) -> bytes:
    """Deterministic pseudo-random content, cheap to regenerate (no need to store the
    corpus) and cheap to verify later (same seed -> same bytes).
    """
    r = random.Random(_h64("content", i))
    return bytes(r.getrandbits(8) for _ in range(0))[:0] + r.randbytes(size)


if __name__ == "__main__":
    # Quick self-check / sample dump: `python3 keygen.py 20`
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    total_size = 0
    chunk_n = 0
    for i in range(n):
        k, s = key_and_size(i)
        total_size += s
        if k.startswith("fake/"):
            chunk_n += 1
        if i < 20:
            print(f"{i:>8}  {s:>7}B  {k}")
    print(f"--- n={n} mean_size={total_size / n:.1f}B chunk_fraction={chunk_n / n:.3f}", file=sys.stderr)
