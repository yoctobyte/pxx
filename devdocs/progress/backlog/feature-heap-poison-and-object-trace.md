---
track: A
prio: 78
type: feature
---

# Debug heap: poison-on-free, quarantine, and an object retain/release trace

Child 1 of [[feature-debuggability-umbrella]] — the cheapest one, and the one
that would have caught the most expensive bug of the campaign.

The NilPy object-reclamation bug family (see
[[project_nilpy_object_reclamation_arc]] and the tickets around
[[bug-nilpy-slice-of-variant-local-returned-is-unusable]]) keeps costing whole
sessions for one reason: **a use-after-free presents as a plausible value.**
`len(self.evidence)` answered `1751084129` — ASCII bytes read as an integer,
i.e. a recycled neighbour's allocation. Nothing in that number says "freed", so
three sessions were spent on type-tagging theories before the ownership bug was
found. The bug itself, once seen, was one retain.

Two switches in `compiler/builtin/builtinheap.pas` would have made it a
one-run diagnosis.

## 1. `PXX_HEAP_DEBUG` — poison + quarantine

On `PXXFree`: fill the payload with `$DD` and hold the block off the free list
for N frees (a small ring) before really releasing it. A dangling read then
returns `$DDDDDDDDDDDDDDDD` — unmistakable, and `len()` on it is an obviously
absurd constant rather than a plausible one. Writing through a dangling pointer
also becomes visible: the quarantined block's poison is checked on real release.

~30 lines, one file, no compiler change. Highest value/effort ratio of anything
on this list.

## 2. `PXX_OBJTRACE` — refcount trace

`PXXObjRetain` / `PXXObjRelease` / `PXXObjAlloc*` log `op addr rc` (and the
magic tag) to stderr. Every bug in this family is the same question — "who took
a reference and who dropped it?" — and today it is answered by inference from
symptoms. With the trace it is answered by reading the log.

Add a cheap filter (an address, or a count threshold) so a real app's output
stays usable.

## Scope

Children 2-5 (the compiler-side `PXXDBG` switch, real DWARF for gdb, compiler
self-debugging, the CPython differential harness) live in
[[feature-debuggability-umbrella]]. This ticket is the runtime-lib half only.

Note for whoever picks up the DWARF child: poison + trace work at `-O2`, where
these bugs actually appear. `-g` forces `-O0`, which changes the allocation
timing that CAUSES this bug class — which is why these two come first.

## Gate

`tools/gate.sh quick` + self-host byte-identical with every switch OFF (the
default path must be unchanged — the poison fill and the trace must sit behind
the flag, not behind a runtime `if` in the hot allocator path where it costs).
Then a regression test that a deliberately dangling read returns poison.
