program test_cross_funcname_field;
{ Function name as a synonym for Result when assigning to a record field or array
  element of the result (`Make.field := ...`), like FPC. `Result.field` already
  worked. x86-64 only (record-valued results are x86-64-only on cross targets). }
type TR = record a, b: Int64; n: Integer; end;
function Make(x: Int64; k: Integer): TR;
begin
  Make.a := x;
  Make.b := x * 2;
  Make.n := k;
end;
var r: TR;
begin
  r := Make(1000000000, 7);
  writeln('a=', r.a, ' b=', r.b, ' n=', r.n);
  r := Make(3, 9);
  writeln('a=', r.a, ' b=', r.b, ' n=', r.n);
end.
