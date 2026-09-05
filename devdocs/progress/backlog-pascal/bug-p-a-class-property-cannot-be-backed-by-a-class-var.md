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
summary: "PARTLY FIXED 2026-09-05. `class property V: T read FV write FV` over a `class var FV: T` now works for the TYPE-QUALIFIED spelling on BOTH declaring kinds -- `TCls.V` and `TRec.Val`, read and write, byte-identical to fpc 3.2.2 -- and terecs8 and tobject6 came OFF the skip list with output matching fpc, not merely exit 0. The cause was one thing wearing two diagnostics: both declaration parsers put any accessor that is not an instance FIELD into the METHOD slot, and the class-property access path built the name from those slots and called FindUMeth only, so a record was refused while PARSING the declaration while a class parsed and failed at the USE. The fix adds a FindClassVar fallback that re-enters on the backing global (pasparser_lval.inc), exactly as the class-VAR arm forty lines below already does, rather than growing a third accessor kind through the four UProp slots. STILL OPEN AT A THIRD SITE, AND THAT ONE CAN FAIL SILENTLY -- which is why it is worth more than the row count suggests. The INSTANCE-qualified and UNQUALIFIED spellings (`a.V := 7`, and a bare `SomethingStatic` inside the type's own static method) go through pasparser_lval.inc's instance accessor branch (the `UPropWriteMLen[pri] > 0` arm, ~line 831, and its read sibling just below), which does its own FindUMeth and has the identical missing arm -- today `setter method not found: FVal`, a clean error. THE DANGER IS IN THE FIX, NOT THE BUG: that branch builds a MakeAccessorCall with a live selfNode, and a class var is NOT per-instance, so a fix that reuses the surrounding shape instead of re-entering on the backing global would compile, run, and read PER-INSTANCE storage where the program asked for the shared slot -- a wrong value with no diagnostic, in place of the honest error we have now. Anyone taking this must assert SHARING (write through one instance, read through another) and not merely that it compiles. Two rows need it: terecs3 (behind a record-constructor wall first) and tstatic2. NOT the fix, measured and reverted earlier: widening only the record parse arms yields a declaration that cannot be used."
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

## 2026-09-05, fixed for the type-qualified spelling — and the third site named

The fix is a `FindClassVar` fallback in the class-property arm of
`ParseLValueAST`: when `FindUMeth` misses, resolve the accessor name as a class
var and **re-enter on the backing global**, exactly as the class-VAR arm forty
lines below already does. That was chosen over a third accessor kind through the
four `UProp` slots because every consumer of those slots would grow an arm — the
shape this repo calls a second path that stays broken. Re-entering also means
read and write both work from one line, and suffixes parse, so `TC.V[0]` over a
class-var array behaves like `TC.FV[0]` already did.

The record declaration parser also had to stop refusing the accessor: it now
routes a class var to the method slot the way the class parser already routed
anything that was not an instance field, so both declaration paths arrive at the
lvalue fix in the same shape. Its diagnostic for a genuine typo now says
"neither a field, a method nor a class var".

**Result, measured:** `terecs8` and `tobject6` compile, run and produce output
**identical to fpc 3.2.2** — checked as output, not as exit code, because this
harness compares exit codes and a row printing wrong values would land in the
same bucket. Both removed from the skip list.

### The third site, precisely

`a.V := 7` and a bare `SomethingStatic` inside the type's own static method do
NOT go through the arm that was fixed. They reach the instance/unqualified
accessor path in the same file (`pasparser_lval.inc`, the
`UPropWriteMLen[pri] > 0` branch, around line 831), which builds the setter name
and calls its own `FindUMeth` — the identical missing arm, one branch over:

    pascal26:13: error: setter method not found: FVal

Its read sibling is a few lines below it. The lowering differs from the fixed
arm: that branch builds a `MakeAccessorCall` with `selfNode`, and a class var is
not per-instance, so the correct move is again to re-enter on the backing global
and ignore the receiver — not to synthesise a call.

**Two rows wait on it:** `tstatic2`, and `terecs3` behind a record-constructor
wall it hits first. Left undone deliberately rather than attempted at the end of
a session: it is a different lowering in a branch with a live `selfNode`, and
the failure mode of getting it wrong is a silent per-instance read of shared
storage.
