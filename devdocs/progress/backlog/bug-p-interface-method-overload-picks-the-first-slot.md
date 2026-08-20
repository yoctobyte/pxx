---
track: P
prio: 60
---

# An interface method call picks the first slot of the name, not the matching overload

- **Type:** bug (silently wrong value)
- **Track:** P — Pascal frontend
- **Status:** backlog
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

## Cause (unverified — measure before writing this into a fix)

An interface is a UCls entry whose methods are slot signatures in declaration
order (`ci`'s IMT layout, `parser.inc` interface branch). The class-method path
resolves overloads through `FindUMethOverloadAhead`; the interface call path
appears to bind by name to the first matching UMeth instead. Confirm with
`PXXDBG` before changing anything.

## Note

`test/test_interface_directives.pas` deliberately uses two DIFFERENTLY named
methods so its expected output does not freeze this defect. Add the same-name
case to that test when this is fixed.
