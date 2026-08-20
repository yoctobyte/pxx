program test_strict_dialect_reject;
{ Pulls in an UNMARKED unit whose overloads carry no `overload` directive. Under
  --strict-overload this must FAIL to compile; with no flag it must build and
  print 8, because the PXX dialect stays lax by default. Both halves are
  asserted -- an "it errors" test alone would also pass if the compiler had
  simply broken. }
uses strict_dialect_theirs_bad_unit;
begin
  Writeln(Quad(2));
end.
