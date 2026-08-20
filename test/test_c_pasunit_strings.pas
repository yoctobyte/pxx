program test_c_pasunit_strings;
{ The Pascal-driver ORACLE for c_pasunit_strings.c: the same unit, the same
  calls, the same output. The Makefile diffs the two programs' output, so a
  regression in the C driver's Pascal-unit compilation shows up as a
  difference rather than as a hand-maintained expected string that could be
  updated to match the bug.
  bug-a-c-driver-omits-rtl-stubs-for-an-imported-pascal-unit }
uses cpasunit_strings;
var
  buf: array[0..63] of Char;
  i: Integer;
begin
  writeln('lit=', LitLen);
  writeln('varlit=', ConcatVarLit);
  writeln('litvar=', ConcatLitVar);
  writeln('varvar=', ConcatVarVar);
  writeln('chain=', ConcatChain);
  for i := 1 to 7 do write(CharCodeAt(i), ' ');
  writeln;
  CopyTag(@buf[0], 64);
  writeln('tag=', PChar(@buf[0]));
end.
