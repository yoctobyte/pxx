---
track: N
prio: 30
type: feature
blocked-by: []
summary: "TPyList/TPyDict corrupt under concurrent mutation — append is a read-modify-write over a buffer PyListGrow may realloc, so two threads can use-after-free. Free-threaded CPython guarantees this cannot happen; adopt that contract under --threadsafe with one-way biased sharing."
---

# Thread-safe NilPy containers — `TPyList` / `TPyDict`

Filed 2026-08-11 from the Track U session that settled
[[decide-nilpy-parallel-capture-semantics]]. **Independent of that ticket** — not
a blocker for `parallel for`, not blocked by it. A program using plain
`threading` hits this without any parallel-for in sight.

Full context and rationale: `devdocs/dev/threading-model.md`.

## The defect

`--threadsafe` makes the **runtime** safe — allocator spinlock, atomic
refcounts, statement-atomic console I/O. It does nothing for **data
structures**. `TPyList.append_self`, in full:

```pascal
PyListGrow(Self, FLen + 1);                        { may REALLOC FItems }
dst := PPyVarRec(NativeInt(FItems) + FLen * 16);
PyVarSlotSet(dst, src);
FLen := FLen + 1;                                   { read-modify-write }
```

Two threads appending:

- benign — both read `FLen = n`, both write slot `n`, one element lost;
- malignant — `PyListGrow` reallocates under thread B while thread A still holds
  the old `FItems`, and A writes into freed memory. **Use-after-free in the
  container runtime**, which is the worst available blast radius.

## Why it is a defect and not a dialect choice

Free-threaded CPython (PEP 703) **guarantees** container operations cannot
corrupt — per-object locks / critical sections, with lock-free optimistic reads.
You may lose an update; you may not lose the heap. Since free-threading is
officially supported from 3.14, working CPython code that shares a list across
threads is code that must work here. By CLAUDE.md's upward-compatibility rule
that makes this a bug, not a divergence.

The stance it replaces is Pascal's — a shared mutable structure is the
programmer's problem — which NilPy inherited **silently**.

## The contract to adopt (CPython's line, deliberately)

- **Integrity is the runtime's job.** No corruption, no use-after-free, no torn
  structures.
- **Logical atomicity is the user's job.** `d[k] += 1` racing loses updates, in
  Python as here.

Note the limit: this is an *operational guarantee from one implementation*, not
a specification — **there is no Python memory model**. Copy the guarantee; do not
try to derive corner cases from it.

## The surface is TWO classes

`TPyList` **is** list, tuple *and* set (`setupdate`, `setintersect`, `issubset`,
`union`, `symmetric_difference` hang off it). `TPyDict` projects into it
(`itemlist`/`keylist`/`vallist`). That is the whole job.

## Design — one-way biased sharing

Pay only when an object is genuinely shared: owner-thread fast path, lock after a
second thread touches it. This is **biased locking**, and its failure mode is
documented history — HotSpot's was disabled in JDK 15 and removed in 18, and
**the fast path was never the problem; revocation was.** Un-biasing needed global
coordination and cost more than the bias saved. CPython's biased *refcounting*
survives because its transition is cheap and monotone.

So:

> **"Becomes shared" is one-way and purely local.** Flip owner-fast → locked
> once, forever. No revocation, no global coordination, never flip back.

`if FOwnerTid <> CurrentTid then FShared := True` on entry — one predictable
branch, no barrier in the common case. Worst case is a container that stays
locked after sharing stops, which is fine.

**Storage: object fields, not the meta word.** The managed-block meta word's low
32 bits are fully allotted (`BlockKind|Flags|KindData0|KindData1`) and bits 32–63
are reserved for [[feature-a-shrink-managed-header-on-32-bit]]. `TPyList` and
`TPyDict` are Pascal classes — put `FOwnerTid`/`FShared` beside `FLen`. Eight
bytes per container, no header-budget interaction, no collision with
[[feature-nilpy-text-string-kind]].

**Under the EXISTING `--threadsafe` flag. Do not add a second one.** A mode where
the allocator is safe but lists still corrupt reads as a guarantee and is not
one. Monothreaded builds pay nothing — that is the design commitment, not an
unfinished migration.

## Scope

1. `FOwnerTid`/`FShared` on `TPyList` and `TPyDict`, set at construction.
2. Guard every **mutating** method (append/insert/remove/pop/sort/extend/the set
   ops/`__setitem__`/dict insert-and-resize). Reads may stay unguarded in v1 —
   but a read concurrent with a realloc is exactly the use-after-free above, so
   **decide reads explicitly rather than by omission** and write down which way.
3. Compile the guard out entirely when `ThreadSafeMode` is off.

## Gate

`compiler/builtin/**` — so Track A's obligation: `stabilize-fast` + `make pin`,
not the quick loop alone. Plus `make test-nilpy` green and a threaded `.npy`
stress test (N threads appending to one list; the list must survive, the count
may be short).

## Not in scope

- Making `d[k] += 1` atomic. That is the user's, in CPython too.
- ARC contention / false sharing on shared managed values — a *performance*
  question, unmeasured, listed as open in the threading doc.
