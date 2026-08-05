---
summary: "x86-64 only: `b := a` on a dynamic array copy-on-writes instead of ALIASING — writes through either name are invisible to the other. FPC, i386, arm32, aarch64 and riscv32 all alias. Dynamic arrays are reference types; this is silent wrong behaviour on the flagship target"
type: bug
track: A
prio: 65
blocked-by: decide-dynamic-array-value-vs-reference-semantics
---

# x86-64: dynamic-array assignment copies instead of aliasing

- **Type:** bug — Track A (x86-64 codegen / dynamic-array reference semantics)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A, cross-checking the fix for
  `bug-a-arm32-dynamic-array-assignment-has-no-store-arm` against the other
  targets. Pre-existing: **`pinned` behaves identically**, so it is not recent.

## Repro

```pascal
var a, b: array of Integer;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  b := a;
  writeln('after b:=a      a[0]=', a[0], ' b[0]=', b[0]);
  b[0] := 77;                      { write through B }
  writeln('after b[0]:=77  a[0]=', a[0], ' b[0]=', b[0]);
  a[1] := 88;                      { write through A }
  writeln('after a[1]:=88  a[1]=', a[1], ' b[1]=', b[1]);
end.
```

| | after `b:=a` | after `b[0]:=77` | after `a[1]:=88` |
| --- | --- | --- | --- |
| **FPC** | a=1 b=1 | **a[0]=77** b[0]=77 | a[1]=88 **b[1]=88** |
| arm32 / riscv32 / i386 / aarch64 | a=1 b=1 | **a[0]=77** b[0]=77 | a[1]=88 **b[1]=88** |
| **pxx x86-64** | a=1 b=1 | **a[0]=1** b[0]=77 | a[1]=88 **b[1]=2** |

Writes through *either* name are invisible to the other on x86-64 — so it is a
copy-on-write in both directions, not a one-off deep copy at assignment.
Reproduces with both plain (`Integer`) and managed (`string`) element types, so
it is not the managed-element machinery.

## Why this matters

Dynamic arrays are **reference types** in FPC/Delphi. `b := a` aliases; the two
names are the same array until one is `SetLength`'d. Code that hands an array to
a helper, mutates it through the second name, and expects the caller to see the
change is ordinary and correct — and silently does nothing on x86-64. No error,
no crash, just a stale read much later. That is the expensive shape described in
the debugging playbook.

It is also the WRONG WAY ROUND for the usual cross-target story: here the
flagship target is the outlier and every cross target is right.

## The open question — direction is a real design call

Two defensible directions, and this ticket does not presume one:

1. **FPC parity (recommended):** drop COW on whole dynamic arrays so x86-64
   aliases like everyone else. Matches the oracle, matches the other five
   targets, matches what `compat` means for Track P. Blast radius is the worry:
   COW has been x86-64's behaviour for a long time, so existing code and tests
   may lean on the copy without anyone noticing.
2. **Keep COW deliberately** and document it as a dialect divergence — then the
   FIVE other targets are the ones that need changing, which is a much larger
   job and puts pxx permanently out of parity on a core type.

Recommend (1). Filed as a `bug-` per CLAUDE.md's escape rule — a compat finding
that produces *silent wrong behaviour* is a bug in the owning lane, not a parity
nicety.

**Blocked on `decide-dynamic-array-value-vs-reference-semantics`** (the pre-existing Track U ticket for this fork; a duplicate I filed was merged into it). Since filing
this, the COW turned out to be DELIBERATE: `IR_DYNUNIQUE` + `PXXDynArrayUnique`
exist for it and `compiler/ir.inc` states the invariant outright — *"writing
through one alias never mutates another at any depth."* So fixing this to match
FPC would overrule a design decision rather than repair a slip, and that is
Track U's call, not an agent's. The observation here stands either way; only the
direction is blocked.

## Related

- `bug-a-arm32-dynamic-array-assignment-has-no-store-arm` — the arm32/riscv32
  gap whose fix surfaced this. `test/test_dynarray_whole_assign.pas` was written
  during that fix and **deliberately does not assert aliasing**, so it stays
  green either way; whoever takes this ticket should add the aliasing assertions
  there once the direction is settled.
