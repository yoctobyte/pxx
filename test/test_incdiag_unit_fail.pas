program test_incdiag_unit_fail;
{ Carrier: the error is in incdiag/badunit.pas, which this program only
  names as a unit. bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file }
uses badunit;
begin
  Foo;
end.
