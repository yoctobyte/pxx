program test_length_of_a_variant;
{ Length(), UpCase() and Copy() of a Variant work on the string it converts to,
  as fpc does. Every backend's Length read a Variant as a frozen inline string
  and returned its tag word; UpCase took the Char arm and Copy the dyn-array one. }
var v: Variant; s: AnsiString;
begin
  v := 'hello';
  writeln(Length(v));
  s := 'ab';
  v := s;
  writeln(Length(v));
  v := s + s + s;
  writeln(Length(v), ' ', Length(s + s + s));
  { UpCase and Copy take their STRING arm for a Variant too }
  v := ' aBcd ';
  writeln('[', UpCase(v), '] [', Copy(v, 2, 2), ']');
end.
