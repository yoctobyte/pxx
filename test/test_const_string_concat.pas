program test_const_string_concat;
{ Regression: `+`-concatenation of char/string literals in an untyped const
  (bug-char-literal-concat-in-const-expr). Synapse's synacode builds its Base64
  reverse tables as `#$xx + #$xx + ...`. }
const T = #65 + #66;
const U = #$41 + #$42 + #$43;
const V = 'foo' + 'bar';
const W = 'x' + #45 + 'y';
var s: AnsiString;
begin
  writeln(T);            { AB }
  writeln(Length(T));    { 2 }
  writeln(U);            { ABC }
  writeln(Length(U));    { 3 }
  writeln(V);            { foobar }
  writeln(W);            { x-y }
  s := T;
  writeln(Ord(s[1]), ' ', Ord(s[2]));   { 65 66 }
end.
