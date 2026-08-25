program test_diagnostic_names_the_right_unit;
{ Compiles a unit that MUST FAIL, to check the `in: <path>` line under the
  diagnostic. See test/srcmap_units/uspec.pas for what makes it hard. }
uses uspec;
begin
  WriteLn(Run);
end.
