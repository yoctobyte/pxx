---
prio: 48
track: A
owner: frankA
---

# Heap allocator serializes under threads — parallel alloc is 3x SLOWER than serial

- **Type:** feature/perf — **Track O** (optimization; file-ownership + gate
  **Track A** — `compiler/builtin/builtinheap.pas`, `ir_codegen.inc`).
- **Status:** working
- **Found by:** Track E, writing `examples/parallel/pow.pas`
  ([[feature-demo-parallel-hashing-pow]]). T owns the tool, E owns the demo —
  the compiler/runtime gap is filed here, in the owning lane.

## Symptom (measured, x86-64, 8 workers)

`pow.pas` mines nonces with two hashes. Identical loop shape, identical
reductions; the ONLY difference is whether the per-iteration hash allocates.

| hash | per-nonce allocation | serial | pdChunked (8 workers) |
| --- | --- | --- | --- |
| splitmix64 | none (registers only) | 28.2 M hash/s | 97.6 M hash/s — **3.5x faster** |
| sha256 | AnsiString buffers | 63.3 K hash/s | 19.2 K hash/s — **3.3x SLOWER** |

So the allocating workload does not merely fail to scale: adding cores makes it
**~11x worse than it should be** (3.5x expected, 0.30x observed). Results stay
correct — both reductions agree across every distribution — this is purely a
throughput cliff.

## Cause

`compiler/builtin/builtinheap.pas` guards ALL allocator state (FreeList /
HeapPtr / the size bins) with a single global userspace spinlock
(`PXXHeapSpin`, taken via `__pxxatomic_xchg` in both alloc and free; see also
`EmitHeapAllocLocked` / `EmitHeapFreeLocked` in `ir_codegen.inc`). Every worker
allocating in its hot loop contends on that one word, so the threads spend their
time spinning on a cache line that is being written by all the others — strictly
worse than the serial run, which never contends. AnsiString refcount atomics
add a second source of the same cache-line ping-pong.

## Direction (suggested)

1. **Per-thread free-list cache** (the standard fix — tcmalloc/jemalloc shape):
   each thread keeps a small array of size-class bins it can pop/push with NO
   lock; only a refill/flush from the global pool takes the spinlock. The
   existing exact-size bin structure maps onto this directly — the bins become
   per-thread, the mmap bump pool stays global.
2. **Bounded thread cache** so a producer/consumer pattern (alloc on A, free on
   B) still returns memory: cap the per-thread bin depth, flush the overflow to
   the global list in batches.
3. Consider a **backoff/futex** on the global spinlock for the remaining
   contended path, so a waiter stops burning a core.
4. Possibly cheaper first step, worth measuring on its own: **sharded locks**
   (N spinlocks by size class, or by `tid mod N`) — much smaller change,
   probably recovers most of the loss for workloads that allocate uniform sizes.

Needs thread-local storage for (1)/(2); check what the PAL/threading layer
already exposes before adding a TLS mechanism.

## Acceptance

- `examples/parallel/pow.pas --hash sha256` shows a **speedup** (>1x) with 8
  workers instead of the current 0.30x; target the same ballpark as the
  non-allocating path's 3.5x.
- No regression on single-threaded allocation throughput (the `--threadsafe`-off
  and 1-worker paths must not get slower).
- Track A gate: `make test` + self-host byte-identical, plus cross where the
  runtime is touched. New behaviour behind `-O3` first if it is a codegen change;
  an allocator data-structure change is not `-O`-gated but must be measured.

## Links
[[feature-demo-parallel-hashing-pow]] (where it showed up) ·
[[feature-parallel-for-scheduling-policy]] (the loop surface that exposes it) ·
`compiler/builtin/builtinheap.pas` · `ir_codegen.inc` (`EmitHeapAllocLocked`).

## Log
- 2026-07-20 — Filed from Track E while building the PoW demo. Numbers above are
  from that demo on an 8-worker x86-64 host; the demo is kept as the standing
  reproducer (`--hash sha256` vs the default `--hash fast`).

---

## 2026-08-29 — a SECOND, independent claim about this allocator: it is 2-3x slower than FPC's with ONE thread

Banked from [[feature-opt-bulk-copy-is-byte-at-a-time]], where it turned up as
the residue after the copy loops were fixed. **This ticket is written entirely
around threaded scaling; the measurement below has no threads in it at all.**

3,000,000 iterations of `b := nil; SetLength(b, 64)` — allocate 256 bytes, zero
it, free the previous block. No copy, no contention, one thread:

