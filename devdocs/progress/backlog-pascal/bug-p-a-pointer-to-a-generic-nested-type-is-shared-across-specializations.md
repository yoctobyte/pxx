---
slug: bug-p-a-pointer-to-a-generic-nested-type-is-shared-across-specializations
title: "A pointer to a generic class's nested type keeps the FIRST specialization's pointee"
track: P
prio: 45
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "MECHANISM LOCATED 2026-09-05 (frankS), at ea4187d4d: the nested RECORD across two specializations WORKS (prints `7 hi`) and only the POINTER to it fails, with the error following declaration order — the first specialization's `PCell` wins and the second reuses it. Cause is pasparser_decl.inc:6984, the tkCaret arm, calling RegisterPtrAlias with the BARE name and never consulting ParsingClassBodyCi, while AddClassLikeType (pasparser_class.inc:350) qualifies the name and calls AddNestedType for a class or record in the same position. Class was fixed, then record; the POINTER arm is the third sibling of that double case and is still flat. HOISTING DOES NOT FIX IT — measured, forcing the pointee to hoist changes nothing, because the collision is on PCell and not on TCell. The fix is an owning-class column on the alias table plus scope-aware lookup; sentinel must be -1 since class 0 is real. Not a one-liner and not attempted: a core registry every type reference reads."
---

# Repro

```pascal
{$mode objfpc}
program v1;
type
  generic TBox<_T> = class(TObject)
    type PCell = ^TCell; TCell = record d: _T; end;
    var head: PCell;
    procedure Put(v: _T);
  end;
procedure TBox.Put(v: _T); var n: PCell; begin new(n); n^.d := v; head := n; end;
type
  TIntBox = specialize TBox<Integer>;
  TStrBox = specialize TBox<AnsiString>;
var i: TIntBox; s: TStrBox;
begin
  i := TIntBox.Create; s := TStrBox.Create;
  i.Put(7); s.Put('hi');
  WriteLn(i.head^.d,' ',s.head^.d);
end.
```

`pascal26:0: error: incompatible types: cannot assign AnsiString to Integer`

fpc 3.2.2 compiles it and prints `7 hi`. Pin v403 gives the same error, so this
is pre-existing.

# It is ORDER-DEPENDENT, which is what names the mechanism

Swap the two `specialize` lines and the message swaps with them:

| declared first | error |
| --- | --- |
| `TBox<Integer>` | cannot assign **AnsiString to Integer** |
| `TBox<AnsiString>` | cannot assign **Integer to AnsiString** |

The pointee is whatever the FIRST specialization made it. That is a value read
from a shared slot, not from the type.

# Three-way control — the trigger is a CONJUNCTION

| probe | shape | result |
| --- | --- | --- |
| v1 | pointer to nested type, **two** specializations | **refused** |
| v2 | pointer to nested type, **one** specialization | compiles, correct |
| v3 | nested record used **directly**, two specializations | compiles, correct (`7 hi`) |

So it is **not** "pointers to nested types are broken" (v2) and **not** "nested
types are not specialized" (v3 — the record IS specialized per instantiation).
It is specifically the pointer's POINTEE resolution being done once and reused.
A fix aimed at either half alone will pass its own probe and leave this failing.

The self-reference in the original (`next: PCell` inside `TCell`) is NOT
required — v1 has no self-reference.

# Where it is NOT

`pasparser_generic.inc`'s nested-type HOISTING is a different path and does not
fire here: hoisting is triggered only when a nested type is used as a GENERIC
ARGUMENT, and `PCell = ^TCell` uses it as a pointee. Its header comment says so
("ONLY WHAT IS ACTUALLY USED AS A GENERIC ARGUMENT IS HOISTED"). Do not start
there.

# Why it matters beyond the two rows

This is the canonical linked-list generic — a nested node record plus a pointer
to it is how you write `TList<T>` in Object Pascal without dynamic arrays. Any
program specializing such a container twice in one compilation gets a compile
error whose text names neither the template nor the specialization.

