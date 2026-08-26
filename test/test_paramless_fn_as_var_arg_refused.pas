program test_paramless_fn_as_var_arg_refused;
{ NEGATIVE test, and the guard on
  bug-p-a-parameterless-function-is-undefined-as-a-method-call-argument.

  A `const Variant` parameter accepts a call's RESULT because it never binds a
  variable. A genuine `var` parameter does bind one, so the same argument must
  still be REFUSED — fpc 3.2.2 says "Can't take the address of constant
  expressions".

  This file exists because the fix was tried UNGATED first, and ungating is a
  regression rather than a generalisation: the method by-ref path has no
  validator that rejects a non-lvalue argument — it relies on
  ByRefArgStartsExpression answering False to force the bare-lvalue parse. So
  ungated, this program COMPILED and a call result bound to a var parameter.

  KNOWN WART, deliberately not asserted: our message here is still
  `undefined variable (zero)`, which names a defined function undefined. It is
  wrong wording on a correct refusal, and it predates the fix — the const arm
  is what was actually broken. The Makefile therefore asserts only that this
  does not compile; pinning the wording would freeze the wart. }
{$mode objfpc}
type K = class function f(var b: Variant): Variant; end;
function K.f(var b: Variant): Variant; begin f := b; end;
function zero: Variant; begin zero := 7; end;
var o: K; v: Variant;
begin
  o := K.Create;
  v := o.f(zero);
  WriteLn(v);
end.
