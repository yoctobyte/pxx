---
slug: bug-p-a-class-property-cannot-be-backed-by-a-class-var
title: "A class property cannot be backed by a class var — the accessor resolver and the lvalue path both only know fields and methods"
track: P
prio: 45
type: bug
status: backlog
found: 2026-09-05
found-by: frankA
owner: ""
blocked-by: []
summary: "`class property V: T read FV write FV` where FV is a `class var` is refused: `record property accessor is neither a field nor a method: FV` (pasparser_decl.inc:3857/3875). Adding FindClassVar to those two arms is NOT the fix and was measured as insufficient -- with the parse arm widened the declaration is accepted and then BOTH accesses fail at use, because pasparser_lval.inc:1073 only knows a METHOD-backed class property write (`if UPropWriteMLen[cpPri] <= 0 then Error('class property is read-only')`) and the read side has no field-backed arm either. So this is a lvalue/expression-path gap wearing a parser diagnostic. fpc 3.2.2 accepts it and prints 41/7/7 for a probe where the property is written through one instance and read through another. THREE conformance rows stop here as their FIRST error -- terecs3, terecs8, tobject6 -- after the `class var` half landed 2026-09-05; tobject6 is behind the old-style-object decision regardless. Sharing storage is not the issue: the ClassVar slot is an ordinary anonymous global and `TR.FVal` works today; only the property indirection is missing."
---

# A class property cannot be backed by a class var

## Measured

    program cp;
    {$mode delphi}
    type
      TR = record
      class var
        FVal: LongInt;
      class property Val: LongInt read FVal write FVal;
      end;
    var a, b: TR;
    begin
      TR.Val := 41;  WriteLn(TR.Val);   { fpc: 41 }
      a.Val := 7;    WriteLn(b.Val);    { fpc: 7  — shared, not per-instance }
                     WriteLn(TR.FVal);  { fpc: 7  }
    end.

fpc 3.2.2 prints `41 / 7 / 7`. pxx refuses at the declaration:

    pascal26:7: error: record property accessor is neither a field nor a method: FVal

## What was tried and did NOT work — recorded so it is not tried again

Widening the two accessor arms in `ParseRecordPropertyDecl` to accept a
`FindClassVar` hit makes the declaration parse. Both accesses then fail at USE:

    pascal26:11: error: class property is read-only: Val      { the write }
    …and the read fails at its own use site too

`pasparser_lval.inc:1073` gates the write on `UPropWriteMLen`, the METHOD
accessor length, so a field-backed class property is read-only by construction
there — and the read path has no field-backed arm either. **The parser
diagnostic is not where the gap is.** The change was reverted; the rebuilt
compiler was byte-identical to the build before it, which is the proof the
revert was exact.

## Why it is worth doing

Three conformance rows stop here as their first error now that the `class var`
half has landed (terecs3, terecs8, tobject6). The storage already exists and
`TR.FVal` resolves today — only the property indirection is missing, so this is
plumbing an existing slot through an existing accessor mechanism rather than a
new storage model.

## Where to start

`UPropReadFOff/FLen` and `UPropWriteFOff/FLen` store a NAME, not an offset, so
the downstream resolution re-looks-up the name. Check whether the lvalue path
can be taught to try the ClassVar registry when the field lookup misses, rather
than adding a third accessor kind — a third kind means every consumer of the
four Upro slots grows an arm, which is the shape this repo calls a second path
that stays broken.
