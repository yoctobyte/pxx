---
slug: bug-p-a-pointer-to-a-generic-nested-type-is-shared-across-specializations
title: "A pointer to a generic class's nested type keeps the FIRST specialization's pointee"
track: P
prio: 55
type: bug
blocked-by: []
status: backlog
owner: "frankD"
created: 2026-09-05
summary: "GENERICS ARE NOT INVOLVED -- corrected by frankD 2026-09-05, population only; frankS's mechanism below is unchanged and is the deeper half. Two ORDINARY classes, no `generic` and no `specialize`, each declaring `type PCell = ^TCell; TCell = record d: X; end;`, compile the SECOND class's `n^.d := v` against the FIRST class's pointee; fpc 3.2.2 prints `7 hi`. That is pasparser_decl.inc:6984 registering the pointer alias under its BARE name with no owning-class column -- the third sibling arm AddClassLikeType already fixed for classes and records. Keyed on NEITHER name: different alias names and different pointee names each still fail. Records trigger it too. Prio 45->55: the population is every class or record with a nested pointer type, not templates. Measured at 4ef367091, binary 25113fd3, fpc 3.2.2, x86-64."
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

---

# 2026-09-05, frankD: the generic is a passenger — population, not mechanism

**frankS's diagnosis above stands and is the deeper half.** This section only
widens who is affected. `pasparser_decl.inc:6984` registering under the bare name
predicts exactly this, so the two findings agree; what follows is the part that
changes the ranking rather than the repair.

Strip the generics out and nothing changes:

```pascal
{$mode objfpc}
program plain;
type
  TIntBox = class(TObject)
    type PCell = ^TCell; TCell = record d: Integer; end;
    var head: PCell; procedure Put(v: Integer); end;
  TStrBox = class(TObject)
    type PCell = ^TCell; TCell = record d: AnsiString; end;
    var head: PCell; procedure Put(v: AnsiString); end;
procedure TIntBox.Put(v: Integer);    var n: PCell; begin new(n); n^.d := v; head := n; end;
procedure TStrBox.Put(v: AnsiString); var n: PCell; begin new(n); n^.d := v; head := n; end;
var i: TIntBox; s: TStrBox;
begin i := TIntBox.Create; s := TStrBox.Create; i.Put(7); s.Put('hi');
      WriteLn(i.head^.d,' ',s.head^.d); end.
```

pxx: `error: incompatible types: cannot assign AnsiString to Integer`.
fpc 3.2.2: **`7 hi`**.

## Boundary — ten probes, all in the plain (non-generic) shape

| # | shape | result |
| --- | --- | --- |
| a_direct | nested RECORD used directly, no pointer, two classes | **OK** `7 hi` |
| e_one | **one** class, one nested pointer alias | **OK** `hi` |
| h_mixed | class A uses a TOP-LEVEL alias, class B a nested one | **OK** `7 hi` |
| f_same | two nested aliases, **both pointees Integer** | **OK** `7 9` — a trap, see below |
| plain | two nested aliases, same names, different pointees | **REFUSED** |
| b_diffptr | two nested aliases, **different alias names** (`PC1`/`PC2`) | **REFUSED** |
| c_diffcell | two nested aliases, **different pointee names** (`TCellA`/`TCellB`) | **REFUSED** |
| i_toplevelcell | two nested aliases, pointees are **top-level** records | **REFUSED** |
| d_records | the same in two **records** rather than classes | **REFUSED** |
| g_rev | `plain` with the two classes swapped | **REFUSED, message reversed** |

- **The trigger is the SECOND class/record body to declare a nested pointer
  alias.** One is fine (`e_one`); one nested plus one top-level is fine
  (`h_mixed`).
- **Keyed on neither name** (`b_diffptr`, `c_diffcell`). Worth stating explicitly
  because "collides under the bare name" invites the reading that renaming one of
  them is a workaround. It is not — there is no owning-class column at all, so two
  differently-named nested aliases still land in one flat undifferentiated table.
- `d_records` reproduces it in two **records**, so the fix has the same two-arm
  shape `AddClassLikeType` already has. fpc rejects the record file for an
  unrelated reason, so diff the CLASS form against fpc.

## `f_same` is a trap, and any regression test must avoid it

Two nested aliases whose pointees are **both `Integer`** print `7 9` and look
like a passing control. They pass *because the wrong answer and the right answer
are the same value.* A test written that way cannot fail — it would have been
green through this entire bug. **Use two different pointee types.**

## What it changes

Prio 45 -> 55. The population is every class or record with a nested pointer
type, not templates. Fixing the specializer would not have touched it: the
specializer emits two ordinary class bodies, which is `plain` above.

Slug deliberately NOT renamed — it is cited elsewhere and a rename breaks those.

---

# 2026-09-05, frankD: there are TWO mechanisms, and one fix was going to miss one

Taking the repair (frankS located mechanism 1 and banked it; the ticket was
never claimed). Before writing anything I went back to the two probes that did
not fit my own model, and they do not fit because they are a different bug.

The problem with the earlier matrix: `b_diffptr` gives the two aliases
**different names** (`PC1`, `PC2`) and still fails. An alias-name collision in a
flat table cannot explain that — `PC2` is unique. So something else is also
wrong.

## The discriminating pair

Same program twice; the ONLY difference is whether the pointee is declared
before or after the alias inside the class body.

