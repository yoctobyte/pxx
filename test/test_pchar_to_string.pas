program test_pchar_to_string;
{ bug-pchar-to-string-implicit-conv: a PChar binds a string/AnsiString parameter
  (overload match) and a string l-value (assignment), converting via PCharToString
  like FPC — no explicit cast, no extra `uses`. Uses a genuine NUL-terminated C
  buffer (the `pc := 'literal'` reverse direction is a separate gap). }
function f(const s: string): Integer; begin Result := Length(s); end;
function g(s: AnsiString): Integer; begin Result := Length(s); end;
var
  buf: array[0..3] of Char;
  pc: PChar;
  s: string;
begin
  buf[0] := 'a'; buf[1] := 'b'; buf[2] := 'c'; buf[3] := #0;
  pc := @buf[0];
  writeln(f(pc));            { 3  - PChar into const string param }
  writeln(g(pc));            { 3  - PChar into AnsiString param }
  s := pc;                   { assignment conversion }
  writeln(s);                { abc }
  writeln(Length(s));        { 3 }
end.
