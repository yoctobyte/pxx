program test_an_open_array_parameter_takes_no_default_in_a_record_method_fail;
{ bug-p-a-default-value-is-accepted-on-an-open-array-parameter -- MUST NOT COMPILE.

  The record-method parameter parser is the third of four and had the same hole.
  An ordinal default is used here rather than a string so the row cannot pass
  for the string-shape reason: `array of Integer = 5` printed an empty High
  under the free-routine version of this bug. }
type
  TR = record
    procedure M(const a: array of Integer = 5);
  end;
procedure TR.M(const a: array of Integer);
begin
  WriteLn(Length(a));
end;
var r: TR;
begin
  r.M;
end.
