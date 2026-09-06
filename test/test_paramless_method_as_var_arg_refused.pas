program test_paramless_method_as_var_arg_refused;
{ NEGATIVE test, and the guard on
  bug-p-a-parameterless-method-is-undefined-as-a-by-ref-argument.

  A `const` parameter takes a VALUE, so a call's result is a legal argument and
  there is nothing to bind — that is what
  test_paramless_method_as_const_byref_arg.pas asserts. A genuine `var`
  parameter DOES bind a variable, so the same argument must still be REFUSED.
  fpc 3.2.2 says "Can't take the address of constant expressions".

  This file exists because the by-ref method path has NO validator that rejects
  a non-lvalue argument: it relies on ByRefArgStartsExpression answering False
  to force the bare-lvalue parse. Widening that predicate from `const Variant`
  to `const` is therefore only safe while `var`, `out` and untyped stay
  outside it, and this is the row that says so. The free-function twin is
  test_paramless_fn_as_var_arg_refused.pas; both must stay red.

  AIMED, and this is the row's own positive control: the SAME file with `var`
  changed to `const` COMPILES and prints 5. So the refusal is about `var` and
  not about anything else in the fixture -- a "does not compile" assertion is
  otherwise satisfied by a typo, and that is the failure mode this note exists
  to close. Re-run it if you ever change this file.

  KNOWN WART, deliberately not asserted, and inherited from the twin: our
  message is still `undefined variable (CurI)`, which names a defined method
  undefined. Wrong wording on a correct refusal. The Makefile asserts only that
  this does not compile — pinning the wording would freeze the wart in place. }
{$mode objfpc}
type
  TFar = class procedure MVr(var n: Integer); end;
  TOwn = class
    FE: TFar;
    function CurI: Integer;
    procedure Go;
  end;
procedure TFar.MVr(var n: Integer); begin WriteLn(n); end;
function TOwn.CurI: Integer; begin CurI := 5; end;
procedure TOwn.Go;
begin
  FE.MVr(CurI);
end;
var o: TOwn;
begin
  o := TOwn.Create;
  o.FE := TFar.Create;
  o.Go;
end.
