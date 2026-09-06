program test_generic_method_across_a_uses_clause;
{$mode objfpc}
{ A generic method declared in a unit, called from here.

  ExpandGenericMethod rewrites a generic method into one ordinary method per
  concrete type argument, in the token stream. Its edits must be at or above the
  class body, and a program calling a used unit's generic method is the one
  shape where a USE sits below it -- unit tokens are appended after the
  program's -- so the expansion used to bail out whole and the call died as a
  parse error ON THE UNIT'S DECLARATION.

  The declaration and the definition were never the problem: both are above the
  class body and always expanded safely. Only the CALL is behind TokPos, so only
  the call is deferred, to the end of the uses clause -- where every use is
  ahead again. That is the same window and the same reason as the free
  routine's SpecializeImportedGenericFuncUses, which had solved this for
  routines and not for methods.

  The class never has to gain a member late: the sweep can already see the
  program's uses when the unit's class body is parsed, so the specializations
  are emitted at declaration time and only their NAME was left generic.

  feature-p-a-generic-method-cannot-be-used-from-across-a-uses-clause }
uses uxgm, uxgmd, uxgmid;
type
  TInFile = class
    class generic function Half<T>(a: T): T;
  end;
class generic function TInFile.Half<T>(a: T): T;
begin Result := a - a + 3; end;
var
  t: TXG; d: TXD;
begin
  t := TXG.Create;
  d := TXD.Create;
  { objfpc `specialize` spelling, and two DIFFERENT type arguments for one
    method -- the deferred sweep must rewrite each use to its own name }
  WriteLn(t.specialize Add<Integer>(2, 3));
  WriteLn(t.specialize Add<String>('a', 'b'));
  { the same method without the `specialize` keyword }
  WriteLn(t.Add<Integer>(10, 5));
  { a CLASS generic method, on the class type, across the uses clause. This
    spelling never worked at all: `class generic function` put `class` BEFORE
    `generic`, the header scan stepped over `generic` only, and the emitted
    specialization came out as an ordinary method -- `cannot call non-static
    method on class type directly`, in one file, at the pin. }
  WriteLn(TXG.specialize Twice<Integer>(21));
  WriteLn(TInFile.specialize Half<Integer>(0));
  { the Delphi surface, which never writes `generic` }
  WriteLn(d.Add<Integer>(6, 7));
  { and a UNIT calling another unit's generic method, the program never
    mentioning it }
  WriteLn(ViaUnit);
end.
