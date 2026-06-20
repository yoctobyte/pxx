program test_shortstring;
{ `shortstring` keyword and arrays of fixed-length strings. Interim: shortstring
  maps to a 255-cap tyFixedString (word-prefix layout); behaviour is a frozen
  255-char string. Validates the keyword resolves, sizes, and that an array of
  sized strings keeps elements independent (the size/offset bug class). }
var
  s: shortstring;
  arr: array[0..2] of string[16];
  i: Integer;
begin
  s := 'hello world';
  writeln(s);
  writeln(Length(s));
  arr[0] := 'Apple';
  arr[1] := 'Banana';
  arr[2] := 'Cherry';
  for i := 0 to 2 do
    writeln(arr[i]);
  if arr[0] = 'Apple' then writeln('arr0-ok') else writeln('arr0-BAD');
  if arr[1] = 'Banana' then writeln('arr1-ok') else writeln('arr1-BAD');
end.