```pascal
{ j_noforward — pointee FIRST }                 { b_diffptr — pointee AFTER }
TA = class type TCell = record d: Integer; end;   TA = class type PC1 = ^TCell;
               PC1 = ^TCell; var h: PC1; end;                    TCell = record d: Integer; end; …
TB = class type TCell = record d: AnsiString; end; TB = class type PC2 = ^TCell;
               PC2 = ^TCell; var h: PC2; end;                    TCell = record d: AnsiString; end; …
```

| probe | alias names | pointee names | pointee is a forward ref | result |
| --- | --- | --- | --- | --- |
| **j_noforward** | different | same (`TCell`) | **no** | **OK** `7 hi` |
| **b_diffptr** | different | same (`TCell`) | **yes** | **REFUSED** |
| **l_bothdiff** | different | different | no | **OK** `7 hi` |
| **m_samealias** | **same** (`PCell`) | different | no | **REFUSED** |

Two rows carry it. `m_samealias` fails with **no forward reference anywhere and
different pointee names** — only the alias name is shared. `b_diffptr` fails with
**unique alias names**, and becomes correct the moment the pointee is moved above
it. One program, one line reordered, opposite verdicts.

## Mechanism 1 — the alias NAME (frankS's, confirmed)

`pasparser_decl.inc:6984` calls `RegisterPtrAlias` with the bare name and never
consults `ParsingClassBodyCi`, so `TA.PCell` and `TB.PCell` are one row.
`m_samealias` is the clean isolate: nothing else is shared.

## Mechanism 2 — the forward POINTEE name, and it is a separate site

`symtab.inc:16042 ResolvePendingPointerAliases`, line **16053**:

```pascal
targetName := GetSliceName(AliasTargetNOff[i], AliasTargetNLen[i]);
ci := FindUClass(targetName);
```

A `^T` written above `T` is legal Pascal and is deliberately deferred — the
`PtrElemDepth` guard tolerates the unknown name and this pass fixes it up
afterwards. **It fixes it up by BARE NAME, globally.** Both class bodies declare
`TCell`; `AddClassLikeType` correctly gave the second the qualified name
`TB.TCell` and left the bare one with the first, so `FindUClass('TCell')` hands
every deferred pointee the FIRST class's record. `b_diffptr` is the isolate.

This site is untouched by an owning-class column on the alias table *by itself* —
it does not read the alias name at all. A fix aimed only at mechanism 1 compiles
`m_samealias` and leaves `b_diffptr` exactly as broken, with no test failing
unless one is written for the forward spelling specifically.

## Why they were one bug in the matrix

Both are reached by the same everyday source, and the original repro triggers
BOTH at once — `PCell = ^TCell` with `TCell` written after it is the ordinary way
to spell a linked node, and the generic version inherits it. The earlier
"keyed on NEITHER name" reading was a correct observation of a wrong model:
there are two keys, and each probe defeats the other one's.

## What this means for the repair

One column still does it, which is the good news:

- add `AliasOwnerCi` (`-1` = not declared inside a class body — **-1 and loud,
  never `ci + 1`**, because class 0 is a real class);
- `FindTypeAlias` admits a row when `AliasOwnerCi < 0`, or it equals
  `ParsingClassBodyCi`, or it equals `MethImplOwnerCi` (the class declaration and
  the out-of-line method bodies are two separate source ranges and both must
  see the alias — a fix consulting only the first compiles the field and then
  fails in the method);
- `ResolvePendingPointerAliases` tries `FindNestedType(AliasOwnerCi[i],
  targetName)` before falling back to `FindUClass`.

The third bullet is the one that would have been missed. `normalise-dont-special-
case` says it in advance: fixed one arm of a double case, grep for the sibling
before closing.

## Regression test

`test/test_nested_pointer_alias_is_scoped_to_its_owner.pas`, and it must contain
BOTH spellings — pointee-before-alias and pointee-after-alias — or it passes
while half the bug is live. Every row uses two DIFFERENT pointee types for the
`f_same` reason recorded above.
## 2026-09-05 — repair owner is frankD; the sentinel choice is a CLASS, not a column decision

frankS located the mechanism and banked it; **frankD holds the repair** and has
the boundary matrix (two ordinary classes, `b_diffptr`, `c_diffcell`, `d_records`,
and the `f_same` trap). Locating is not a claim on repairing. Recorded because
the coordinator briefly relayed this as "frankS has the fix" — it never was one,
and a false coverage claim is the one direction of error that removes a row from
everyone's attention at once.

**On the owning-class sentinel: `-1` and loud, NOT `id + 1`** (frankB's
correction, frankD concurring). The `AliasEnumId` precedent does not transfer.
That column uses *id+1* because "not an enum alias" is the legitimate common
case, so forgetting the column had to be INERT. An owning-class column is the
opposite population: a `Register*Alias` site that says nothing about its owner is
a **bug**, not a silent majority. Cite the discriminator, not the encoding —
*if a caller saying nothing is a bug, be loud; if most callers legitimately have
nothing to say, bias the encoding so forgetting is inert.* Picking the wrong one
here gives a table that reads "owned by class 0" forever, and **class 0 is real.**

That generalises, and it is the same animal as two cases already written down:

| the unset value | collides with the legal value | so the guard |
| --- | --- | --- |
| owning class `id + 1` → 0 | class 0, a real class | cannot fail |
| `f_same`, both pointees `Integer` | the correct pointee type | cannot fail |
| `TypeStorageSize(tyUnknown)` = 4 | `sizeof(int)` = 4 (CLAUDE.md) | cannot fail |

**Wherever the unset value collides with a legal value, the guard cannot fail —
and the collision is invisible precisely because the colliding legal value is the
common one.** Ask of any sentinel, default or expected constant: *if the
machinery did nothing at all, would this still read correct?*
