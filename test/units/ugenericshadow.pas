unit ugenericshadow;
{ Support unit for test_generic_shadow_decl: exports a generic whose name the
  using program deliberately redeclares, plus a second generic the program
  really does specialize -- so the test can tell a rewrite that stopped firing
  everywhere from one that stopped firing only on declarations. }
{$MODE DELPHI}
interface
type
  TBox<T> = record
    V: T;
  end;

  TPairU<A, B> = record
    L: A;
    R: B;
  end;
implementation
end.
