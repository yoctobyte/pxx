program test_widechar_var_to_string;
{ Regression: assigning a WideChar VARIABLE to a string must convert (UTF-8), not
  crash. WideChar collapses to tyUInt16 with no subtype marker, so a variable read
  is a bare tyUInt16 ident — the cast-only NodeIsWideCharVal missed it and the
  ordinal fell into the managed-assign-as-pointer path (segfault).
  See bug-pascal-widechar-var-to-string-segfault. }
var s: AnsiString; w: WideChar;
begin
  s := WideChar($41);   { direct value }
  writeln('direct=', s);
  w := WideChar($42);
  s := w;               { via a variable — previously segfaulted }
  writeln('viavar=', s);
end.
