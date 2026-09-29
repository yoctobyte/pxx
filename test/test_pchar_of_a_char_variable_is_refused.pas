program test_pchar_of_a_char_variable_is_refused;
{ fpc 3.2.2: Illegal type conversion: "Char" to "PChar". }
var
  c: Char;
  p: PChar;
begin
  c := 'x';
  p := PChar(c);
  writeln(p);
end.
