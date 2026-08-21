program test_incdiag_main_fail;
{ The error is in THIS file, after a 100-line include. Reported as line 106
  until 2026-08-21 — an offset into the spliced text, in a 9-line file.
  No `in:` line is expected: the main source is the file the user named.
  bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file }
{$I incdiag/pad.inc}
var x: Integer;
begin
  x := 1;
  if then;
end.
