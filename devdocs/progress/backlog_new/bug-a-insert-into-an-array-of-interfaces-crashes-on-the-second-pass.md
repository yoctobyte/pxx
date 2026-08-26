---
slug: bug-a-insert-into-an-array-of-interfaces-crashes-on-the-second-pass
title: "`Insert` into a dynamic array of COM interfaces segfaults on the second pass through the statement"
track: A
prio: 55
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-26
summary: "A loop containing `Insert(x, a, 1)` where `a: array of ISomething` runs pass 1 correctly and segfaults on pass 2. Element kind 4 (COM interface) only — the identical loop over `array of AnsiString` and `array of LongInt` is fine, and so is Delete or Copy over interfaces in the same loop. Present on `pinned` as well as HEAD, so it predates the Delete/Insert/Copy hand-off fix; found by that ticket's leak check."
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

Pass 1 is byte-identical to fpc, `live` included, so the insert itself is right.
It is the SECOND entry to the statement that dies.

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
