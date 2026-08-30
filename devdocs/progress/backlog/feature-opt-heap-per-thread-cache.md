---
prio: 48
track: A
---

# Heap allocator serializes under threads — parallel alloc is 3x SLOWER than serial

- **Type:** feature/perf — **Track O** (optimization; file-ownership + gate
  **Track A** — `compiler/builtin/builtinheap.pas`, `ir_codegen.inc`).
- **Status:** backlog — filed 2026-07-20.
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
