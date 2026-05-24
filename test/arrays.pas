program Arrays;
var
  a: array[0..9] of Integer;
  b: array[0..4] of Char;
  i: Integer;

begin
  { Fill integer array }
  for i := 0 to 9 do
    a[i] := i * i;

  writeln('Squares:');
  for i := 0 to 9 do
    writeln(a[i]);

  { Char array }
  b[0] := 'H';
  b[1] := 'i';
  b[2] := '!';

  writeln(b[0]);
  writeln(b[1]);
  writeln(b[2]);
end.
