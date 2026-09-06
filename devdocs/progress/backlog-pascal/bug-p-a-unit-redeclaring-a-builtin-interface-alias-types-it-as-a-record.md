---
track: P
prio: 65
type: bug
blocked-by: []
status: open
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
