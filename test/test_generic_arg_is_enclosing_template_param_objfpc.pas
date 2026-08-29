program test_generic_arg_is_enclosing_template_param_objfpc;
{ The objfpc arm of
  bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type.

  The defect is NOT Delphi-specific and this file is why it has its own test:
  `DelphiRewriteGenericUses` handles the Delphi surface as pattern A and the
  inline `specialize` as pattern B through ONE `isParamForm` test, so both
  spellings minted the same wrong alias. Reading the Delphi name on the
  procedure and concluding objfpc is unaffected is the mistake this guards.

  Expected values are FPC 3.2.2's. }
{$MODE OBJFPC}

type
  generic TCmp<T> = class
    Val: T;
  end;

  generic TDict<TKey, TValue> = class
    C: specialize TCmp<TKey>;
    K: TKey;
  end;

var
  d: specialize TDict<Integer, LongInt>;
  c: specialize TCmp<Integer>;
begin
  d := specialize TDict<Integer, LongInt>.Create;
  d.K := 5;
  c := specialize TCmp<Integer>.Create;
  c.Val := 9;
  if (d.K = 5) and (c.Val = 9) then writeln('ok   objfpc inline specialize')
  else writeln('FAIL objfpc inline specialize ', d.K, ' ', c.Val);
  writeln('total ok 1 / 1');
end.
