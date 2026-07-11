{ Regression driver: bug-pascal-missing-diagnostics-fail-tests — this file is
  a PASSING program; the companion *_fail variants below are embedded in the
  Makefile as expected-error compiles. Kept so TextFile stays a real record
  type (SizeOf(TextFile) = SizeOf(Text), previously a bare 4-byte word). }
program test_missing_diagnostics_fail;
var t: TextFile; u: Text;
begin
  if SizeOf(t) = SizeOf(u) then writeln('textfile=text');
  writeln(SizeOf(t) > 4);
end.
