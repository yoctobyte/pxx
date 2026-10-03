---
track: A
prio: 35
type: feature
blocked-by: [feature-nilpy-object-reclamation]
status: backlog
---

# NilPy: collect reference cycles (the reserved half of the GC decision)

`devdocs/developer/garbage-collection-thoughts.md` (2026-06-02) rejected tracing
GC as a default and reserved exactly one niche, point 4:

> **Cycle collection — the one thing ARC genuinely cannot do.** Refcounts leak
> reference cycles. If Nil Python allows them, the eventual answer is a cycle
> collector alongside refcounting — exactly CPython's design. That is the
> legitimate niche, not wholesale GC.

This is that ticket. It changes nothing for Pascal, nothing for bare metal:
per that decision memory management is a per-target/per-frontend profile, ARC
stays the default, and a collector is a HOSTED-profile addition for NilPy only.

## Why it does not contradict the "no GC" decision

The doc rejected tracing GC because of ROOT FINDING: locating every live
pointer in stacks and registers needs stack maps, which pushes codegen up
rather than down and is hostile to bare metal.

A cycle collector needs no roots. CPython's trial deletion copies each
refcount, walks the tracked set subtracting INTERNAL references, and whatever
still has count left over is referenced from outside. The stack is never
scanned — an external reference is already visible as leftover refcount. That
single property is what makes one approach unacceptable and the other cheap,
and it is why both answers in that doc are consistent.

## Objects ARE refcounted already — this builds on that, it does not await it

Slices 1-4 of [[feature-nilpy-object-reclamation]] landed 2026-07-22/23:
`PXXObjRetain`/`PXXObjRelease` (`compiler/builtin/builtinheap.pas:1722/1760`)
are real refcounting on the heap-block header word — atomic under
`PXX_TS_SOFTLOCK`, guarded by `PXXObjPlausible`, freeing through `PXXFree` at
zero. Same protocol as AnsiString and dynarray. doloop RSS went 595 -> 369 MB.

So the prerequisite a collector needs — objects that carry a count — is DONE.

## Why the traverse half is nearly free (measured, not assumed)

Two existing walkers already enumerate an object's outgoing managed references:

- `PXXObjRelease` at rc=0 calls `PXXObjFinalizeHook` -> pylib's `PyObjFinalize`
  (`compiler/builtin/pylib.pas:7278`), which recursively releases children.
- `PXXRecordRelease` (`builtinheap.pas:2283`) walks a type's members from a
  descriptor — offset / kind / arrayCount / typeRef each — recursing through
  sub-records and dynarrays, with cases for variant slots (kind 5,
  `PXXVarClear`) and NilPy class-typed fields (kind 6, `PXXObjRelease`).

A traverse is either of those with the LEAF ACTION swapped from "release this
child" to "visit this child". The per-type reference enumeration is existing,
tested machinery — not new codegen, not new RTTI, not a function emitted per
type.

## What it really depends on: a COMPLETE traverse, not a refcount

The blocker edge is real but the reason is not the obvious one. Trial deletion
is conservative in a specific direction:

- **Over-retention (today's leak tail) is SAFE but blunts the collector.** An
  inflated refcount makes an object look externally referenced, so it survives
  the pass. Wrong answer never; cycles simply not found.
- **An INCOMPLETE traverse is the same failure.** A missed edge under-counts
  internal references, so both ends of a cycle look externally referenced and
  the cycle is missed.

Item 3 of that ticket's remaining list is exactly this: *"class-typed FIELDS not
walked by the finalizer — field refs leak on instance death"*. An
instance-holds-instance edge is the single most likely edge in a real Python
cycle, so a collector built before that lands would run correctly and collect
almost nothing. Same for the aarch64 `EmitVariantClearA64/RetainA64` object arms
and the non-x86-64 scope-exit release arm (item 4): a leak-only asymmetry today
becomes a *silently weaker collector on those targets* tomorrow.

Hence blocked-by — for effectiveness, not for safety. Nothing here is unsound
before reclamation finishes; it would just be a collector that reports nothing
and looks like it works.

## The part that is genuinely new work

A **tracked-object list**. CPython maintains one explicitly; pxx has nothing
equivalent. Either thread a link through the heap-block header (the same block
that already carries `PXX_HDR_RC` and the `PXX_OBJ_MAGIC` tag) or walk the
heap. Real work, not exotic, and the honest answer to "how small is this" — the
traverse half is nearly free, this half is not.

## Gate

`make test-nilpy` green + self-host byte-identical + cross. The behavioural
check is RSS, not output: a loop that builds and drops cyclic object graphs
must stay bounded, verified against CPython's own RSS on the same program the
way `make bench-uforth` already does. Without that, a collector that never
runs and a collector that works look identical — and per the section above,
"runs but finds nothing" is this design's natural failure mode, so the RSS
assertion is the gate, not a nicety.

## Notes

- Track A because it edits A's file-lane (`compiler/builtin/builtinheap.pas`,
  the runtime, possibly the backends) — NOT a new track. Memory management is
  work over A's files, not a new place code lives.
- The cpyext extension runtime is a SEPARATE object model with its own,
  much smaller version of this: [[feature-nilpy-cpyext-cycle-collector]].
  Do not conflate them; cpyext never routes through pxx's ARC.

## Landed 2026-10-03: opt-in, `-dPXX_CYCLE_GC`

The design above, built. Still in backlog only because it is OPT-IN: making it
the NilPy default is a decision (every object grows 24 bytes, and a heap that
only grows pays a traverse per doubling), not a code step.

- **Tracked list.** The first option above: every object block from the three
  `PXXObjAlloc*` gets a 24-byte prefix `[prev][next][gcrefs]` linking it into
  one list (`PXXGcLinkNew`/`PXXGcUnlink`, `builtinheap.pas`). The header code
  never sees it -- the block base is raw + 24.
- **Traverse.** `PXXGcTraverseHook`, installed by pylib (`PyGcTraverse`),
  mirrors `PyObjFinalize` arm for arm: list items, dict keys/values/factory,
  bytes views, iterator sources, bound pairs (code + receiver), and class
  instances through the field descriptors (`PXXGcWalkFields`, kinds 3/5/6).
  Visiting only COUNTED references is what makes it safe: a missed edge keeps
  a cycle alive, never frees a live object.
- **Collect.** CPython's trial deletion: copy counts, subtract internal
  references, mark from what is left, then hold / clear / release the rest.
  DONE (destroyed) objects are pinned as roots.
- **When.** `gc.collect()` always; automatically from the allocators once the
  tracked count reaches 2 x survivors + 10000 (amortised O(1) per
  allocation). `gc.disable()`/`enable()`/`isenabled()` switch the automatic
  runs. A collection never sees a half-built object of its own allocator (the
  check runs before the new block is linked).
- **Proof.** `-dPXX_GC_STRESS` collects every 97th allocation -- inside pylib
  routines, mid-construction. A HEAP_DEBUG + STRESS sweep of every
  `test_nilpy_*.npy` showed nothing new against the baseline.
  `test_nilpy_reference_cycles_are_collected`: 20000 dropped parent/child
  pairs hold 8852 live with the collector, 131460 without (the keep control's
  figure); HD, stress and i386 byte-identical to CPython.
  The case that started this, `xml.dom.minidom` (a node holds its parent):
  3000 documents built and dropped left 75218 objects live without the
  collector, 14013 with it; 30000 documents end at 3184 -- bounded.
- **Cost measured.** 200k dropped pairs: 1.73 s vs 1.06 s without (which
  leaks them all). 200k KEPT pairs: 2.78 s vs 1.25 s -- the growing-heap case
  pays one full traverse per doubling; there is no generational split.

Not covered, each a cycle that is SAFELY not collected (the edge is unseen,
so the target looks externally held):
- closures and their captured cells (rawKind 2 is not traversed), generator
  frames;
- threadsafe builds: `PXXGcCollect` answers 0 there -- trial deletion reads
  every container while other threads mutate it, and nothing stops them.