| | time | |
| --- | --- | --- |
| FPC 3.2.2 | 0.28-0.29 s | |
| pxx | 0.70-0.87 s | **2.4x - 3.1x slower** |

Both sides alternated in one window, best of three, twice — **binary
`272e95c5ec9c`** (and `061099b514c0` for the first window). The spread is box
contention, not measurement disagreement; the ratio held across both windows.

### Why it matters here rather than in its own ticket

Two different claims about one component, and this ticket held only one of them:

| | workload | claim |
| --- | --- | --- |
| the original filing | 8 workers, sha256 with AnsiString buffers | **3.3x SLOWER than serial** — lock contention |
| this addition | 1 worker, SetLength churn | **2.4-3.1x slower than FPC** — no lock contention possible |

A per-thread free-list cache (direction 1) addresses the first and does nothing
for the second, because with one thread the global spinlock is uncontended and
`__pxxatomic_xchg` on an uncontended line is cheap. So **the acceptance
criterion "No regression on single-threaded allocation throughput" is treating
the single-threaded path as a constraint when it is also a defect.** Whoever
takes this should decide deliberately whether they are fixing one problem or
two; fixing only the contention leaves a 2-3x sitting under every allocating
program on every target, threaded or not.

### Where it was found, and why the finding is bigger than the number

`Copy(arr)` on a 64-element array is 3.6x slower than FPC's at HEAD. After
removing every byte loop on that path, **77% of the remaining time is this
allocator** — 0.70 s of pxx's 0.91 s is allocate/zero/free churn, and the copy
itself is ~0.21 s against FPC's ~0. The copy was never the main term once the
block primitives landed; it just looked like it because nobody re-measured.

### Every figure above is stamped, deliberately

This ticket already carries the rule and learned it the hard way — the `-O2`
promotion recorded here is worth **1.04x, not the 1.29x** originally quoted,
because the baseline stopped existing. The same thing happened to
`feature-opt-bulk-copy-is-byte-at-a-time`: its **23x became 3.6x** while the
ticket sat in the backlog at prio 65 advertising the old number, and the work
that closed the gap had landed weeks earlier.

**A benchmark number in a ticket is a measurement with an unstated `as-of`, and
the unstated part is what rots.** So: the numbers in this section are as of
binary `272e95c5ec9c` / `061099b514c0`, and the 3.5x / 3.3x figures at the top of
this ticket are **as of 2026-07-20 and unverified since** — rebuild their
baseline before quoting them, including in the acceptance criteria.

---

## 2026-08-31 (frankA) — claim 2's headline is closed: 2.18x -> 1.25x at 256 bytes, and the cause was NOT the lock

Landed `878542b89`, binary `cc9b600f1208`, `gate.sh quick` green.

**Baseline re-measured first, as this ticket instructs.** At compiler
`393ba3c6006a` the 2026-08-29 claim was still live: `b := nil; SetLength(b, 64)`
x 3M ran 0.68 s against FPC 3.2.2's 0.25 s — **2.7x**, inside the recorded
2.4-3.1x. It had not decayed.

**The ticket's own stated cause could not have produced it.** `PXXHeapSpin` is
behind `{$ifdef PXX_TS_SOFTLOCK}` and is absent from a single-threaded build, so
**direction 1 (per-thread free-list cache) addresses claim 1 only** — as the
2026-08-29 section suspected, now confirmed structurally rather than by
inference.

**The real cause, found by scaling the block rather than profiling.** The
pxx/FPC ratio grew with size — 8B 1.22x, 32B 1.48x, 128B 1.71x, 256B 2.18x,
2048B 4.62x — which is a per-BYTE cost. Both of `PXXAlloc`'s reuse paths
hand-rolled a word-at-a-time zero loop, so neither ever reached the `rep stosb`
that `PXXMemZero` (declared in the same unit, 2700 lines below) has always
provided. ~2.1 GB/s against FPC's ~13.7.

**Two thresholds, both swept, because the naive fix regressed.** Calling
`PXXMemZero` unconditionally measured **0.91x at 8 bytes and 0.92x at 32** (old
faster in 9 of 9 interleaved rounds): `rep stosb`'s microcode startup, and
separately a call costing more than the job for one or two words. So
`MEMZERO_REP_MIN` (64) picks loop-vs-`rep` *inside* `PXXMemZero`, benefiting
every caller, and `ALLOC_INLINE_ZERO_MAX` (64) is a call boundary in `PXXAlloc`
— not a rival algorithm.

