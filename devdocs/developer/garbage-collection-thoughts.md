# Garbage Collection — Thoughts And Decision

**Filed:** 2026-06-02 21:20 (+0200)
**Status:** decision recorded — GC is **not** the default; memory management
becomes a per-target / per-frontend **profile**. All advice below accepted.

## The question

Replace deterministic managed-value cleanup (ARC: release managed strings/
records on every function exit, exception unwind, etc. — complicated codegen)
with a garbage collector that runs "every so often, once idle".

## What is actually being traded

Deterministic **ARC** → tracing **GC**. The per-exit cleanup pain is real, but
GC's hidden requirement is larger than what it removes.

### The hidden cost is root-finding

A collector must, at collection time, find every live heap pointer — the roots
(locals/temps/registers in every active frame, plus globals) — then trace the
object graph. Two ways, both with structural cost:

- **Precise GC.** The compiler emits **stack maps**: at every safepoint, which
  stack slots and registers hold pointers. That is *more* pervasive codegen
  than ARC release calls, and it bleeds into the register allocator and every
  call site. Net codegen goes **up**, not down.
- **Conservative GC (Boehm-style).** Scan stack/registers, treat anything
  pointer-shaped as a pointer. No stack maps — genuinely bolt-on, genuinely
  less compiler work. Cost: false retention, cannot move objects, must know the
  heap extents.

### "Run when idle" is the part that bites

"Idle" assumes a clean point, but a heap reference lives in a register
mid-expression. A collector may run only at **safepoints**, or it must scan
registers conservatively. Add threads and it becomes stop-the-world with a scan
of every stack.

### Roadmap tension decides it

The destination is RISC-V **bare metal** (see [`roadmap.md`](roadmap.md)). A
timer-driven tracing collector is a runtime — no scheduler, no "idle",
deterministic latency matters. ARC and arenas are bare-metal-friendly;
timer-GC is hostile. So GC-as-default fights where the project is going.

## The wins that were actually wanted — ranked (none is "GC everywhere")

1. **Arena / region allocation.** Allocate from an arena; drop the *whole
   arena* at a coarse boundary (request, frame, loop iteration). Zero
   per-object cleanup, deterministic, trivial on bare metal. This *is* the
   "call something every so often" idea — but bounded and precise. Best fit for
   the embedded roadmap.
2. **Conservative mark-sweep as an optional *hosted* profile.** Bolt-on, no
   stack maps, removes the per-exit codegen. Ship where there is an OS; never on
   bare metal.
3. **Keep ARC, cut its pain without GC.** Most of the "check strings on every
   exit" cost is implementation, not inherent: move-on-return (already on the
   backlog), one cleanup block per function instead of per-exit, and
   liveness-gated emission so functions with no managed temps emit nothing.
4. **Cycle collection — the one thing ARC genuinely cannot do.** Refcounts leak
   reference cycles. If Nil Python (Python) allows them, the eventual answer is
   a **cycle collector** alongside refcounting — exactly CPython's design
   (refcount + optional cycle GC). That is the legitimate niche, not wholesale
   GC.

## Decision (accepted)

Memory management is a **per-target / per-frontend profile**, sharing the
allocator contract being designed in
[`allocator-platform-design.md`](allocator-platform-design.md). One allocator,
swappable policy:

- **ARC** — default. Precise, bare-metal-safe. Pascal stays ARC/manual.
- **Arena** — embedded / bare-metal profile. Coarse reset, no per-object work.
- **Conservative mark-sweep + cycle collector** — hosted profile. Nil Python
  (Python semantics) gets the collector; Rust stays ownership/no-GC.

GC is therefore an *optional hosted policy*, never forced, never the default,
never on bare metal. Capture this when the allocator profiles are implemented;
do not bolt a timer-driven tracing collector onto the current managed-value
path.

## Related

- [`allocator-platform-design.md`](allocator-platform-design.md) — the
  allocator contract these profiles plug into.
- [`rainy-afternoon.md`](rainy-afternoon.md) — managed-value backlog
  (move-on-return, exception-unwind finalization) that softens ARC without GC.
- [`plan-async-coroutines.md`](plan-async-coroutines.md) — shares the allocator
  groundwork.
