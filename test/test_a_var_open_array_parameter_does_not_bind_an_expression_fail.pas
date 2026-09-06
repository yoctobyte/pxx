program test_a_var_open_array_parameter_does_not_bind_an_expression_fail;

{$mode objfpc}
{$modeswitch arrayoperators}

{ MUST NOT COMPILE. This is the positive control for the widening that let a
  CONST open-array parameter take an expression argument
  (ParamBindsAnExpression, pasparser_call.inc), and it is drawn from the
  population that widening is about: the same open-array parameter, one keyword
  different.

  `const r: array of T` is by-ref internally and is never a var-binding target,
  so `o.M(a + b)` binds a temporary and that is correct. `var r: array of T` IS
  a binding target -- the callee's writes are meant to reach the caller -- so an
  expression has nowhere to write back to.

  THE GREEN TEST NEXT DOOR CANNOT ASSERT THIS AND IT IS NOT ENOUGH. Its
  `var writes` row passes a BARE VARIABLE, and a bare variable followed by `)`
  takes the lvalue path whatever the gate says, so that row is green under the
  correct gate AND under a gate widened to every array parameter. It is a
  regression assertion, not a control. This file is the control: it is the only
  spelling whose answer changes if ProcParamIsConst is dropped from
  ParamBindsAnExpression.

  WE DIVERGE FROM FPC HERE, DELIBERATELY. fpc 3.2.2 COMPILES this program: it
  materialises `a + b` into a temporary, passes that by reference, and the
  callee's writes land in it and are discarded. Nobody writes `Bump(a + b)`
  meaning "throw the result away", so this is a divergence on code someone did
  not mean to write and matching fpc is not a goal (CLAUDE.md, "on par with the
  language, not with FPC"). Refusing leaves the mistake visible.

  The DIAGNOSTIC is the second half of the fix and is asserted by name in the
  Makefile row. It used to be `wrong number of parameters in call to TCls.Bump`
  for a call passing exactly one argument -- the arity tail fires whenever the
  index-driven loop stops before `)`, and it could not tell a genuine surplus
  (which starts at a comma) from an argument the loop cut short (which stops at
  an operator).
  bug-p-a-bracket-at-the-head-of-an-argument-cannot-be-an-operators-left-operand }

type
  TCls = class
    procedure Bump(var r: array of LongInt);
  end;

procedure TCls.Bump(var r: array of LongInt);
var i: LongInt;
begin
  for i := 0 to High(r) do r[i] := r[i] + 100;
end;

var
  o: TCls;
  a, b: array of LongInt;
begin
  o := TCls.Create;
  a := [1, 2, 3];
  b := [4, 5];
  o.Bump(a + b);
  WriteLn('COMPILED -- the var open-array door bound an expression');
end.
