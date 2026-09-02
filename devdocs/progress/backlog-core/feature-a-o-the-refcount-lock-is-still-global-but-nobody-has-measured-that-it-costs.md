---
track: A
prio: 25
type: feature
status: backlog
created: 2026-09-02
found-by: frankA
owner: ""
summary: "The managed-refcount critical sections still take the ONE global heap lock — 10 emitter sites (EmitManagedLocalCleanupForTarget 5, EmitDynArrayRetain/ReleaseForSym/ReleaseForNode 3, symtab.inc 2) plus EmitAnsiStringRuntime's 7 mixed ones — so threaded code that retains and releases managed values serialises on the allocator's lock even though it never allocates. This is step 1 of the old feature-threadsafe-heap-optimize plan, which that ticket went AROUND rather than through: the owner's per-thread magazine (250fdc6bd) bypassed the pure alloc/free sites and flattened the scaling curve without touching these. PROMISE IS UNMEASURED and that is why the prio is low: the only benchmark we have (bench/threadsafe_heap_scaling.pas) is alloc-heavy and the magazine already flattened it, so NOTHING here is a demonstrated cost — it is an instruction census, which the O-lane rule says is not a promise. The first job is the benchmark, not the fix. The shape of the fix is known and is a DELETION: give the refcount role atomic primitives and remove it from the lock, rather than adding a lock order."
---

# The refcount lock is still global, but nobody has measured that it costs

- **Type:** feature (optimization) — Track A, tag **O**
- **Split from** [[feature-threadsafe-heap-optimize]] when that resolved
  2026-09-02, because the magazine met its acceptance without doing this.

## The observation

One lock does two jobs. Census of `EmitAcquireHeapLock` CALL sites (grep lines
minus the five that are comments and the declarations — the raw grep says 32 and
the answer is 25):

| enclosing routine | sites | role |
| --- | --- | --- |
| `IREmitNode` | 9 | pure alloc/free — the magazine's fast path already skips two of these, lock is the fallback |
| `EmitAnsiStringRuntime` | 7 | mixed alloc + refcount |
| `EmitManagedLocalCleanupForTarget` | 5 | refcount release, walked over a field list |
| `EmitDynArrayRetain` / `ReleaseForSym` / `ReleaseForNode` | 3 | refcount |
| `EmitAnsiStrFromLiteral` | 1 | alloc |
| `symtab.inc` (`EmitManagedLocalCleanup`, `EmitProcEpilog`) | 2 | refcount release at scope exit |

A thread that only retains and releases — passing managed strings around,
leaving scopes — takes the allocator's lock without ever allocating.

## What is NOT claimed

**No workload has been shown to be slower because of this.** The count above is
an instruction census and the O-lane rule is explicit that opportunity inferred
from a census is not a promise. `bench/threadsafe_heap_scaling.pas` cannot
answer it: it is alloc/free-heavy by construction, which is what made it the
right instrument for the magazine and makes it the wrong one here.

## So the first job is the benchmark

A scaling benchmark whose inner loop **retains and releases managed values
without allocating** — passing an `AnsiString` by value across threads,
entering and leaving scopes holding managed locals, dyn-array element writes —
holding total work constant and splitting it across threads, so a flat line is
perfect scaling and a rise is the lock, the same framing that made the
allocator result legible.

**If that curve is flat, this ticket is `rejected/`, not `low-prio/`** — a
serialisation nobody can measure is not a defect, and parking it at a low number
keeps it in the ranker forever at zero value.

## If the curve does rise, the fix is known and it is a deletion

Worked out in `feature-threadsafe-heap-optimize`'s 2026-08-31 design pass and
still valid: **give the refcount role atomic primitives and delete it from the
lock**, rather than defining a lock order. Removes a mechanism instead of adding
one.

Two caveats that survive from that pass:

- The bare refcount bumps that do NOT free already use `lock dec` and skip the
  lock, so the distinction is one the codegen draws — just not where the old
  ticket assumed. The sites that must stay atomic-and-compound are
  "decrement, and if that reached zero, free" and the record-scope-exit walk.
- `PXXDynArrayRetainImmediate` walks nested elements, so "atomic increments"
  needs the per-arch primitives on all four targets that accept `--threadsafe`.

**The old two-lock obstacle is gone and does not need re-deriving:** it was about
`EmitDynArrayUnique` / `PXXDynArrayUnique`, which had zero call sites since
dynamic arrays were settled as reference types and were deleted 2026-09-02.

## Also worth knowing before starting

`ir_codegen386.inc`'s `EmitAcquireHeapLock386` is an **empty procedure** — i386
takes the lock INSIDE `PXXAlloc` under `PXX_TS_SOFTLOCK`, the opposite placement
from x86-64. Two mechanisms for one concept, which
`normalise-dont-special-case.md` calls a smell and which it is; any change here
has to land in both shapes or the smell gets worse.
