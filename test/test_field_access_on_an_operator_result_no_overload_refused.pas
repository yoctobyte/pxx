{$mode objfpc}
program test_field_access_on_an_operator_result_no_overload_refused;
{ `(x + y).v` where `+` on TFoo has NO operator declared.

  The negative control for the arm that made its sibling compile: a
  tyRecord-tagged AN_BINOP reaches the field/base walk whether or not an
  operator backs it, and handing it an address would turn "add two records'
  first qwords and read a field off the garbage" into something that compiles
  and prints. It must keep reaching IRLowerAST's refusal by name.

  Guarded by a FindOpOverload2 test in the arm itself, so this row is what
  proves the guard is present rather than assumed.
  bug-p-a-field-access-on-an-operator-result-does-not-lower }
type
  TFoo = record v: LongInt; end;

var
  x, y: TFoo;
begin
  x.v := 4; y.v := 5;
  WriteLn((x + y).v);
end.
