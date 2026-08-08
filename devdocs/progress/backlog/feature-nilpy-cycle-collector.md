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
