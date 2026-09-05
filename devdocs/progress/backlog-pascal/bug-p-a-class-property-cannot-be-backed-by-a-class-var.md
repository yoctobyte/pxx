---
slug: bug-p-a-class-property-cannot-be-backed-by-a-class-var
title: "A class property can only be backed by a static METHOD — never by a class var, on a class or a record"
track: P
prio: 50
type: bug
status: backlog
found: 2026-09-05
found-by: frankA
owner: ""
blocked-by: []
summary: "`class property V: T read FV write FV` where FV is a `class var` is refused on BOTH type kinds, and the two spellings fail with different messages from different places, which is why it read as one narrow bug. On a RECORD the declaration is refused at parse time: `record property accessor is neither a field nor a method: FV` (pasparser_decl.inc:3857/3875). On a CLASS the declaration parses and the USE fails: `class property accessor not found: FV` (pasparser_lval.inc:1084). The cause is one thing: the class-property access path at pasparser_lval.inc:1063-1084 reads ONLY the METHOD accessor slots (UPropRead/WriteMOff/MLen) and then FindUMeth, so a class property can be backed by a static method and by nothing else. Adding FindClassVar to the record parse arms was MEASURED as insufficient -- the declaration then parses and both accesses still fail at use. fpc 3.2.2 accepts both spellings; a probe writing through one instance and reading through another prints 41/7/7. FOUR conformance rows stop here as their first error: terecs3, terecs8, tobject6 (records) and tstatic2 (a CLASS, found by subtraction from the undefined-variable wall). tobject6 is behind the old-style-object decision regardless. Storage is not the issue: the ClassVar slot is an ordinary anonymous global and `TC.FV` resolves today; only the property indirection is missing."
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


## 2026-09-05, later — it is not record-only, and the title was a hypothesis

The first version of this ticket said "record property accessor" because a
record was where I met it. Measured within the hour, on a CLASS:

    type
      TC = class
      private
        class var FV: Integer;
      public
        class property V: Integer read FV write FV;
      end;
    begin
      TC.V := 9; WriteLn(TC.V);   { fpc 3.2.2: 9 }
    end.

    pascal26:11: error: class property accessor not found: FV

**A different message, from a different file, at a different phase** — the
record spelling is refused while PARSING the declaration, the class spelling
parses and fails at the USE. That is exactly why it looked like two problems and
is one: `pasparser_lval.inc:1063-1084` builds the accessor name from
`UPropReadMOff/MLen` or `UPropWriteMOff/MLen` — the METHOD slots — and then calls
`FindUMeth`. There is no field-backed arm on either side, so **a class property
can be backed by a static method and by nothing else**, whatever declares it.

`tstatic2` joins the row list from that: it is a class with
`class property SomethingStatic: Integer read FSomethingStatic write SetSomethingStatic`,
and the unqualified read inside the static method is the property, not the class
var. It surfaced as `undefined variable (SomethingStatic)` in the
undefined-variable wall, which is why it was not obviously this bug.

**Fix the lvalue path, not the parse arms.** The record-side parse refusal is
the surface; widening it alone produces a declaration that cannot be used.
