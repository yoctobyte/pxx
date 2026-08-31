program test_generic_constraint_forward_stub_fail;
{ NEGATIVE: a FORWARD class stub does not satisfy a constraint naming a class
  deeper than TObject, even though the real declaration below the specialization
  does descend from it. fpc 3.2.2 rejects this at the specialization point --

    tgenconstraint39.pp(16,39) Error: Incompatible types: got "TTest" expected "TSomeClass"

  -- and so must we. This is fpc-testsuite tgenconstraint39, marked %FAIL, which
  we accepted until 2026-08-31: the constraint checker took an unconditional
  early exit on any forward stub, so nothing about it was ever checked.

  The rule is NOT "a forward stub is an error in its own right" -- that was this
  ticket's proposed fix before it was measured, and it is wrong. A stub is a
  class whose ancestry is TObject and which implements nothing YET, and fpc
  judges it as exactly that: `T: class` and `T: TObject` against a stub are
  ACCEPTED (both are guarded in test_generic_constraint_accept_control.pas),
  while `T: record`, a deeper named class, and any interface are refused.
  bug-p-generic-constraints-are-checked-before-the-type-section-closes }
{$mode objfpc}
type
  TSomeClass = class
  end;

  generic TGeneric<T: TSomeClass> = class
  end;

  TTest = class;

  TGenericTTest = specialize TGeneric<TTest>;

  TTest = class(TSomeClass)
  end;
begin
end.
