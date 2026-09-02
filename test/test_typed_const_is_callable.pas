{ The POSITIVE control for test_const_shadows_routine_fail: a const of a
  PROCEDURAL type is genuinely callable, and the refusal added for the shadowing
  case must not reach it. Without this row, "consts cannot be called" would look
  like a safe blanket rule.

  FPC answers 15 here too -- checked, not assumed. }
program test_typed_const_is_callable;
type TFn = function(a: Integer): Integer;
function Triple(a: Integer): Integer;
begin
  Triple := a * 3;
end;
const F: TFn = @Triple;
begin
  WriteLn(F(5));
end.
