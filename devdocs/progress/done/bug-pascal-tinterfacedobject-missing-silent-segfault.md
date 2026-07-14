---
prio: 60
---

# `TInterfacedObject` does not exist — inheriting from it compiles, then segfaults under ARC

- **Type:** bug (missing diagnostic + RTL gap — silent runtime crash)
- **Track:** A — core (unknown base class silently accepted) + B (the RTL type)
- **Status:** done
  closure.

## Reproduction
```pascal
program tio2;
{$mode objfpc}{$interfaces com}
type
  IFoo = interface
    procedure Go;
  end;
  TFoo = class(TInterfacedObject, IFoo)   { TInterfacedObject is declared NOWHERE }
    procedure Go;
  end;
procedure TFoo.Go; begin writeln('go'); end;
procedure Use;
var f: IFoo;
begin
  f := TFoo.Create;
  f.Go;
end;
begin
  Use;                       { SIGSEGV on scope exit }
  writeln('survived scope exit');
end.
```
Compiles clean. `f.Go` even prints. It dies at scope exit: **exit 139**.

## What is actually wrong — two things
1. **There is no `TInterfacedObject` in the RTL.** It is the single most-written base class
   in FPC/Delphi interface code (it supplies `IInterface` + `_AddRef` / `_Release` /
   `QueryInterface`). Every interface test in tree declares its OWN, which is exactly why
   this was never noticed.
2. **An unknown base class name is silently accepted.** `class(TInterfacedObject, IFoo)`
   with no such type in scope should be a compile error naming it. Instead the heritage
   resolves to nothing and the class is built with no parent.

Under CORBA interfaces (the default, no refcounting) the damage stays hidden: nothing calls
the missing methods, so the program runs. Under `{$interfaces com}` the ARC path emits
`_AddRef`/`_Release` calls that dispatch through a parent that does not exist — hence the
crash at scope exit, far from the declaration.

## Why it matters
This is the shape that hurts: it compiles, it runs, it prints the right thing, and it dies
later on a path the author never wrote. Real FPC code opens with
`class(TInterfacedObject, IFoo)` as a matter of course, so a user's first interface program
hits it.

## Wanted
- Diagnostic: an unknown base-class name in a heritage list is an error, not a silent
  no-parent class. (Check the interface-name path too — `class(TFoo, INoSuchThing)`.)
- RTL: provide `IInterface` and `TInterfacedObject` (refcounted, `_AddRef`/`_Release`/
  `QueryInterface`) so the idiom works rather than merely failing loudly.

## Gate
`make test` + self-host byte-identical; the repro above either compiles-and-runs (once the
RTL type exists) or fails at COMPILE time — never segfaults.

## Log
- 2026-07-14 — resolved, commit 068ef1e1.
