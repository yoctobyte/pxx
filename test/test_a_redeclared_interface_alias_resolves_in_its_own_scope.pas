{ A type ALIAS resolves by SCOPE, not by which row registered first.

  builtinheap declares `IInterface` and `IUnknown = IInterface`. Anything that
  re-declares those names -- lib/rtl/classes.pas does, deliberately -- used to
  lose: FindUClassAliasCi returned the FIRST name match, so the re-declared row
  was built correctly and NEVER CONSULTED, and every `var v: IUnknown` bound to
  builtinheap's IInterface. Silent where the two targets happened to be
  compatible; three phases later an overload refusal reading `(record)` against
  a candidate also printing `(record)` where they were not.

  That was the whole of test-fpjson: fcl-fpcunit's `AssertNullIntf(msg, obj)`
  with `obj: IUnknown` would not compile, so 0 of 203 tests ran.

  Rows 1-2 are the shape that was broken -- an alias from a USED UNIT, which is
  the fpjson case. Rows 5-6 are the controls that must not move: a non-colliding
  alias, and a colliding alias declared but never used to type anything.

  ROWS 3-4 ARE LOAD-BEARING AND LOOK REDUNDANT. They are the PROGRAM-scope half
  and they needed a SECOND fix: at program scope CurrentUnitIdx is -1, which is
  a real scope and not "unknown", so the obvious guard -- `if CurrentUnitIdx >= 0`
  -- fixed the unit case and left the program case live. Deleting rows 3-4
  because rows 1-2 "already cover it" restores exactly that half of the bug,
  and nothing else here would notice.

  The reason it was nearly missed is worth keeping: the ticket is called "a UNIT
  redeclaring a builtin interface alias", so every instinct reaches for a unit,
  and the program-scope case is BOTH the shorter repro and the invisible one.
  The name steered the test away from the smaller bug.

  STILL BROKEN ON PURPOSE, so do not read this file as covering the family: an
  alias in a USED UNIT whose name collides with a real CLASS row rather than
  with another alias (`IInterface = IMine` in a unit) is unfixed, because the
  ranked UCls scan runs to completion before the alias table is consulted at
  all. Filed as
  bug-p-an-alias-in-a-used-unit-loses-to-a-class-row-of-the-same-name.
  bug-p-a-unit-redeclaring-a-builtin-interface-alias-types-it-as-a-record }
{$mode objfpc}
program test_a_redeclared_interface_alias_resolves_in_its_own_scope;
uses ualias;

type
  TLocal = class(TObject)
    function Tag: Integer;
  end;
  { program-scope alias whose NAME collides with a builtin alias }
  IUnknown = TLocal;
  { non-colliding control }
  TLocalAlias = TLocal;
  { collides, declared, never used to type anything (control) }
  IInterface = TLocal;

function TLocal.Tag: Integer; begin Tag := 42; end;

{ takes the UNIT's interface: reachable only if `uses ualias` won the name }
function TakeIface(a: ualias.IUnknown): Integer;
begin
  if a = nil then TakeIface := 1 else TakeIface := 2;
end;

function TakeLocal(a: TLocal): Integer; begin TakeLocal := a.Tag; end;

var
  i: ualias.IUnknown;
  u: IUnknown;
  c: TLocalAlias;
begin
  i := nil;
  Writeln('1 unit alias  = ', TakeIface(i));
  Writeln('2 unit iface  = ', TakeIface(nil));
  u := TLocal.Create;
  Writeln('3 prog alias  = ', TakeLocal(u));
  Writeln('4 prog tag    = ', u.Tag);
  c := TLocal.Create;
  Writeln('5 control     = ', TakeLocal(c));
  Writeln('6 sum         = ', TakeIface(i) + TakeLocal(u));
  Writeln('IFACEALIASSCOPE OK');
end.
