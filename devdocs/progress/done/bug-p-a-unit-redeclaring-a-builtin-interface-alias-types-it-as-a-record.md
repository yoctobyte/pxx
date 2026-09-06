---
track: P
prio: 65
type: bug
blocked-by: []
status: done
owner: frankS
---

# A unit re-declaring a builtin interface alias makes it a `record`, and every call taking the interface is refused

`compiler/builtin/builtinheap.pas:461-466` declares `IInterface` and
`IUnknown = IInterface`. `lib/rtl/classes.pas:67-73` declares them AGAIN, on
purpose and with a comment saying why (*"FPC hands every unit
IInterface/IUnknown and HResult from System. pxx has no System"*). When a
program `uses` such a unit, the ALIAS loses its class row and a value declared
through it types as a bare `record`.

Minimal, measured 2026-09-06 at compiler `4dc48164a5ed`:

```pascal
unit shadow;                       { 7 lines }
{$mode objfpc}
interface
type
  IInterface = interface ['{00000000-0000-0000-C000-000000000046}'] end;
  IUnknown = IInterface;
implementation
end.
```
```pascal
{$mode objfpc}
program m3;
uses shadow;
procedure Take(a: IInterface); begin end;
var v: IUnknown;
begin Take(v); end.
{ pascal26:6: error: no overload of Take matches these arguments
    argument types: (record) }
```

## What separates the working cases from the broken one

Four cells, and only the last fails — which is what says it is the
RE-DECLARATION and not aliases, units, or interfaces:

| | result |
| --- | --- |
| builtin `IUnknown`, no `uses` | ok |
| `uses classes`, value typed `IInterface` | ok |
| own unit declaring `IMine` + `IMineAlias = IMine` | ok |
| own unit RE-declaring `IInterface` + `IUnknown = IInterface` | **`(record)`** |

So an interface alias in a used unit is fine; an interface alias whose target
name is ALSO declared by `builtinheap.pas` is not. `UClsAliasNOff/NLen/Ci`
exists precisely to make a class alias transparent to *"every class-name
consumer (var decls, X.Create, casts, is/as)"* — this is that table not being
reached, or being reached and bound to the wrong row, when the aliased name
resolves ambiguously.

## Why it ranks at 65

It is the whole of `test-fpjson#src:tools/install_lib_candidates.sh`, RED on
seven since 2026-09-04 (`b8e3b3010249`), and it is not an fpjson bug: the
fpjson suite runner fails to COMPILE, so 0 of 203 tests run. The failing call
is `fcl-fpcunit`'s `AssertNullIntf(msg, obj)` where `obj: IUnknown` — one line
of ordinary DUnit-compatible code.

`lib/rtl/classes.pas` is ours and re-declares these names deliberately, so
**any** program using `classes` and an `IUnknown`-typed value hits this. That
is a large surface, not a corpus curiosity.

## Not the pin

Checked, because the recipe builds with `$(PXX_STABLE)` and a pin-age failure
looks identical: the LIVE compiler at HEAD refuses the same file with the same
error. This is not inert-until-pinned.

## How it was found, which is a note about the diagnostic and not about this bug

The refusal said only `no overload of AssertNullIntf matches these arguments`.
`pasparser_call.inc`'s method-overload probe appended nothing, while the free
path at `pasparser_stmt.inc:8210` appends `OverloadReport`. Adding the argument
types to the method arm turned four wrong guesses into one measurement —
`(AnsiString, record)` names the defect outright. That fix landed with this
ticket.

## FIXED 2026-09-06 (frankD) — but the ROW is inert until a pin, and the summary above is wrong in two ways

### The mechanism is not what the title says

The alias does not "lose its class row" and nothing "types as a record". The
re-declared alias row is built correctly and **never consulted**:
`FindUClassAliasCi` returned the FIRST name match, so whichever row registered
first captured the name for the whole program, and builtinheap always registers
first. `var v: IUnknown` bound to **builtinheap's IInterface**.

Proved rather than argued: with `IUnknown = TMine` declared, passing `v` to a
parameter typed with the BUILTIN `IInterface` compiled cleanly. The binding was
not absent, it was wrong.

`(record)` is just how an interface prints in an overload report — the candidate
line said `Take(record)` too. Two different rows, both printing `record`, which
is why the message reads as nonsense.

**So the silent case is the dangerous one.** Where the two targets happen to be
compatible this compiles and binds the wrong type with no diagnostic at all. The
refusal is the lucky outcome.

### It is also neither about units nor about interfaces

Measured over eleven cells. It needs no unit and no `uses` — six lines in a
plain program reproduce it — and it is not specific to interfaces:
`IUnknown = TMine` over a **class** breaks identically. The discriminator is
only that the alias NAME collides with something builtinheap already declares.

### Fix

Resolution is now by SCOPE, mirroring `FindUClass`'s existing policy for `UCls`
rows exactly: current scope wins outright, then highest `UsesRankOf`, ties keep
the first row. One ranked scan (`FindUClassAliasRow`) shared by both alias
lookups, because `FindUClassNonRecord`'s own comment records what it cost the
last time two predicates disagreed about one name.

Two fixes, not one. The second is the interesting one: at PROGRAM scope
`CurrentUnitIdx` is -1, which is a real scope and not "unknown", so a guard
written `if CurrentUnitIdx >= 0` fixed the bug in a unit and left it live in a
program — the shorter repro and the harder one to notice.

### THE ROW WILL NOT GO GREEN TONIGHT

`test-fpjson` builds the suite runner with `$(PXX_STABLE)`. Measured: the
pinned compiler `8f21d04df626` still refuses the repro; HEAD accepts it. So
this is **fixed at HEAD, inert until pinned** — the class this repo has been
bitten by twice. Nothing further is owed on the code; the row clears on the
next pin.

### Verified at `4bfd73d70588`

Ten of the eleven cells fixed, the original repro compiles, `gate.sh quick`
GREEN. Guard wired as `test-core#625` with a POSITIVE CONTROL: the pinned
compiler refuses the fixture with the exact reported symptom.

One cell stays broken on purpose and is filed as
[[bug-p-an-alias-in-a-used-unit-loses-to-a-class-row-of-the-same-name]]: an
alias in a USED UNIT colliding with a real class row. That needs the class and
alias tables ranked together rather than another preference arm, which changes
name resolution compiler-wide and is not a change to land unmeasured before a
pin.

### Credit

frankS's four-cell table is what made this cheap — it had already excluded
aliases, units and interfaces as the cause, so the eleven-cell widening had
somewhere to start. Their two instrument fixes on the way in (the recipe piping
the diagnosis to /dev/null for two days, and the method-overload arm not
appending `OverloadReport`) are why the error named argument types at all.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b77e0d9ec.
