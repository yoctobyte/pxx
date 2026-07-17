program test_widechar_var_concat;
{ Regression: string + WideChar-variable concatenation must convert the widechar
  to UTF-8, not crash. A WideChar var is a bare tyUInt16 (no distinct type); the
  single-sided string+ordinal form is unambiguously widechar building. Word+Word
  must stay integer addition (asserted too).
  See bug-pascal-widechar-var-to-string-other-contexts. }
var s: AnsiString; w: WideChar; a, b: Word;
begin
  w := WideChar($41);
  s := 'x' + w;          { previously segfaulted }
  writeln('concat=', s);
  s := w + 'y';          { widechar on the left }
  writeln('lconcat=', s);
  a := 1000; b := 2000;
  writeln('wordadd=', a + b);   { must stay integer addition, not string-building }
end.
