program vref64;
{ Regression: a by-ref (var/const) Int64 param is a single pointer word, not a
  2-word value. The ARM32 word-based spill/caller once treated every Int64 param
  as 2 words, so a `var x: Int64` wrote a bogus high word over the next param —
  e.g. a managed-string param next to it became -1, crashing Length(). }
procedure Bump(var n: Int64);
begin
  n := n + 1000000000;
end;
procedure Tagged(const tag: AnsiString; var n: Int64; const tag2: AnsiString);
begin
  n := n * 2;
  writeln(tag, ' ', n, ' ', tag2);
end;
var a: Int64;
begin
  a := 5000000000;
  Bump(a);
  writeln('bumped=', a);
  a := 3000000000;
  Tagged('alpha', a, 'beta');
  writeln('final=', a);
end.
