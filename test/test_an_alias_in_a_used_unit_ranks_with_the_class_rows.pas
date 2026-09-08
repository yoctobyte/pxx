{ FindUClass scanned the CLASS rows to completion and consulted the alias table
  only when that scan found NOTHING. So an alias in a used unit could never be
  seen while any unit anywhere declared a real class of the same name -- the
  scan always succeeded and the alias was never asked. The two tables are now
  ranked in ONE scan by UsesRankOf.

  ROW 'used-unit-alias' IS THE DEFECT. Rows 'reversed' and 'own' are the
  controls and they are the point: a fix that simply PREFERRED aliases passes
  the defect row and fails both, and the sibling fix that preferred a
  CURRENT-SCOPE alias outright could not reach the defect row at all. Ranking is
  the only answer that satisfies all three.

  ClassName is the readout because it names WHICH class was bound in one word;
  a field access would only tell us the binding was wrong by failing to compile,
  which cannot be a row of an output comparison.

  Expected values are the fpc 3.2.2 oracle.
  bug-p-an-alias-in-a-used-unit-loses-to-a-class-row-of-the-same-name }
program test_an_alias_in_a_used_unit_ranks_with_the_class_rows;

{$mode objfpc}

uses uclsranka, uclsrankb, uclsrankc, uclsrankd, uclsranke;

var s: TShared;
begin
  { the program's own clause ends with uclsrankd, whose alias is the latest }
  s := TShared.Create;
  WriteLn('prog ', s.ClassName);
  WriteLn('used-unit-alias ', WhichInE);
  WriteLn('reversed ', WhichInC);
  WriteLn('own ', WhichInD);
end.
