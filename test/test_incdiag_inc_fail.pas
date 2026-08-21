program test_incdiag_inc_fail;
{ Carrier: the error is in incdiag/badinc.inc, not here.
  bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file }
{$I incdiag/badinc.inc}
begin
end.
