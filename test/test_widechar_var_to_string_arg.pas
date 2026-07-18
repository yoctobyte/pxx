{ Regression: a WideChar variable passed to a string parameter. WideChar collapses
  to tyUInt16 with no subtype marker, so a bare `w: WideChar` read is a plain tyUInt16
  ident — the call-arg WideChar->string retry in MatchCallDelphiProcAddr only caught
  the explicit `WideChar(x)` cast, so `show(w)` failed overload resolution ("no
  overload matches"). FPC accepts it (implicit WideChar->string). Now a tyUInt16 arg
  is string-compatible on a failed as-is match, wrapped via __pxxWideCharToUTF8 —
  matching the assign path. Assign and concat were fixed earlier; this covers the arg
  context. See bug-pascal-widechar-var-to-string-other-contexts. }
program test_widechar_var_to_string_arg;
procedure show(const s: AnsiString); begin writeln('arg=', s); end;
var s: AnsiString; w: WideChar;
begin
  w := WideChar($41);
  s := w;                { assign }
  writeln('assign=', s);
  s := 'x' + w;          { concat }
  writeln('concat=', s);
  show(w);               { arg — the case this test guards }
end.
