{ NEGATIVE CONTROL. A string literal longer than the char array it initialises
  must be REFUSED, not truncated. fpc 3.2.2 says
  `string length is larger than array of char length` and so do we.

  This is the row that fails if the pad loop is ever written as "copy min(len,
  want)": every positive row in test_char_array_string_init still passes, and a
  five-character literal quietly loses its last character. }
program test_char_array_literal_too_long_fail;
const
  c : array[1..4] of Char = 'ABCDE';
begin
  writeln(c[1]);
end.
