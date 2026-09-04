program test_forward_interface_constraint_fail;
{ NEGATIVE half of test_forward_interface_decl. Answering `T: IInterface` as
  "the argument is an interface" must not become "any interface constraint is
  satisfied": the DIRECTION is the whole distinction, and fpc-testsuite
  tgenconstraint17 rejects exactly this pair.

  IInterface is ITest1's ANCESTOR, not a descendant, so this must not compile.
  fpc 3.2.2 refuses it too ("Incompatible types: got IUnknown expected
  ITest1"). bug-p-a-forward-interface-declaration-is-not-parsed }
{$mode objfpc}
type
  ITest1 = interface function A: Integer; end;
  generic TT<T: ITest1> = class v: T; end;
  TBad = specialize TT<IInterface>;
begin
end.
