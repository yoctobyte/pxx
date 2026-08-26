---
slug: bug-a-insert-into-an-array-of-interfaces-crashes-on-the-second-pass
title: "`Insert` into a dynamic array of COM interfaces takes no reference for the inserted element"
track: A
prio: 55
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
summary: "pxx spells a COM interface tyRecord, so Insert's gap store fell into IR_COPY_REC and copied the instance pointer with NO AddRef. The array owned N+1 slots holding N references, so releasing it destroyed an object another owner still had, and that owner's own release then segfaulted. Filed as a second-pass crash; that narrowing was wrong — a SINGLE Insert is enough, the loop only changed where it surfaced. Store through PXXIntfAssign instead, tested before the record arms."
---

# Repro

```pascal
{$mode objfpc}{$H+}{$interfaces com}
type
  ITest = interface ['{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}'] function N: LongInt; end;
  TTest = class(TInterfacedObject, ITest) ... end;
  TIA = array of ITest;
procedure Loop;
var a: TIA; i, j: LongInt;
begin
  for j := 1 to 3 do
  begin
    SetLength(a, 3);
    for i := 0 to 2 do a[i] := TTest.Create(i);
    Insert(TTest.Create(9), a, 1);
    WriteLn('pass ', j, ' len=', Length(a), ' live=', live);
    a := nil;
  end;
end;
```

| | fpc 3.2.2 | pxx (HEAD and `pinned`) |
| --- | --- | --- |
| pass 1 | `pass 1 len=4 live=4` | `pass 1 len=4 live=4` |
| pass 2 | `pass 2 len=4 live=4` | **SIGSEGV** |
| pass 3 | `pass 3 len=4 live=4` | — |
| final | `final live = 0` | — |

**The title's narrowing was WRONG and is corrected below.** "Second pass" was
what the first repro showed, but it is not the rule: a SINGLE `Insert` already
leaves the program broken. It survived to the ticket because the loop repro was
the one in hand; narrowing it properly was the first thing the fix needed.

# What it is not

Measured, each in the same loop shape:

- `array of AnsiString` — 3 passes, correct, matches fpc.
- `array of LongInt` — 3 passes, correct, matches fpc.
- `Delete(a, 2, 2)` over the interface array — 2000 passes, `live = 0` at the
  end, no growth in maxRSS.
- `Copy(a, 0, 2)` over the interface array — same.
- `Delete` + `Copy` together over the interface array — same.

So it is `Insert` **and** element kind 4 **and** a second pass. Any one of the
three removed and it is fine.

# Where to look

`AN_DYN_INSERT`'s arm in `compiler/ir.inc`. All three of these arms build a
hidden fresh-buffer temp and empty it with `SetLength(temp, 0)` before sizing
it, precisely so a second pass does not reuse the previous pass's block — the
head comment there records that a loop was the case that forced the design. The
suspicion is that Insert's retain/release walk over the OLD buffer and the temp
disagree for kind 4 specifically, so the second pass empties a temp whose
elements have already been released; but that is a hypothesis, not a
measurement, and the arm should be read before it is believed.

Related: kind 4 was the element type that
[[bug-a-delete-on-a-dynamic-array-of-interfaces-dangles-every-survivor]] found
missing from all three arms' retain walks. This may be the same absence in a
different place, which is the argument for reading all three arms together
rather than patching Insert alone.

# Found by

The leak check written for
[[bug-a-a-dynarray-delete-temp-holds-the-new-buffer-until-scope-exit]] — a 2000
iteration loop doing Delete, Copy and Insert over an interface array, to prove
that hand-off did not leak. It did not leak; it crashed, on `pinned` too, which
is how the two were told apart.

# The real narrowing

A single `Insert` is enough. What varies is only WHERE the damage surfaces:

```pascal
v := TTest.Create(9);
Insert(v, a, 1);
a := nil;      { fpc: live = 1, v still holds it.  pxx: live = 0 }
v := nil;      { pxx: SIGSEGV — releasing memory already freed }
```

On `pinned` the crash came at procedure exit instead of at the `v := nil`,
because the fresh-buffer temp held a second reference until then and pushed the
whole accounting one scope later. That is
[[bug-a-a-dynarray-delete-temp-holds-the-new-buffer-until-scope-exit]], fixed
earlier the same evening, and fixing it moved this crash EARLIER — which is how
the two got told apart rather than blamed on each other.

# Cause

pxx spells a COM interface `tyRecord` — measured, not assumed: an instrumented
build reported `elemTk=5 (tyRecord) elemRec=22 elemSz=8`, the instance pointer.
So the gap store fell into `IR_COPY_REC` and copied the pointer RAW, with no
AddRef. `RecordHasManagedFields` is False for an interface, so even the MANAGED
record arm above it would not have caught it, and the buffer-wide
`PXXDynArrayRetainImmediate` could not either — it runs while the gap is still
nil, as its own comment says.

Result: the array owned N+1 slots and held N references. Releasing it destroyed
an object another owner still had.

# Fix

Test for `ManagedElemKind = 4` BEFORE the record arms, and store through
`PXXIntfAssign(gapAddr, srcAddr, ifaceId)` — retain source, release old dest,
copy, in that order. It is the primitive the by-value interface param path
already uses instead of hand-rolling the halves, and the gap is fresh zeros so
the release-of-old is a no-op.

The one subtlety, and it cost a build to find: **what `dcValTmp` holds depends
on which capture branch ran.** An LVALUE operand is captured with
`IRLowerAddress`, so the slot holds an address and must be LOADED; an rvalue is
captured with `IRLowerAST`, so the slot holds the interface VALUE and is its own
storage, so the slot's own address is what `PXXIntfAssign` wants. Getting this
wrong dereferences a value as an address: the first cut fixed the variable form
and made the `Insert(TTest.Create(9), ...)` form crash instantly, worse than
before. The gap store now spells the same condition as the capture, deliberately.

# Gate

All three shapes byte-identical to fpc 3.2.2, refcounts included:

| | fpc | pxx before | pxx now |
| --- | --- | --- | --- |
| `Insert(v, a, 1)`, then `a := nil` | `live = 1` | `live = 0`, then SIGSEGV | `live = 1` |
| ...then `v := nil` | `live = 0` | — | `live = 0` |
| `Insert(Create, a, 1)` in a 3-pass loop | 3 passes, `live = 0` | pass 1, then SIGSEGV | 3 passes, `live = 0` |

`test/test_dynarray_delete_insert_copy_of_interfaces.pas` gains
**InsertVarCase** and **InsertRValueCase**. The file is named
delete_insert_copy and had no Insert case at all, which is precisely why this
lived: Delete, Copy and Shrink were covered and the operation in the middle of
the name was not. Both operand shapes are present because they capture
differently and only one was wrong at a time.

Leak check: 2000 iterations of Delete + Copy + **Insert** over an
`array of ITest` — `live = 0` at the end, maxRSS identical to the fpc build's.
`fpc-testsuite tarray11.pp` still exit 0. Every `test_dyn*` and `test_intf*`
GREEN. pascal-conformance 346/0/170/34, fgl 7/7. Self-host byte-identical.
`gate.sh quick` GREEN.


## Log
- 2026-08-26 — resolved, commit 8b4987893.