Also: the diagnostic carries **line 0**, i.e. no location at all, which is its
own small defect — the message cannot be traced to a line by anyone reading it.

# Corpus rows

`tgeneric6.pp` and `tgeneric8.pp` of the FPC test suite, both blocked on exactly
this after the header-lexing fix (`9a3b8f38c`) let the parser reach the bodies.
They are the two-row shape noted in [[feature-pascal-corpus-fpc-testsuite]].

# Gate

Both orders of the repro compiling and printing `7 hi`, v2 and v3 unchanged,
plus tgeneric6/tgeneric8 diffed against fpc OUTPUT rather than scored on an exit
code, plus `make test` and the self-host fixedpoint.

## Mechanism located — the POINTER arm of a double case already fixed twice (frankS, 2026-09-05)

Measured at `ea4187d4d`, compiler/pascal26 sha `25113fd329a9`
(`converged after 1 round(s)`). Four probes, and they discriminate:

| probe | result |
| --- | --- |
| nested RECORD, two specializations | **BUILDS**, prints `7 hi` |
| POINTER to that nested record, two specializations | `cannot assign AnsiString to Integer` |
| same, declaration order swapped | `cannot assign Integer to AnsiString` — **the error follows the order** |
| ONE specialization only (control) | **BUILDS**, prints `hi` |

The order-flip is the signature: **the first specialization's `PCell` wins and
the second reuses it.**

### Where

`pasparser_decl.inc:6984`, the `tkCaret` arm of the type-declaration loop:

```pascal
RegisterPtrAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId, targetNOff, targetNLen);
```

`tnOff/tnLen` is the **bare** name, and `RegisterPtrAlias` (`symtab.inc:246`)
never consults `ParsingClassBodyCi`. Compare `AddClassLikeType`
(`pasparser_class.inc:350`), which for a class or record inside a class body
registers under the QUALIFIED name when the bare one is taken and calls
`AddNestedType(ParsingClassBodyCi, tname, Result)` so a bare reference from
inside the owner's own body still resolves. **A pointer alias gets neither.**

That function's own comment records this being fixed once already: *"ONE
function, because the class branch had this and the RECORD branch did not ...
the exact sibling case normalise-dont-special-case is about."* Class was fixed,
then record. **The pointer arm is the third sibling and it is still flat.**

**Why reading the fixed arms cannot find it** (frankB's rule, and it is exactly
this shape): a rule spelled per caller fails by a MISSING copy, not a divergent
one. The class and record paths agree with each other perfectly — they are the
same function — so diffing them reveals nothing. The instrument is the callee's
contract, not a comparison of the callers.

### The route that looks obvious and does NOT work

**Hoisting does not fix this, measured.** `pasparser_generic.inc:131` already
mints per-specialization names (`TDict$Integer$LongInt$TPair`) and its trigger is
*used as a generic argument*. Making `TCell` a generic argument so it hoists
changes nothing — the same `cannot assign AnsiString to Integer`. Recorded as a
negative result because a reader would start there, as I did: the pointer alias
collides whether or not its pointee is hoisted, because the collision is on
`PCell`, not on `TCell`.

### The fix, and why it is not a one-liner

The alias table has `AliasUnitIdx` and `AliasDeclImpl` and **no owning-class
column**. The fix is that column plus a scope-aware lookup — the alias-table twin
of `AddNestedType`. Two hazards for whoever takes it:

- **Class index 0 is a real class**, so the sentinel must be `-1` and an
  unwritten row must be loud, never silently "owned by class 0". frankB stored
  `AliasEnumId` as *id + 1* for exactly this reason after an unwritten row read
  as *enum 0*.
- **Every `Register*Alias` that bumps `AliasCount` must set the new column**, and
  a missing copy is invisible for the reason above. Prefer one choke point over
  N assignments.

Not attempted here: this is a core registry every type reference reads, so it is
the destabilising kind that lands incrementally, not at the end of a session.
The diagnosis is the deliverable.
