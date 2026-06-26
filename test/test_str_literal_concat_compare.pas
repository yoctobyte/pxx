program test_str_literal_concat_compare;
{ Regression: a compile-time concat of string literals as a comparison operand
  must fold to a single literal and compare correctly — not crash.
  bug-string-literal-concat-compare-segfault. Also guards that folding keeps
  the literal tyString (Concat / managed assignment unaffected). }
var a: AnsiString;
begin
  a := 'abcdef';
  if a = 'abc' + 'def' then writeln('eq1') else writeln('neq1');   { eq1 }
  if a = 'abc' + 'xyz' then writeln('eq2') else writeln('neq2');   { neq2 }
  if 'ab' + 'cd' = 'abcd' then writeln('eq3') else writeln('neq3'); { eq3 }
  a := 'p' + 'q' + 'r';
  writeln(a);                                                       { pqr }
  writeln(Concat('hel', 'lo', ' ', 'world'));                       { hello world }
end.
