---
track: A
prio: 70
type: bug
blocked-by: []
summary: "A local `array[0..N] of IFoo` was never zero-initialised, so the first assignment to an element ran the ARC release on STACK GARBAGE and dispatched _Release through a junk IMT. It presented as `uses sysutils` causing a segfault — a red herring: that unit merely dirties the stack the routine is about to reuse."
status: done
owner: claude-acp
---

# A local array of interfaces is not zero-initialised

- **Track A** (`compiler/parser.inc` `EmitManagedLocalsZeroInit`,
  `compiler/symtab.inc` predicates).
- Found 2026-08-20 while writing the regression test for
  `bug-a-an-as-cast-assigned-to-an-interface-variable-is-not-retained` — the new
  test crashed on the *fixed* compiler, which is how a second, unrelated bug
  surfaced.

## Measured

```pascal
procedure P;
var i: Integer; keep: array[0..2] of IFoo;
begin
  i := 0;
  keep[i] := nil;        { SIGSEGV }
end;
```

| variant | result |
| --- | --- |
| with `uses sysutils` | **SIGSEGV** |
| identical program without it | runs clean |
| constant index `keep[0] := nil` | runs clean |
| global array instead of local | runs clean |
| **no sysutils, but a hand-written stack-dirtying call first** | **SIGSEGV** |

FPC runs every variant clean.

## Cause

`EmitManagedLocalsZeroInit` nils every managed local before the body. Its chain
has an arm for a scalar COM interface (`SymIsComInterface`) and an arm for a
static array of managed RECORDS — and `array[0..N] of IFoo` matches neither:

- `SymIsComInterface` answers **False for an array** on purpose (the array's
  slot is not itself a reference), and
- the record-array arm asks `RecordHasManagedFields(ElemRec)`, which is False
  because an interface UCls has no managed **fields**.

So the slots kept stack garbage, and the very first `keep[i] := x` — which
correctly releases the old occupant — released that garbage, dispatching
`_Release` through a junk IMT.

## The red herring, and why it cost time

The reproducer's only difference was one `uses sysutils` line, which invites the
conclusion that sysutils is at fault (and this repo has real
`uses sysutils` bugs, so the story was plausible). It is entirely accidental:
the unit's initialisation runs first and **dirties the stack** the routine then
reuses. On a clean stack the garbage is zero and the bug cannot be observed —
which is also why a constant index and a global array appeared to work.

Confirming it took one program: dirty the stack by hand, drop sysutils, and the
crash reproduces exactly. **When a bug's trigger is "this unrelated line", suspect
the stack, not the line.** The regression test therefore dirties the stack
itself, so the failure is deterministic rather than a lottery.

## Fix

- Split `RecIsComInterface(recId)` out of `SymIsComInterface` — the same
  question has to be asked of an array's ELEMENT rec, where the symbol-level
  predicate deliberately answers False.
- Add `SymElemIsComInterface(symIdx)` for `array[0..N] of IFoo`, and document on
  `SymIsComInterface` that arrays answer False on purpose so the next caller
  knows to reach for the element predicate.
- Give `EmitManagedLocalsZeroInit` the missing arm.

## Left open — the cleanup half

The array is now initialised correctly, but its elements are still **never
released at scope exit**: `SymNeedsManagedCleanup` has the same two-arm gap, and
`EmitManagedLocalCleanup` has no per-element interface walk
(`PXXArrayReleaseImmediate` knows baseKind 1 = string and 3 = record, not
interfaces). Measured: a routine filling `array[0..2] of IFoo` and returning
destroys 0 of 3. That is a bounded leak rather than a crash, and closing it wants
a new `PXXIntfArrayRelease(arrData, len, ifaceId)` runtime helper — filed as
`bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit`.

## Test

`test/test_interface_local_array_zero_init.pas` — 5/5, identical to FPC. Nil
store through a variable index, fill-and-read-back, overwrite, constant index,
and a 2-D array; each preceded by an explicit stack-dirtying call. **The pinned
binary segfaults on this file** rather than printing a failure.

## Gate

`make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.