| bytes | old | new | vs FPC before | after |
| --- | --- | --- | --- | --- |
| 8 | 0.28 | 0.28 | 1.22x | 1.22x |
| 32 | 0.30 | 0.30 | 1.48x | 1.43x |
| 128 | 0.41 | 0.34 | 1.71x | 1.42x |
| 256 | 0.61 | 0.35 | 2.18x | **1.25x** |
| 2048 | 3.14 | 0.66 | 4.62x | **0.97x** |

Interleaved A/B against a clean-tree build, min of 3, box load 5-7. No
regression at any size — the acceptance criterion's second bullet.

### Banked, NOT fixed: the dynamic-array path zeroes every block twice

`SetLength` calls `PXXMemZero(newArrData, newLen * elSize)` on a block `PXXAlloc`
has *already* zeroed. Two full passes over the same bytes on the commonest
allocation shape in the language.

**This is not a guess — it is why my first regression test could not fail.** The
obvious dynamic-array spelling of the zero-on-reuse contract passes with
`PXXAlloc`'s zeroing **deleted entirely**, measured, all three arms removed,
because `SetLength` re-zeroes underneath it. `test/test_heap_zero_on_reuse.pas`
uses class instances for that reason and carries the warning in its header.

Removing the second pass is not a deletion: `SetLength` must still zero the
grown tail on a realloc, and the copy path needs the old span intact. So the
shape is probably "zero only `[copyLen, newLen)`", and it wants its own
measurement — plausibly another ~1.2-1.4x on this same benchmark, since the
remaining 1.25x at 256 bytes is now mostly that second pass.

### What is still open on this ticket

- **Claim 1 (the title) is untouched.** 8-worker sha256 at 0.30x serial. The
  spinlock, `PXX_TS_SOFTLOCK`, per-thread bins — all still to do, and the
  2026-07-20 numbers there remain **unverified since**; rebuild that baseline
  before quoting the 3.5x / 3.3x, including in the acceptance criteria.
- **The double zeroing above.**
- Claim 2's residual: 1.22x at 8 bytes, which is per-call overhead, not per-byte,
  and is a different investigation again.

## 2026-08-31 (frankA) — I was WRONG about the double zeroing: removing it measures 1.00x, at every size

Correcting my own paragraph two sections up, which predicted "plausibly another
~1.2-1.4x". It is not. **Removing the redundant pass entirely changes nothing
measurable**, and the prediction should not have been written as a number.

The redundancy is real: `PXXDynSetLen` calls
`PXXMemZero(newArrData, newLen * elSize)` on a block `PXXAlloc` has already
zeroed on every path (bin reuse, large-list reuse, bump, and the ESP/libc
`calloc` profiles). I deleted the call and measured, interleaved, min of 3,
against a stash-built control — **both binaries' sha256 confirmed different**,
because an A/B where the two arms are secretly one binary is the standing trap
here:

| alloc size | with 2nd pass | without | gain |
| --- | --- | --- | --- |
| 8 B | 0.28 | 0.27 | 1.04x |
| 32 B | 0.30 | 0.31 | 0.97x |
| 128 B | 0.33 | 0.33 | 1.00x |
| 256 B | 0.35 | 0.35 | 1.00x |
| 2048 B | 0.69 | 0.70 | 0.99x |
| 64 KB | 0.11 | 0.11 | 1.00x |
| 1 MB | 1.98 | 1.98 | 1.00x |

The last two rows are the ones that killed the hypothesis. At 1 MB per
allocation the second pass would be 20 GB of extra stores across the run — well
past any cache — and it costs **nothing**. Reading back from the total: 20 GB in
1.98 s is ~10 GB/s, i.e. the cost of exactly ONE pass. So at that size only one
pass is doing real work anyway; the large path bump-allocates fresh mmap pages
the kernel has already zeroed, and the redundant `rep stosb` runs over lines the
fault just brought in.

**Why the earlier 1.71x/4.59x was real and this is not, since the two look like
the same edit.** What that commit removed was a *word loop* at ~2.1 GB/s. What
this removes is a *second `rep stosb`* over bytes the first pass just left in
L1. The redundancy was never the defect — **the slow spelling was**. Deleting
duplicated work and deleting duplicated *mechanism* are different edits, and only
the second one had a number behind it.

**Not landed, deliberately.** No promise, so it does not proceed: it would move
a live correctness guarantee onto a contract established a call away, in
exchange for nothing measured. The knowledge stays here so the next reader does
not re-derive it — and so nobody "optimises" it later on the strength of how
obviously redundant it looks. That obviousness is exactly what I acted on.

`PXXStrSetLen` has the same shape and was not measured; assume the same answer
until someone shows otherwise.
