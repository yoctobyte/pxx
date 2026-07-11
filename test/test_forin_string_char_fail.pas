{ %FAIL-style negative: for-in over a string requires a Char loop var. }
program test_forin_string_char_fail;
var s: string; b: byte;
begin
  s := 'abc';
  for b in s do write(b);
end.
