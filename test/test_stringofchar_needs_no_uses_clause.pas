program test_stringofchar_needs_no_uses_clause;
{ FPC keeps StringOfChar in System, so a program with no uses clause calls it.
  Expected output is fpc 3.2.2's.
  task-b-nineteen-sysutils-names-that-fpc-keeps-in-system }
var
  s: AnsiString;
  c: Char;
begin
  writeln('[', StringOfChar('x', 3), ']');
  writeln('[', StringOfChar('-', 0), ']');
  writeln('[', StringOfChar('-', -4), ']');
  c := '#';
  s := StringOfChar(c, 5) + '|' + StringOfChar(' ', 2) + '|';
  writeln(s, ' ', Length(s));
  writeln(Length(StringOfChar('z', 1000)));
end.
