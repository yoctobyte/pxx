---
track: P
prio: 60
owner: frank1-ACP
---

# An interface method call picks the first slot of the name, not the matching overload

- **Type:** bug (silently wrong value)
- **Track:** P — Pascal frontend
- **Status:** done
- **Found:** 2026-08-20 (frank1-ACP), writing `test/test_interface_directives.pas`
  for [[feature-pascal-corpus-generics]].

## Repro

```pascal
program r;
{$mode objfpc}{$H+}
type
  IThing = interface
    function Compare(constref L, R: Integer): Integer; overload;
    function Compare(constref L, R: string): Integer; overload;
  end;
  TThing = class(TInterfacedObject, IThing)
    function Compare(constref L, R: Integer): Integer; overload;
    function Compare(constref L, R: string): Integer; overload;
  end;
{ both bodies: -1 / 0 / 1 by ordinary comparison }
var i: IThing;
begin
  i := TThing.Create;
  WriteLn(i.Compare(2, 5), ' ', i.Compare('b', 'a'));
end.
```

fpc 3.2.2 prints `-1 1`. pxx prints `-1 -1`: the second call takes the Integer
slot and compares the string arguments as integers.

## Why it matters

No error, no warning — a wrong number. That is the expensive failure mode this
repo's debugging playbook is built around, and it is reachable from any
interface that overloads a method name, which `IComparer<T>`-shaped APIs do
routinely.

## Root cause (measured, 2026-08-20)

Not the call site. `parser.inc`'s interface call path already resolves through
`FindUMethOverloadAhead`, and it picks the right IMT **slot**. The wrong binding
is one level down, in the **IMT builder** (`parser.inc`, the
`for imSlot := 0 to UClsMCount[tmpCi] - 1` loop): it filled every slot with

```pascal
mmi := FindUMeth(ci, imName);      { NAME only }
```

so all slots sharing a name got the class's FIRST method of that name.

The decisive measurement was to swap the two overloads' declaration order **in
the class only**, leaving the interface untouched:

| repro | pxx before | fpc 3.2.2 |
| --- | --- | --- |
| 1-arg then 2-arg in the class | `iface 101 101` | `iface 101 203` |
| 2-arg then 1-arg in the class | `iface 207 203` | `iface 101 203` |

`207` is `200 + 1 + <garbage>` — the 1-arg call landed in the 2-arg body. The
answer tracks the CLASS's declaration order, not the interface's, which is only
possible if the slot→proc binding is what is wrong. Had the parser been picking
the slot badly, swapping the class would have changed nothing.

Note the type-based repro above (`-1 -1`) and the arity-based one both come from
this single cause: neither arity nor types reach a name-only lookup.

## Fix

`FindUMethForSig(ci, name, sigProc)` in `symtab.inc` — the same parent-chain walk
as `FindUMethArity`, matching on the interface signature proc's arity, per-param
type kind, array-ness and class/record id, and falling back to the first name
match so single-method classes and the "does not implement" diagnostic are
unchanged. The IMT builder calls it per slot.

A second defect surfaced while writing that matcher and is fixed with it: the
interface-method registration computed `mPTypesRec[i]` per parameter and then
**dropped it** — never shifted it when Self was injected at index 0, never stored
it into `ProcParamRecId`. So every class-typed interface parameter was `REC_NONE`
and no signature comparison could have told two class-typed overloads apart. The
class-method path (`parser.inc:28660`/`28675`/`28708`) has always done both; this
path now mirrors it.

## Note

`test/test_interface_directives.pas` now carries the same-name case — three
`Compare` overloads (2×Integer, 2×string, 3×Integer), declared in a DIFFERENT
order in the class than in the interface so declaration position cannot pass by
accident, asserted through the interface AND directly on the class with
identical answers. Output is byte-identical to fpc 3.2.2.

## Log
- 2026-08-20 — resolved, commit 22e4d0860.
