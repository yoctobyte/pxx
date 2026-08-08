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

## Why the traverse half is nearly free (measured, not assumed)

`PXXRecordRelease` (`compiler/builtin/builtinheap.pas:2283`) is ALREADY a
descriptor-driven walk over a type's managed members: per member it reads
offset / kind / arrayCount / typeRef, recurses through sub-records and
dynarrays, and has cases for variant slots (kind 5, via `PXXVarClear`) and
NilPy class-typed fields (kind 6, via `PXXObjRelease`).

That is the shape a traverse function needs. The difference between "release
each managed child" and "visit each managed child" is the LEAF ACTION. So the
per-type reference enumeration a collector depends on is existing, tested
machinery — not new codegen, not new RTTI, not a new emitted function per type.

## Why it is nonetheless blocked, and on what

Trial deletion needs accurate refcounts on the objects in question, and NilPy
class instances **have no refcount at all yet** — that is
[[feature-nilpy-object-reclamation]]'s five-slice ladder, which has not started.
You cannot collect cycles among objects nobody counts. Land reclamation first;
this becomes a small addition rather than a project.

## The part that is genuinely new work

A **tracked-object list**. CPython maintains one explicitly; pxx has nothing
equivalent. Either thread a link through the existing heap-block header word
(the `[-16]` slot the reclamation design already uses for the refcount) or walk
the heap. Real work, not exotic, and the honest answer to "how small is this"
— the traverse half is cheap, this half is not zero.

## Gate

`make test-nilpy` green + self-host byte-identical + cross. The behavioural
check is RSS, not output: a loop that builds and drops cyclic object graphs
must stay bounded, verified against CPython's own RSS on the same program the
way `make bench-uforth` already does. Without that, a collector that never
runs and a collector that works look identical.

## Notes

- Track A because it edits A's file-lane (`compiler/builtin/builtinheap.pas`,
  the runtime, possibly the backends) — NOT a new track. Memory management is
  work over A's files, not a new place code lives.
- The cpyext extension runtime is a SEPARATE object model with its own,
  much smaller version of this: [[feature-nilpy-cpyext-cycle-collector]].
  Do not conflate them; cpyext never routes through pxx's ARC.
