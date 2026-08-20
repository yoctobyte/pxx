program test_strict_dialect_ownership;
{ --strict-overload scopes by DIALECT OWNERSHIP, not program-vs-unit.

  A unit that declares {$MODE PXX} is ours and is exempt; an unmarked unit is
  external FPC code and is policed. Both are pulled in here at once, so the
  program proves the two answers come from the same compilation rather than from
  two runs with different flags.

  The REJECTION half (an unmarked unit with an undirectived overload) cannot live
  in this program -- it has to fail the compile -- so it is
  strict_dialect_theirs_bad_unit, asserted separately in the Makefile. Without
  that half this test would pass equally well if the flag did nothing at all. }
uses strict_dialect_ours_unit, strict_dialect_theirs_unit;
begin
  Writeln(Twice(21), ' ', Twice('ab'));
  Writeln(Thrice(14), ' ', Thrice('c'));
end.
