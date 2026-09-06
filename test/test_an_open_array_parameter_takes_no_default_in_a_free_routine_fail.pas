program test_an_open_array_parameter_takes_no_default_in_a_free_routine_fail;
{ bug-p-a-default-value-is-accepted-on-an-open-array-parameter -- MUST NOT COMPILE.

  THE ARRAY-CONSTRUCTOR SPELLING IS THE ORDER CLAIM, not a second copy of the
  string one. `= ['x']` was already refused before this fix, but with `a string
  parameter's default must be a string literal` -- an open-array parameter
  records its ELEMENT kind, so the stringy check saw a string parameter and
  demanded the literal that the array check would then have rejected anyway. A
  refusal that tells you to write the thing it is about to refuse is a wrong
  diagnostic, not a differing one. The Makefile asserts the ARRAY message here,
  so the two checks cannot swap back. }
procedure P(const a: array of string = ['x']);
begin
  WriteLn(Length(a));
end;
begin
  P;
end.
