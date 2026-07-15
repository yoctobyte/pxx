program test_copy_char_promote;
{$mode objfpc}
{ Copy() promotes a Char argument to a string, matching FPC (a single-quoted
  single character is typed Char, not string). Regression for pxx rejecting
  `Copy('a', i, n)` with a dynamic-array error. Covers a char literal, a char
  variable, and confirms the ordinary string-Copy path still works. }
var
  s: ansistring;
  c: char;
begin
  s := Copy('a', 1, 1);
  writeln('[', s, ']');            { [a] }
  c := 'z';
  s := Copy(c, 1, 1);
  writeln('[', s, ']');            { [z] }
  s := Copy('hello', 2, 3);
  writeln('[', s, ']');            { [ell] }
end.
